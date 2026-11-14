import 'dart:io';

/// 按最后修改时间淘汰旧文件，把目录体积压到 [maxBytes] 以内。
///
/// 纯 Dart 实现，方便在无 Flutter 环境下测试；[FileCache] 直接复用它。
/// 返回删除的文件数。
Future<int> evictOldestFiles(
  Directory dir, {
  required int maxBytes,
  void Function(String message)? log,
}) async {
  if (!await dir.exists()) return 0;

  var total = 0;
  final entries = <(File, FileStat)>[];
  await for (final item in dir.list()) {
    if (item is! File) continue;
    try {
      final stat = await item.stat();
      total += stat.size;
      entries.add((item, stat));
    } catch (_) {
      // 文件刚被删除或被占用，跳过
    }
  }
  if (total <= maxBytes) return 0;

  entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
  var deleted = 0;
  for (final entry in entries) {
    if (total <= maxBytes) break;
    try {
      await entry.$1.delete();
      total -= entry.$2.size;
      deleted++;
    } catch (_) {
      // 删除失败的下次再试
    }
  }
  log?.call('缓存超限清理：删除 $deleted 个文件，'
      '当前 ${(total / 1024 / 1024).toStringAsFixed(1)}MB / '
      '上限 ${(maxBytes / 1024 / 1024).toStringAsFixed(0)}MB');
  return deleted;
}
