import '../models/diary_entry.dart';
import 'cloud_storage_service.dart';
import 'local_diary_cache.dart';

/// 给用户看的同步错误。toString 直接作为 UI 文案，原始异常留在 cause 里打日志。
class SyncError implements Exception {
  SyncError(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

Object friendlySyncError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('401') || text.contains('unauthorized')) {
    return SyncError('WebDAV 账号或密码不正确，请在设置里检查', error);
  }
  if (text.contains('403') || text.contains('forbidden')) {
    return SyncError('WebDAV 拒绝访问，请检查账号权限或目录设置', error);
  }
  if (text.contains('404') || text.contains('not found')) {
    return SyncError('远端目录不存在，请检查 WebDAV 地址', error);
  }
  if (text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('connection') ||
      text.contains('socket') ||
      text.contains('network') ||
      text.contains('unreachable')) {
    return SyncError('无法连接 WebDAV 服务器，请检查网络或服务器地址', error);
  }
  return SyncError('同步失败，请稍后重试', error);
}

/// 一次同步的结果。error 非空表示这次对账失败，本地数据仍可用。
class SyncReport {
  const SyncReport({
    this.added = 0,
    this.changed = 0,
    this.removed = 0,
    this.skipped = false,
    this.error,
    this.elapsed = Duration.zero,
  });

  final int added;
  final int changed;
  final int removed;
  final bool skipped;
  final Object? error;
  final Duration elapsed;

  bool get hasChanges => added + changed + removed > 0;

  @override
  String toString() =>
      'SyncReport(added:$added, changed:$changed, removed:$removed, '
      'skipped:$skipped, error:$error, ${elapsed.inMilliseconds}ms)';
}

/// 本地优先的数据入口：先读本地缓存，再后台向远端对账。
///
/// 远端仍然只有 entries/{id}.json 一种文件，不新增索引文件、不改字段，
/// 因此旧版本 App 与本版本可以双向共存。
class DiaryRepository {
  DiaryRepository({
    required this.configId,
    required this.cloud,
    required this.cache,
    this.minSyncInterval = const Duration(seconds: 60),
    this.log,
  });

  final String configId;
  final CloudStorageService cloud;
  final LocalDiaryCache cache;

  /// 两次自动同步的最小间隔，避免切前台、切宝宝频繁触发 PROPFIND
  final Duration minSyncInterval;

  /// 日志回调（保持本类不依赖 Flutter，调用方传 debugPrint 即可）
  final void Function(String message)? log;

  bool _syncing = false;

  /// 本次进程内是否已经成功对账过。节流只用于抑制同一会话里的重复触发，
  /// 冷启动后的第一次同步必须执行，否则远端改动最多要等一个节流窗口才可见。
  bool _syncedThisSession = false;

  Future<bool> hasCachedData() => cache.exists();

  /// 读取全部本地条目。索引和 body 都是本地文件，不走网络。
  Future<List<DiaryEntry>> loadCached() => cache.readAllEntries();

  /// 只读索引（单个小文件），用于首屏先拿元数据。
  Future<List<CachedEntryMeta>> loadIndexMetas() async {
    final index = await cache.loadIndex();
    return index?.sorted ?? const [];
  }

  /// 按 id 读取一批本地 body，按日期倒序返回。
  Future<List<DiaryEntry>> loadEntries(Iterable<String> ids) async {
    final entries = await cache.readEntries(ids);
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  /// 分批同步。[onBatch] 每拉完一批回调一次，用于让 UI 先渲染最近的数据；
  /// 首批按远端 mtime 倒序（最近写入的条目先到），最多等一个网络往返就能出首屏。
  Future<SyncReport> sync({
    bool force = false,
    void Function(List<DiaryEntry> fetched, int done, int total)? onBatch,
    int batchSize = 40,
  }) async {
    if (_syncing) return const SyncReport(skipped: true);
    _syncing = true;
    final stopwatch = Stopwatch()..start();
    try {
      final index = await cache.loadIndex() ??
          CacheIndex(configId: configId, syncedAtMs: 0);
      final lastSyncedAt = await cache.loadSyncedAt() ?? index.syncedAtMs;
      final ageMs = DateTime.now().millisecondsSinceEpoch - lastSyncedAt;
      if (!force &&
          _syncedThisSession &&
          index.entries.isNotEmpty &&
          ageMs >= 0 &&
          ageMs < minSyncInterval.inMilliseconds) {
        return SyncReport(skipped: true, elapsed: stopwatch.elapsed);
      }

      final remote = await cloud.listEntryMeta();
      final remoteById = {for (final meta in remote) meta.id: meta};

      final needFetch = <String>[];
      for (final meta in remote) {
        final local = index.entries[meta.id];
        if (local == null ||
            !local.matchesRemote(
              remoteEtag: meta.etag,
              remoteMtimeMs: meta.mtimeMs,
              remoteSize: meta.size,
            )) {
          needFetch.add(meta.id);
        } else if (!await cache.hasEntry(meta.id)) {
          // 索引还在但 body 被清掉了（缓存被手动清理过）
          needFetch.add(meta.id);
        }
      }

      // 远端整体为空但本地有数据：可能是配置指错目录、服务端故障或权限变化。
      // 后台同步不能把本地缓存清空（用户会以为日记全丢了），
      // 只有用户显式下拉刷新（force）才接受"真的被清空"这个结果。
      if (remote.isEmpty && index.entries.isNotEmpty && !force) {
        return SyncReport(
          error: StateError('远端目录为空（本地缓存 ${index.entries.length} 条），'
              '已暂停同步以免误删本地数据；下拉刷新可强制对齐远端'),
          elapsed: stopwatch.elapsed,
        );
      }

      final removedIds = index.entries.keys
          .where((id) => !remoteById.containsKey(id))
          .toList(growable: false);

      // 最近写入的条目优先拉取，保证首批就是用户最可能先看到的
      final ordered = List<String>.from(needFetch)
        ..sort((a, b) {
          final am = remoteById[a]?.mtimeMs ?? 0;
          final bm = remoteById[b]?.mtimeMs ?? 0;
          return bm.compareTo(am);
        });

      final fetchedById = <String, DiaryEntry>{};
      final newEntries = <String, CachedEntryMeta>{};
      // 未变化的行先沿用，等批次里有新数据再覆盖
      final pendingIds = needFetch.toSet();
      for (final meta in remote) {
        if (pendingIds.contains(meta.id)) continue;
        final local = index.entries[meta.id];
        if (local != null) newEntries[meta.id] = local;
      }

      var done = 0;
      final total = ordered.length;
      final effectiveBatch =
          batchSize < 1 ? total.clamp(1, 1000) : batchSize;
      for (var i = 0; i < ordered.length; i += effectiveBatch) {
        final end =
            (i + effectiveBatch) < ordered.length ? i + effectiveBatch : ordered.length;
        final chunk = ordered.sublist(i, end);
        final chunkEntries = await cloud.readEntries(chunk);
        for (final entry in chunkEntries) {
          await cache.writeEntry(entry);
          fetchedById[entry.id] = entry;
          final meta = remoteById[entry.id];
          if (meta != null) {
            newEntries[entry.id] = CachedEntryMeta.fromEntry(
              entry,
              etag: meta.etag,
              mtimeMs: meta.mtimeMs,
              size: meta.size,
            );
          }
        }
        done += chunk.length;

        // 每批落一次索引：中途被杀掉也能保住已下载的部分
        final hasMore = end < ordered.length;
        if (hasMore) {
          await cache.saveIndex(CacheIndex(
            configId: configId,
            syncedAtMs: DateTime.now().millisecondsSinceEpoch,
            entries: newEntries,
          ));
        }
        onBatch?.call(chunkEntries, done, total);
      }

      // 拉取失败的新增条目：不写入索引，下次再试；老条目沿用旧行
      for (final meta in remote) {
        if (newEntries.containsKey(meta.id)) continue;
        final local = index.entries[meta.id];
        if (local != null) newEntries[meta.id] = local;
      }

      for (final id in removedIds) {
        await cache.removeEntry(id);
      }

      _syncedThisSession = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      final hasListChanges = needFetch.isNotEmpty || removedIds.isNotEmpty ||
          index.entries.length != newEntries.length;
      if (hasListChanges) {
        await cache.saveIndex(CacheIndex(
          configId: configId,
          syncedAtMs: now,
          entries: newEntries,
        ));
      } else {
        // 列表没变：只更新时间戳，不重写整份索引
        index.syncedAtMs = now;
        await cache.saveSyncedAt(now);
      }

      var added = 0;
      var changed = 0;
      for (final id in needFetch) {
        if (!fetchedById.containsKey(id)) continue;
        if (index.entries.containsKey(id)) {
          changed++;
        } else {
          added++;
        }
      }

      return SyncReport(
        added: added,
        changed: changed,
        removed: removedIds.length,
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      log?.call('[sync] 同步失败: $e');
      return SyncReport(error: friendlySyncError(e), elapsed: stopwatch.elapsed);
    } finally {
      _syncing = false;
    }
  }

  /// 保存条目：先写远端，成功后更新本地，保证本地不会出现远端没有的数据。
  Future<DiaryEntry> saveEntry(DiaryEntry entry) async {
    final saved = await cloud.saveDiaryEntry(entry);
    await cacheEntry(saved);
    return saved;
  }

  /// 远端已经保存成功，只补本地缓存（编辑页/详情页当前的写入路径）。
  Future<void> cacheEntry(DiaryEntry entry) async {
    await cache.writeEntry(entry);
    final index = await cache.loadIndex() ??
        CacheIndex(configId: configId, syncedAtMs: 0);
    index.entries[entry.id] = CachedEntryMeta.fromEntry(entry);
    await cache.saveIndex(index);
  }

  /// 远端已经删除成功，只清本地缓存。
  Future<void> forgetEntry(String id) async {
    await cache.removeEntry(id);
    final index = await cache.loadIndex();
    if (index == null) return;
    index.entries.remove(id);
    await cache.saveIndex(index);
  }
}
