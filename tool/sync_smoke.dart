// 纯 Dart 冒烟测试：不依赖 Flutter，验证本地缓存与差分同步的核心行为。
//
//   dart tool/sync_smoke.dart
//
// 覆盖：
//   1. 首次同步把远端全部条目落到本地
//   2. 第二次同步不重复下载未变化的条目
//   3. 只改一条时只下载这一条
//   4. 远端删除会清掉本地 body 与索引
//   5. 索引损坏时能自行重建
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:growth_diary/models/app_config.dart';
import 'package:growth_diary/models/diary_entry.dart';
import 'package:growth_diary/services/cloud_storage_service.dart';
import 'package:growth_diary/services/diary_repository.dart';
import 'package:growth_diary/services/local_diary_cache.dart';

int _failures = 0;

void _check(String name, bool ok, [String? detail]) {
  if (ok) {
    stdout.writeln('  ok   $name');
  } else {
    _failures++;
    stdout.writeln('  FAIL $name${detail == null ? '' : ' — $detail'}');
  }
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('dav_smoke_');
  final cloud = _FakeCloud();
  final cache = LocalDiaryCache(baseDir: Directory('${root.path}/cache'));
  final repo = DiaryRepository(
    configId: 'cfg-1',
    cloud: cloud,
    cache: cache,
    minSyncInterval: Duration.zero,
  );

  // 1. 首次同步
  for (var i = 0; i < 8; i++) {
    cloud.seed('e$i', DateTime(2026, 1, 1 + i), '标题 $i');
  }
  var report = await repo.sync(force: true);
  _check('首次同步 added=8', report.added == 8, '$report');
  _check('首次同步读取 8 条', cloud.readCalls == 8, '${cloud.readCalls}');
  var cached = await repo.loadCached();
  _check('本地 8 条', cached.length == 8, '${cached.length}');
  _check(
    '本地按日期倒序',
    cached.isNotEmpty && cached.first.date.isAfter(cached.last.date),
  );

  // 2. 无变化时不重复下载
  cloud.readCalls = 0;
  report = await repo.sync(force: true);
  _check('二次同步 added/changed=0',
      report.added == 0 && report.changed == 0, '$report');
  _check('二次同步读取 0 条', cloud.readCalls == 0, '${cloud.readCalls}');

  // 3. 只改一条
  cloud.mutate('e3', '改过的标题');
  cloud.readCalls = 0;
  report = await repo.sync(force: true);
  _check('增量同步 changed=1', report.changed == 1, '$report');
  _check('增量同步只读 1 条', cloud.readCalls == 1, '${cloud.readCalls}');
  final updated = await cache.readEntry('e3');
  _check('本地内容已更新', updated?.title == '改过的标题', updated?.title);

  // 4. 远端删除
  cloud.remove('e5');
  report = await repo.sync(force: true);
  _check('删除同步 removed=1', report.removed == 1, '$report');
  _check('本地 body 已删除', !await cache.hasEntry('e5'));
  cached = await repo.loadCached();
  _check('剩余 7 条', cached.length == 7, '${cached.length}');

  // 5. 索引损坏后重建
  final indexFile = File('${root.path}/cache/index.json');
  await indexFile.writeAsString('{ broken json');
  cached = await repo.loadCached();
  _check('索引损坏时读不到条目', cached.isEmpty, '${cached.length}');
  report = await repo.sync(force: true);
  _check('重建后重新拉取 7 条', report.added == 7, '$report');
  cached = await repo.loadCached();
  _check('重建后本地 7 条', cached.length == 7, '${cached.length}');

  // 6. 旧版客户端直接写入（不经过我们的索引）
  cloud.seed('legacy-1', DateTime(2026, 2, 1), '旧客户端写的');
  report = await repo.sync(force: true);
  _check('识别旧版写入 added=1', report.added == 1, '$report');
  _check(
    '旧版写入的条目可读',
    (await cache.readEntry('legacy-1'))?.title == '旧客户端写的',
  );

  await root.delete(recursive: true);
  stdout.writeln(_failures == 0
      ? '\n全部通过'
      : '\n$_failures 项失败');
  if (_failures != 0) exit(1);
}

/// 内存版 WebDAV 替身。ETag 由内容哈希生成，行为与远端文件属性一致。
class _FakeCloud implements CloudStorageService {
  final Map<String, DiaryEntry> _entries = {};
  final Map<String, String> _etag = {};
  int readCalls = 0;

  void seed(String id, DateTime date, String title) {
    _entries[id] = DiaryEntry(
      id: id,
      date: date,
      title: title,
      description: '正文 $id',
      ageInMonths: date.month,
    );
  }

  void mutate(String id, String title) {
    final old = _entries[id]!;
    _entries[id] = DiaryEntry(
      id: old.id,
      date: old.date,
      title: title,
      description: old.description,
      ageInMonths: old.ageInMonths,
    );
  }

  void remove(String id) {
    _entries.remove(id);
    _etag.remove(id);
  }

  String _tagFor(String id) {
    final json = jsonEncode(_entries[id]!.toJson());
    final bytes = utf8.encode(json);
    return '${bytes.length}-${json.hashCode}';
  }

  @override
  Future<List<RemoteEntryMeta>> listEntryMeta() async {
    return _entries.keys.map((id) {
      // 与真实服务端一致：每次 PROPFIND 都按当前文件内容重新算指纹
      final tag = _etag[id] = _tagFor(id);
      return RemoteEntryMeta(
        id: id,
        etag: tag,
        mtimeMs: tag.hashCode,
        size: utf8.encode(jsonEncode(_entries[id]!.toJson())).length,
      );
    }).toList();
  }

  @override
  Future<DiaryEntry?> readEntry(String id) async {
    readCalls++;
    final entry = _entries[id];
    _etag[id] = _tagFor(id);
    return entry;
  }

  @override
  Future<List<DiaryEntry>> readEntries(List<String> ids,
      {int concurrency = 4}) async {
    final result = <DiaryEntry>[];
    for (final id in ids) {
      final entry = await readEntry(id);
      if (entry != null) result.add(entry);
    }
    return result;
  }

  @override
  Future<List<DiaryEntry>> loadAllEntries() async =>
      (await readEntries(_entries.keys.toList()));

  @override
  Future<void> saveDiaryEntry(DiaryEntry entry) async {
    _entries[entry.id] = entry;
    _etag[entry.id] = _tagFor(entry.id);
  }

  @override
  Future<void> deleteEntry(DiaryEntry entry) async => remove(entry.id);

  @override
  Future<void> initialize(AppConfig config) async {}

  @override
  Future<void> saveConfig(AppConfig config) async {}

  @override
  Future<AppConfig?> loadConfig() async => null;

  @override
  Future<Uint8List?> downloadFile(String path) async => null;

  @override
  Future<File?> downloadToFile(String path,
          {String? targetFilePath, Function(double)? onProgress}) async =>
      null;

  @override
  Future<bool> fileExists(String path) async => false;

  @override
  Future<bool> uploadFile(String path, File file,
          {Function(double)? onProgress}) async =>
      false;

  @override
  Future<bool> uploadData(String path, Uint8List data,
          {Function(double)? onProgress}) async =>
      false;

  @override
  Future<String> uploadMedia(File file, String fileName) async => '';

  @override
  Future<String> uploadImageWithThumbnails(File file, String fileName) async =>
      '';

  @override
  Future<String> uploadVideoWithThumbnails(File file, String fileName) async =>
      '';

  @override
  bool get isInitialized => true;

  @override
  Future<void> clearCache() async {}

  @override
  Future<File?> saveToTempFile(String path, Uint8List? data) async => null;
}
