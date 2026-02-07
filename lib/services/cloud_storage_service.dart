import 'dart:io';
import 'dart:typed_data';
import '../models/diary_entry.dart';
import '../models/app_config.dart';

abstract class CloudStorageService {
  Future<void> initialize(AppConfig config);
  Future<void> saveConfig(AppConfig config);
  Future<AppConfig?> loadConfig();
  Future<void> saveDiaryEntry(DiaryEntry entry);
  Future<List<DiaryEntry>> loadAllEntries();
  Future<List<DiaryEntry>> loadEntriesPage(int offset, int limit);
  Future<Uint8List?> downloadFile(String path);
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
