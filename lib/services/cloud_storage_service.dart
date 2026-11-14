import 'dart:io';
import 'dart:typed_data';
import '../models/diary_entry.dart';
import '../models/app_config.dart';

/// 远端条目属性（来自 PROPFIND 目录列表），只含差分需要的字段。
class RemoteEntryMeta {
  const RemoteEntryMeta({
    required this.id,
    this.etag,
    required this.mtimeMs,
    required this.size,
  });

  final String id;

  /// ETag 视为不透明字符串；部分服务端不返回，此时为 null
  final String? etag;
  final int mtimeMs;
  final int size;
}

abstract class CloudStorageService {
  Future<void> initialize(AppConfig config);
  Future<void> saveConfig(AppConfig config);
  Future<AppConfig?> loadConfig();
  Future<void> saveDiaryEntry(DiaryEntry entry);
  Future<List<DiaryEntry>> loadAllEntries();

  /// 列出 entries/ 的远端属性，用于增量差分（1 次 PROPFIND）
  Future<List<RemoteEntryMeta>> listEntryMeta();

  /// 按 id 读取单条日记，不存在或解析失败返回 null
  Future<DiaryEntry?> readEntry(String id);

  /// 批量读取条目，内部限制并发，避免首次安装时上千次串行请求
  Future<List<DiaryEntry>> readEntries(List<String> ids,
      {int concurrency = 4});
  Future<Uint8List?> downloadFile(String path);
  Future<File?> downloadToFile(String path,
      {String? targetFilePath, Function(double)? onProgress});
  Future<bool> fileExists(String path);
  Future<bool> uploadFile(String path, File file,
      {Function(double)? onProgress});
  Future<bool> uploadData(String path, Uint8List data,
      {Function(double)? onProgress});
  Future<String> uploadMedia(File file, String fileName);
  Future<String> uploadImageWithThumbnails(File file, String fileName);
  Future<String> uploadVideoWithThumbnails(File file, String fileName);
  Future<void> deleteEntry(DiaryEntry entry);
  bool get isInitialized;

  // 缓存相关方法
  Future<void> clearCache();

  // 临时文件保存方法
  Future<File?> saveToTempFile(String path, Uint8List? data);
}
