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
import 'package:growth_diary/utils/cache_eviction.dart';
import 'package:growth_diary/utils/revision_merger.dart';

int _failures = 0;

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

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

  // 2b. 无变化时不应重写整份索引，只更新时间戳
  final indexFile = File('${root.path}/cache/index.json');
  final syncStateFile = File('${root.path}/cache/sync_state.json');
  final indexBefore = await indexFile.readAsBytes();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await repo.sync(force: true);
  final indexAfter = await indexFile.readAsBytes();
  _check('无变化时索引未被重写',
      _sameBytes(indexBefore, indexAfter), '${indexBefore.length} vs ${indexAfter.length}');
  _check('sync_state 已写入', await syncStateFile.exists());
  final stateJson =
      jsonDecode(await syncStateFile.readAsString()) as Map<String, dynamic>;
  _check('sync_state 带同步时间', stateJson['syncedAt'] is int);

  // 3. 只改一条
  cloud.mutate('e3', '改过的标题');
  cloud.readCalls = 0;
  report = await repo.sync(force: true);
  _check('增量同步 changed=1', report.changed == 1, '$report');
  _check('增量同步只读 1 条', cloud.readCalls == 1, '${cloud.readCalls}');
  final indexAfterChange = await indexFile.readAsBytes();
  _check('列表变化时索引被重写',
      !_sameBytes(indexAfter, indexAfterChange));
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

  // 7. 版本号与冲突裁决（纯逻辑）
  final now = DateTime(2026, 5, 1, 12);
  DiaryEntry e({int rev = 0, int updatedAt = 0, String title = '原题'}) =>
      DiaryEntry(
        id: 'rev-1',
        date: DateTime(2026, 4, 1),
        title: title,
        description: '正文',
        ageInMonths: 10,
        rev: rev,
        updatedAt: updatedAt,
      );

  var decision = decideEntrySave(
      incoming: e(), remote: null, deviceId: 'dev-a', now: now);
  _check('新建条目 rev=1', decision.entry?.rev == 1, '${decision.entry?.rev}');
  _check('新建不产生副本', decision.conflictCopy == null);

  decision = decideEntrySave(
      incoming: e(rev: 3, updatedAt: 100),
      remote: e(rev: 3, updatedAt: 100),
      deviceId: 'dev-a',
      now: now);
  _check('内容未变只递增 rev', decision.entry?.rev == 4 && !decision.hasConflict,
      '$decision');

  decision = decideEntrySave(
      incoming: e(rev: 5, updatedAt: 200, title: '本地改'),
      remote: e(rev: 2, updatedAt: 100, title: '远端旧'),
      deviceId: 'dev-a',
      now: now);
  _check('本地 rev 更高时本地做主版本',
      decision.entry?.title == '本地改' && decision.conflictCopy != null,
      '$decision');
  _check('远端旧内容被保留成副本',
      decision.conflictCopy?.title.contains('冲突副本') == true &&
          decision.conflictCopy?.id != 'rev-1',
      '${decision.conflictCopy}');

  decision = decideEntrySave(
      incoming: e(rev: 2, updatedAt: 100, title: '本地旧'),
      remote: e(rev: 5, updatedAt: 200, title: '远端新'),
      deviceId: 'dev-a',
      now: now);
  _check('远端 rev 更高时不覆盖远端', decision.entry == null, '$decision');
  _check('本地编辑被保留成副本',
      decision.conflictCopy?.title.contains('本地旧') == true, '$decision');

  // 旧条目（无版本信息）第一次被编辑：不应产生冲突副本
  decision = decideEntrySave(
      incoming: e(rev: 0, updatedAt: 0, title: '第一次改老日记'),
      remote: e(rev: 0, updatedAt: 0, title: '老日记'),
      deviceId: 'dev-a',
      now: now);
  _check('旧条目首次编辑不产生副本',
      decision.entry?.rev == 1 && !decision.hasConflict, '$decision');

  final down = now.subtract(const Duration(hours: 1));
  decision = decideEntrySave(
      incoming: e(rev: 4, updatedAt: now.millisecondsSinceEpoch, title: 'A'),
      remote: e(rev: 4, updatedAt: down.millisecondsSinceEpoch, title: 'B'),
      deviceId: 'dev-a',
      now: now);
  _check('同 rev 且时间差过大时两边都保留',
      decision.entry != null && decision.hasConflict, '$decision');

  // 旧队列文件兼容：缺字段按 0 处理
  final legacyJson = e().toJson()
    ..remove('rev')
    ..remove('updatedAt')
    ..remove('deviceId');
  final parsed = DiaryEntry.fromJson(legacyJson);
  _check('旧格式条目缺版本字段可解析',
      parsed.rev == 0 && parsed.updatedAt == 0 && parsed.deviceId == '');
  final roundTrip = DiaryEntry.fromJson(e(rev: 9, updatedAt: 123).toJson());
  _check('版本字段可往返序列化',
      roundTrip.rev == 9 && roundTrip.updatedAt == 123);

  // 8. 媒体缓存按最旧优先淘汰
  final mediaDir = Directory('${root.path}/media_cache');
  await mediaDir.create(recursive: true);
  final base = DateTime(2026, 1, 1);
  for (var i = 0; i < 5; i++) {
    final file = File('${mediaDir.path}/f$i.bin');
    await file.writeAsBytes(List<int>.filled(100, i));
    await file.setLastModified(base.add(Duration(hours: i)));
  }
  final deleted = await evictOldestFiles(mediaDir, maxBytes: 250);
  final remain = mediaDir.listSync().whereType<File>().toList();
  _check('缓存淘汰删除了文件', deleted == 3, '$deleted');
  _check('缓存淘汰后不超上限', remain.length == 2, '${remain.length}');
  _check('保留的是较新的文件',
      remain.every((f) => f.path.endsWith('f3.bin') || f.path.endsWith('f4.bin')),
      remain.map((f) => f.path.split('/').last).join(','));

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
  set conflictListener(void Function(DiaryEntry conflict)? listener) {}

  @override
  Future<DiaryEntry> saveDiaryEntry(DiaryEntry entry) async {
    _entries[entry.id] = entry;
    _etag[entry.id] = _tagFor(entry.id);
    return entry;
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
