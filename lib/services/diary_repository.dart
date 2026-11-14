import '../models/diary_entry.dart';
import 'cloud_storage_service.dart';
import 'local_diary_cache.dart';

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
  });

  final String configId;
  final CloudStorageService cloud;
  final LocalDiaryCache cache;

  /// 两次自动同步的最小间隔，避免切前台、切宝宝频繁触发 PROPFIND
  final Duration minSyncInterval;

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

  Future<SyncReport> sync({bool force = false}) async {
    if (_syncing) return const SyncReport(skipped: true);
    _syncing = true;
    final stopwatch = Stopwatch()..start();
    try {
      final index = await cache.loadIndex() ??
          CacheIndex(configId: configId, syncedAtMs: 0);
      final ageMs =
          DateTime.now().millisecondsSinceEpoch - index.syncedAtMs;
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

      final removedIds = index.entries.keys
          .where((id) => !remoteById.containsKey(id))
          .toList(growable: false);

      final fetched = await cloud.readEntries(needFetch);
      final fetchedById = {for (final entry in fetched) entry.id: entry};
      for (final entry in fetched) {
        await cache.writeEntry(entry);
      }

      // 索引以远端列表为准：拉到 body 的用新元数据，没变化沿用旧行。
      // 新增但拉取失败的不写进索引，下次同步会再试。
      final newEntries = <String, CachedEntryMeta>{};
      for (final meta in remote) {
        final fetchedEntry = fetchedById[meta.id];
        if (fetchedEntry != null) {
          newEntries[meta.id] = CachedEntryMeta.fromEntry(
            fetchedEntry,
            etag: meta.etag,
            mtimeMs: meta.mtimeMs,
            size: meta.size,
          );
        } else if (index.entries[meta.id] != null) {
          newEntries[meta.id] = index.entries[meta.id]!;
        }
      }

      for (final id in removedIds) {
        await cache.removeEntry(id);
      }

      _syncedThisSession = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      await cache.saveIndex(CacheIndex(
        configId: configId,
        syncedAtMs: now,
        entries: newEntries,
      ));

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
      return SyncReport(error: e, elapsed: stopwatch.elapsed);
    } finally {
      _syncing = false;
    }
  }

  /// 保存条目：先写远端，成功后更新本地，保证本地不会出现远端没有的数据。
  Future<void> saveEntry(DiaryEntry entry) async {
    await cloud.saveDiaryEntry(entry);
    await cacheEntry(entry);
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
