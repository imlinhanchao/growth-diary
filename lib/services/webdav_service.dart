import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:image/image.dart' as img;
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import '../models/diary_entry.dart';
import '../models/app_config.dart';
import 'cloud_storage_service.dart';
import 'file_cache.dart';

class WebDAVService implements CloudStorageService {
  webdav.Client? _client;
  String? _id;
  final FileCache _fileCache = FileCache();

  String _getBasePath() => 'growth_diary/$_id';

  String _getConfigPath() => '${_getBasePath()}/config.json';

  String _getEntriesPath() => '${_getBasePath()}/entries';

  String _getMediaPath(String fileName) => '${_getBasePath()}/media/$fileName';

  String _getThumbnailsPath(String fileName) =>
      '${_getBasePath()}/thumbnails/$fileName';

  @override
  Future<void> initialize(AppConfig config) async {
    debugPrint(
        'Initializing WebDAV for id: ${config.id}, url: ${config.webdavUrl}');
    if (config.webdavUrl.isNotEmpty && config.username.isNotEmpty) {
      _client = webdav.newClient(
        config.webdavUrl,
        user: config.username,
        password: config.password,
        debug: false,
      );
      _client!.setConnectTimeout(8000);
      _client!.setSendTimeout(8000);
      _client!.setReceiveTimeout(8000);

      _id = config.id;

      // 初始化文件缓存
      await _fileCache.initialize();

      // Create base directories if they don't exist
      final baseDir = _getBasePath();
      try {
        await _client!.mkdir(baseDir);
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir $baseDir: $e');
      }
      try {
        await _client!.mkdir(_getEntriesPath());
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir ${_getEntriesPath()}: $e');
      }
      try {
        await _client!.mkdir('${_getBasePath()}/media');
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir ${_getBasePath()}/media: $e');
      }
      try {
        await _client!.mkdir('${_getBasePath()}/thumbnails');
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir ${_getBasePath()}/thumbnails: $e');
      }
    }
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    if (_client == null || _id == null) return;

    try {
      final jsonString = jsonEncode(config.toJson());
      await _client!.write(
        _getConfigPath(),
        utf8.encode(jsonString),
      );
    } catch (e) {
      debugPrint('Error saving config: $e');
      rethrow;
    }
  }

  @override
  Future<AppConfig?> loadConfig() async {
    if (_client == null || _id == null) return null;

    try {
      final content = await _client!.read(_getConfigPath());
      final jsonData = jsonDecode(utf8.decode(content));
      return AppConfig.fromJson(jsonData);
    } catch (e) {
      debugPrint('Error loading config: $e');
      return null;
    }
  }

  @override
  Future<void> saveDiaryEntry(DiaryEntry entry) async {
    if (_client == null || _id == null) return;

    try {
      final jsonString = jsonEncode(entry.toJson());
      await _client!.write(
        '${_getEntriesPath()}/${entry.id}.json',
        utf8.encode(jsonString),
      );
    } catch (e) {
      debugPrint('Error saving diary entry: $e');
      rethrow;
    }
  }

  Future<List<DiaryEntry>> _loadEntriesFromDirectory() async {
    final files = await _client!.readDir(_getEntriesPath());
    final entries = <DiaryEntry>[];

    for (var file in files) {
      if (file.name != null && file.name!.endsWith('.json')) {
        try {
          final content =
              await _client!.read('${_getEntriesPath()}/${file.name}');
          final jsonData = jsonDecode(utf8.decode(content));
          final entry = DiaryEntry.fromJson(jsonData);
          entries.add(entry);
        } catch (e) {
          debugPrint('Error loading entry ${file.name}: $e');
        }
      }
    }

    // Sort by date descending
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Future<List<DiaryEntry>> loadAllEntries() async {
    debugPrint(
        'Loading entries for id: $_id, client initialized: ${_client != null}');
    if (_client == null || _id == null) return [];

    // 等待一小段时间，确保连接稳定
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      return await _loadEntriesFromDirectory();
    } catch (e) {
      debugPrint('Error loading entries: $e');
      // 如果是认证错误，等待更长时间后重试一次
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        debugPrint('Retrying after authentication error...');
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          return await _loadEntriesFromDirectory();
        } catch (retryError) {
          debugPrint('Retry also failed: $retryError');
        }
      }
      return [];
    }
  }

  @override
  Future<List<DiaryEntry>> loadEntriesPage(int offset, int limit) async {
    if (_client == null || _id == null) return [];

    try {
      final files = await _client!.readDir(_getEntriesPath());
      final jsonFiles = files
          .where((file) => file.name != null && file.name!.endsWith('.json'))
          .toList();

      // Sort files by modification time descending (newest first)
      jsonFiles.sort((a, b) {
        final aTime = a.mTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.mTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      final entries = <DiaryEntry>[];
      final startIndex = offset;
      final endIndex = (offset + limit).clamp(0, jsonFiles.length);

      for (var i = startIndex; i < endIndex; i++) {
        final file = jsonFiles[i];
        try {
          final content =
              await _client!.read('${_getEntriesPath()}/${file.name}');
          final jsonData = jsonDecode(utf8.decode(content));
          entries.add(DiaryEntry.fromJson(jsonData));
        } catch (e) {
          debugPrint('Error loading entry ${file.name}: $e');
        }
      }

      // Sort by date descending as final ordering
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    } catch (e) {
      debugPrint('Error loading entries page: $e');
      return [];
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    if (_client == null || _id == null) return false;

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';

      // 分离文件名和父目录路径
      final pathParts = fullPath.split('/');
      final fileName = pathParts.last;
      final parentPath = pathParts.sublist(0, pathParts.length - 1).join('/');

      // 获取父目录内容
      final parentContents = await _client!.readDir(parentPath);

      // 检查文件中是否有同名文件
      return parentContents.any((file) => file.name == fileName);
    } catch (e) {
      debugPrint('Error checking if file exists: $e');
      return false;
    }
  }

  @override
  Future<Uint8List?> downloadFile(String path) async {
    // 检查缓存
    final cachedData = await _fileCache.get(path);
    if (cachedData != null) {
      return cachedData;
    }

    if (_client == null) return null;

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      final data = await _client!.read(fullPath);
      final result = Uint8List.fromList(data);

      // 保存到缓存
      await _fileCache.put(path, result);
      debugPrint('Downloaded and cached media: $path');

      return result;
    } catch (e) {
      debugPrint('Error downloading media: $e');
      return null;
    }
  }

  @override
  Future<String> uploadMedia(File file, String fileName) async {
    if (_client == null || _id == null) {
      throw Exception('WebDAV client not initialized');
    }

    try {
      final path = _getMediaPath(fileName);
      await _client!.writeFromFile(file.path, path);
      return 'media/$fileName'; // 返回相对路径
    } catch (e) {
      debugPrint('Error uploading media: $e');
      rethrow;
    }
  }

  @override
  Future<bool> uploadFile(String path, File file,
      {Function(double)? onProgress}) async {
    if (_client == null || _id == null) {
      return false;
    }

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      await _client!.writeFromFile(
        file.path,
        fullPath,
        onProgress: onProgress != null
            ? (c, t) {
                if (t > 0) {
                  onProgress(c / t);
                }
              }
            : null,
      );
      debugPrint('Successfully uploaded file to: $fullPath');
      return true;
    } catch (e) {
      debugPrint('Error uploading file to $path: $e');
      return false;
    }
  }

  @override
  Future<bool> uploadData(String path, Uint8List data,
      {Function(double)? onProgress}) async {
    if (_client == null || _id == null) {
      return false;
    }

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      await _client!.write(
        fullPath,
        data,
        onProgress: onProgress != null
            ? (c, t) {
                if (t > 0) {
                  onProgress(c / t);
                }
              }
            : null,
      );
      debugPrint('Successfully uploaded data to: $fullPath');
      return true;
    } catch (e) {
      debugPrint('Error uploading data to $path: $e');
      return false;
    }
  }

  @override
  Future<String> uploadImageWithThumbnails(File file, String fileName) async {
    if (_client == null || _id == null) {
      throw Exception('WebDAV client not initialized');
    }

    try {
      // 上传原图
      final originalPath = _getMediaPath(fileName);
      await _client!.writeFromFile(file.path, originalPath);

      // 生成中号缩略图 (用于详情页)
      final image = img.decodeImage(await file.readAsBytes());
      if (image != null) {
        final mediumThumbnail = img.copyResize(image, width: 768);
        final mediumData = img.encodeJpg(mediumThumbnail, quality: 85);
        final mediumFileName = '${fileName}_medium.jpg';
        final mediumPath = _getThumbnailsPath(mediumFileName);
        await _client!.write(mediumPath, mediumData);

        // 生成小号缩略图 (用于时间轴)
        final smallThumbnail = img.copyResize(image, width: 400);
        final smallData = img.encodeJpg(smallThumbnail, quality: 80);
        final smallFileName = '${fileName}_small.jpg';
        final smallPath = _getThumbnailsPath(smallFileName);
        await _client!.write(smallPath, smallData);

        return 'media/$fileName|thumbnails/$mediumFileName|thumbnails/$smallFileName'; // 返回相对路径
      }

      return 'media/$fileName'; // 返回相对路径
    } catch (e) {
      debugPrint('Error uploading image with thumbnails: $e');
      rethrow;
    }
  }

  @override
  Future<String> uploadVideoWithThumbnails(File file, String fileName) async {
    if (_client == null || _id == null) {
      throw Exception('WebDAV client not initialized');
    }

    try {
      // 上传原视频
      final originalPath = _getMediaPath(fileName);
      await _client!.writeFromFile(file.path, originalPath);

      // 生成缩略图
      debugPrint('Generating thumbnail for video: ${file.path}');
      Uint8List? thumbnail;
      try {
        thumbnail = await VideoThumbnail.thumbnailData(
          video: file.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 768, // 中号缩略图
          quality: 75,
          timeMs: 1000, // 从第1秒开始获取缩略图
        );
        debugPrint(
            'getThumbnail result: ${thumbnail.isNotEmpty ? 'success (${thumbnail.length} bytes)' : 'null'}');
      } catch (e) {
        debugPrint('getThumbnail exception: $e');
        thumbnail = null;
      }

      if (thumbnail == null || thumbnail.isEmpty) {
        debugPrint(
            'Failed to generate video thumbnail for $fileName, trying alternative method');
        // 尝试不同的参数
        try {
          thumbnail = await VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 768,
            quality: 75,
            timeMs: 0, // 从开始位置
          );
          debugPrint(
              'Alternative VideoThumbnail result: ${thumbnail.isNotEmpty ? 'success (${thumbnail.length} bytes)' : 'null'}');
        } catch (e) {
          debugPrint('Alternative VideoThumbnail exception: $e');
          thumbnail = null;
        }
      }

      if (thumbnail == null || thumbnail.isEmpty) {
        debugPrint(
            'All thumbnail generation methods failed for $fileName, using default thumbnail');
        // 生成默认缩略图 - 简单的灰色背景
        final defaultImage = img.Image(width: 400, height: 300);
        img.fillRect(defaultImage,
            x1: 0,
            y1: 0,
            x2: 400,
            y2: 300,
            color: img.ColorUint8.rgba(150, 150, 150, 255)); // 灰色背景

        thumbnail = img.encodeJpg(defaultImage, quality: 75);
      }

      final mediumFileName = '${fileName}_medium.jpg';
      final mediumPath = _getThumbnailsPath(mediumFileName);
      await _client!.write(mediumPath, thumbnail);

      // 生成小号缩略图
      final image = img.decodeImage(thumbnail);
      if (image != null) {
        final smallThumbnail = img.copyResize(image, width: 400);
        final smallData = img.encodeJpg(smallThumbnail, quality: 70);
        final smallFileName = '${fileName}_small.jpg';
        final smallPath = _getThumbnailsPath(smallFileName);
        await _client!.write(smallPath, smallData);

        return 'media/$fileName|thumbnails/$mediumFileName|thumbnails/$smallFileName'; // 返回相对路径
      } else {
        debugPrint('Failed to decode thumbnail image for $fileName');
        // 如果无法解码图片，返回只有视频路径
        return 'media/$fileName||'; // 返回空缩略图路径
      }
    } catch (e) {
      debugPrint('Error uploading video with thumbnails: $e');
      // 如果出现错误，只返回视频路径
      return 'media/$fileName||';
    }
  }

  @override
  Future<void> deleteEntry(DiaryEntry entry) async {
    if (_client == null || _id == null) return;

    try {
      // 删除所有相关的媒体文件
      final allMediaPaths = [
        ...entry.imagePaths,
        ...entry.videoPaths,
        ...entry.imageThumbnails,
        ...entry.videoThumbnails,
      ];

      for (final path in allMediaPaths) {
        try {
          // 媒体文件现在在当前宝宝的文件夹中
          final fullPath = '${_getBasePath()}/$path';
          await _client!.remove(fullPath);
          debugPrint('Deleted media file: $fullPath');
        } catch (e) {
          debugPrint('Error deleting media file $path: $e');
          // 继续删除其他文件，即使某个文件删除失败
        }
      }

      // 删除条目JSON文件
      await _client!.remove('${_getEntriesPath()}/${entry.id}.json');
      debugPrint('Deleted entry: ${entry.id}');
    } catch (e) {
      debugPrint('Error deleting entry: $e');
      rethrow;
    }
  }

  @override
  bool get isInitialized => _client != null;

  @override
  Future<void> clearCache() async {
    await _fileCache.clear();
  }

  @override
  Future<File?> saveToTempFile(String path, Uint8List? data) async {
    try {
      final mediaData = data ?? await downloadFile(path);
      if (mediaData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final fileName = path.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(mediaData);
      return tempFile;
    } catch (e) {
      debugPrint('Error saving to temp file: $e');
      return null;
    }
  }
}
