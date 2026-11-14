import 'dart:convert';
import 'dart:io';

import '../models/diary_entry.dart';

/// 本地索引中的一行。只放列表渲染与差分需要的字段，
/// 正文（description、缩略图、媒体路径）仍从 entries/{id}.json 懒读。
class CachedEntryMeta {
  CachedEntryMeta({
    required this.id,
    required this.dateMs,
    required this.ageInMonths,
    required this.title,
    required this.imageCount,
    required this.videoCount,
    this.etag,
    required this.mtimeMs,
    required this.size,
  });

  final String id;

  /// 毫秒时间戳。索引里存 int 而不是 ISO 字符串，
  /// 2000 条能省掉约 90ms 的 DateTime.parse 开销。
  final int dateMs;
  final int ageInMonths;
  final String title;
  final int imageCount;
  final int videoCount;

  /// 远端 PROPFIND 返回的 ETag，缺失时为 null
  final String? etag;

  /// 远端 mtime（毫秒），用于 ETag 缺失时的兜底比对
  final int mtimeMs;

  /// 远端文件字节数，与 mtime 一起兜底比对
  final int size;

  factory CachedEntryMeta.fromEntry(
    DiaryEntry entry, {
    String? etag,
    int mtimeMs = 0,
    int size = 0,
  }) {
    return CachedEntryMeta(
      id: entry.id,
      dateMs: entry.date.millisecondsSinceEpoch,
      ageInMonths: entry.ageInMonths,
      title: entry.title,
      imageCount: entry.imagePaths.length,
      videoCount: entry.videoPaths.length,
      etag: etag,
      mtimeMs: mtimeMs,
      size: size,
    );
  }

  /// 指纹比对：ETag 双方都有就只信 ETag，否则退回 mtime + size。
  /// ETag 视为不透明字符串，不做格式假设。
  bool matchesRemote({String? remoteEtag, required int remoteMtimeMs, required int remoteSize}) {
    final localTag = etag?.trim();
    final remoteTag = remoteEtag?.trim();
    if (localTag != null &&
        localTag.isNotEmpty &&
        remoteTag != null &&
        remoteTag.isNotEmpty) {
      return localTag == remoteTag;
    }
    return mtimeMs == remoteMtimeMs && size == remoteSize;
  }

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateMs': dateMs,
        'ageInMonths': ageInMonths,
        'title': title,
        'imageCount': imageCount,
        'videoCount': videoCount,
        if (etag != null) 'etag': etag,
        'mtime': mtimeMs,
        'size': size,
      };

  factory CachedEntryMeta.fromJson(Map<String, dynamic> json) {
    return CachedEntryMeta(
      id: json['id'] as String,
      dateMs: json['dateMs'] as int? ??
          DateTime.parse(json['date'] as String).millisecondsSinceEpoch,
      ageInMonths: json['ageInMonths'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      imageCount: json['imageCount'] as int? ?? 0,
      videoCount: json['videoCount'] as int? ?? 0,
      etag: json['etag'] as String?,
      mtimeMs: json['mtime'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
    );
  }
}

class CacheIndex {
  CacheIndex({
    required this.configId,
    required this.syncedAtMs,
    Map<String, CachedEntryMeta>? entries,
  }) : entries = entries ?? <String, CachedEntryMeta>{};

  static const int schemaVersion = 2;

  final String configId;
  int syncedAtMs;
  final Map<String, CachedEntryMeta> entries;

  List<CachedEntryMeta> get sorted =>
      entries.values.toList()..sort((a, b) => b.dateMs.compareTo(a.dateMs));

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'configId': configId,
        'syncedAt': syncedAtMs,
        'entries': sorted.map((e) => e.toJson()).toList(),
      };

  factory CacheIndex.fromJson(Map<String, dynamic> json) {
    final index = CacheIndex(
      configId: json['configId'] as String? ?? '',
      syncedAtMs: json['syncedAt'] as int? ?? 0,
    );
    final list = json['entries'] as List<dynamic>? ?? const [];
    for (final item in list) {
      final meta = CachedEntryMeta.fromJson(item as Map<String, dynamic>);
      index.entries[meta.id] = meta;
    }
    return index;
  }
}

/// 条目与索引的本地持久化。刻意不依赖 Flutter，方便用纯 Dart 脚本验证。
///
/// 目录结构：
///   <baseDir>/index.json
///   <baseDir>/entries/{id}.json
class LocalDiaryCache {
  LocalDiaryCache({required this.baseDir});

  final Directory baseDir;

  File get _indexFile => File('${baseDir.path}/index.json');
  File get _syncStateFile => File('${baseDir.path}/sync_state.json');
  Directory get _entriesDir => Directory('${baseDir.path}/entries');

  Future<bool> exists() async => _indexFile.exists();

  Future<CacheIndex?> loadIndex() async {
    try {
      if (!await _indexFile.exists()) return null;
      final raw = await _indexFile.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['schema'] != CacheIndex.schemaVersion) return null;
      return CacheIndex.fromJson(json);
    } catch (_) {
      return null; // 损坏当作不存在，由 Repository 重建
    }
  }

  Future<void> saveIndex(CacheIndex index) async {
    await _writeAtomic(_indexFile, jsonEncode(index.toJson()));
    await saveSyncedAt(index.syncedAtMs);
  }

  /// 只记录"上次同步时间"。索引没变化时不再整体重写几 MB 的 index.json，
  /// 2000 条约 426KB，每次启动都写一遍纯属浪费。
  Future<void> saveSyncedAt(int syncedAtMs) async {
    await _writeAtomic(
      _syncStateFile,
      jsonEncode({
        'syncedAt': syncedAtMs,
        'configId': baseDir.path.split(Platform.pathSeparator).last,
      }),
    );
  }

  /// 读取上次同步时间；缺失时返回 null，由调用方回退到索引里的值。
  Future<int?> loadSyncedAt() async {
    try {
      if (!await _syncStateFile.exists()) return null;
      final json = jsonDecode(await _syncStateFile.readAsString());
      final value = (json as Map<String, dynamic>)['syncedAt'];
      return value is int ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<DiaryEntry?> readEntry(String id) async {
    final file = File('${_entriesDir.path}/$id.json');
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return DiaryEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 批量读取 body。并发分批，避免上千次串行 IO。
  Future<List<DiaryEntry>> readEntries(
    Iterable<String> ids, {
    int batchSize = 32,
  }) async {
    final idList = ids.toList();
    final result = <DiaryEntry>[];
    for (var i = 0; i < idList.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, idList.length);
      final chunk = idList.sublist(i, end);
      final loaded = await Future.wait(chunk.map(readEntry));
      result.addAll(loaded.whereType<DiaryEntry>());
    }
    return result;
  }

  /// 按索引顺序读取全部 body（时间轴需要正文与缩略图路径）。
  Future<List<DiaryEntry>> readAllEntries() async {
    final index = await loadIndex();
    if (index == null) return const [];
    final entries = await readEntries(index.sorted.map((e) => e.id));
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  Future<void> writeEntry(DiaryEntry entry) async {
    await _entriesDir.create(recursive: true);
    await _writeAtomic(
      File('${_entriesDir.path}/${entry.id}.json'),
      jsonEncode(entry.toJson()),
    );
  }

  Future<void> removeEntry(String id) async {
    final file = File('${_entriesDir.path}/$id.json');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败不影响后续重建
    }
  }

  Future<bool> hasEntry(String id) =>
      File('${_entriesDir.path}/$id.json').exists();

  Future<void> clear() async {
    try {
      if (await baseDir.exists()) {
        await baseDir.delete(recursive: true);
      }
    } catch (_) {
      // ignore
    }
  }

  /// 临时文件 + 替换。先写同目录 tmp 再 rename，避免断电/崩溃留下半截文件。
  Future<void> _writeAtomic(File target, String content) async {
    await target.parent.create(recursive: true);
    // 唯一 tmp 名：同步与编辑保存可能并发写同一份索引，固定名字会互相踩
    final tmp = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(content, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // Windows 上 rename 覆盖已存在文件会失败，退化为先删再改名
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
    }
  }
}
