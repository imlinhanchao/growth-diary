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
import 'local_storage_service.dart';
import 'network_service.dart';

class WebDAVService implements CloudStorageService {
  webdav.Client? _client;
  String? _id;
  AppConfig? _config;
  String? _currentUrl;
  final FileCache _fileCache = FileCache();
  final LocalStorageService _localStorage = LocalStorageService();

  String _getBasePath() => 'growth_diary/$_id';

  String _getConfigPath() => '${_getBasePath()}/config.json';

  String _getEntriesPath() => '${_getBasePath()}/entries';

  String _getMediaPath(String fileName) => '${_getBasePath()}/media/$fileName';

  String _getThumbnailsPath(String fileName) =>
      '${_getBasePath()}/thumbnails/$fileName';

  /// 当前实际连接的 WebDAV 地址
  String? get currentUrl => _currentUrl;

  /// 根据当前网络环境（连接的 WiFi）解析应生效的 WebDAV 地址
  Future<String> resolveEffectiveUrl(AppConfig config) async {
    final defaultWebdavUrl =
        await _localStorage.getString('defaultWebdavUrl:${config.webdavUrl}') ??
            config.webdavUrl;

    // 1. 获取当前连接的 WiFi SSID
    final currentSsid = await NetworkService.getCurrentWifiSSID();

    // 2. 如果连接了特定 WiFi，查找绑定了该 WiFi 的镜像
    if (currentSsid != null && currentSsid.isNotEmpty) {
      final matchingMirror = config.getMirrorForWifi(currentSsid);
      if (matchingMirror != null && matchingMirror.url.isNotEmpty) {
        debugPrint(
            'WebDAV WiFi 匹配成功: SSID="$currentSsid" -> 切换镜像: ${matchingMirror.url}');
        return matchingMirror.url;
      }
    }

    // 3. 否则使用未绑定特定 WiFi 的镜像或默认配置
    // 如果用户设置了默认载入镜像，且该镜像没有绑定不匹配的 WiFi，优先使用
    if (defaultWebdavUrl.isNotEmpty) {
      final defaultMirror = config.webdavMirrors.cast<WebDavMirror?>().firstWhere(
            (m) => m != null && m.url == defaultWebdavUrl,
            orElse: () => null,
          );
      if (defaultMirror == null ||
          !defaultMirror.hasWifiBinding ||
          (currentSsid != null && defaultMirror.matchesWifi(currentSsid))) {
        return defaultWebdavUrl;
      }
    }

    // 优先使用没有配置 WiFi 的通用镜像
    final unboundMirror = config.defaultUnboundMirror;
    if (unboundMirror != null && unboundMirror.url.isNotEmpty) {
      return unboundMirror.url;
    }

    // 降级使用主配置地址
    if (config.webdavUrl.isNotEmpty) {
      return config.webdavUrl;
    }

    // 降级使用第一个镜像地址
    if (config.webdavMirrors.isNotEmpty) {
      return config.webdavMirrors.first.url;
    }

    return '';
  }

  /// 确保 WebDAV 客户端与当前网络环境匹配
  Future<webdav.Client?> _ensureClient() async {
    if (_config == null) return _client;

    final effectiveUrl = await resolveEffectiveUrl(_config!);
    if (effectiveUrl.isEmpty) return _client;

    if (_client == null || _currentUrl != effectiveUrl) {
      debugPrint(
          'Initializing WebDAV for id: ${_config!.id}, url: $effectiveUrl (was: $_currentUrl)');
      _currentUrl = effectiveUrl;
      _client = webdav.newClient(
        effectiveUrl,
        user: _config!.username,
        password: _config!.password,
        debug: false,
      );
      _client!.setConnectTimeout(15000);
      _client!.setSendTimeout(60000);
      _client!.setReceiveTimeout(60000);
    }

    return _client;
  }

  @override
  Future<void> initialize(AppConfig config) async {
    _config = config;
    _id = config.id;

    // 初始化文件缓存
    await _fileCache.initialize();

    final client = await _ensureClient();
    if (client != null && _id != null) {
      // Create base directories if they don't exist
      final baseDir = _getBasePath();
      try {
        await client.mkdir(baseDir);
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir $baseDir: $e');
      }
      try {
        await client.mkdir(_getEntriesPath());
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir ${_getEntriesPath()}: $e');
      }
      try {
        await client.mkdir('${_getBasePath()}/media');
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir ${_getBasePath()}/media: $e');
      }
      try {
        await client.mkdir('${_getBasePath()}/thumbnails');
      } catch (e) {
        // Ignore if directory already exists (409 Conflict)
        debugPrint('mkdir ${_getBasePath()}/thumbnails: $e');
      }
    }
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    _config = config;
    final client = await _ensureClient();
    if (client == null || _id == null) return;

    try {
      final jsonString = jsonEncode(config.toJson());
      await client.write(
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
    final client = await _ensureClient();
    if (client == null || _id == null) return null;

    try {
      final content = await client.read(_getConfigPath());
      final jsonData = jsonDecode(utf8.decode(content));
      return AppConfig.fromJson(jsonData);
    } catch (e) {
      debugPrint('Error loading config: $e');
      return null;
    }
  }

  @override
  Future<void> saveDiaryEntry(DiaryEntry entry) async {
    final client = await _ensureClient();
    if (client == null || _id == null) return;

    try {
      final jsonString = jsonEncode(entry.toJson());
      await client.write(
        '${_getEntriesPath()}/${entry.id}.json',
        utf8.encode(jsonString),
      );
    } catch (e) {
      debugPrint('Error saving diary entry: $e');
      rethrow;
    }
  }

  @override
  Future<List<RemoteEntryMeta>> listEntryMeta() async {
    final client = await _ensureClient();
    if (client == null || _id == null) return const [];

    final files = await client.readDir(_getEntriesPath());
    final metas = <RemoteEntryMeta>[];
    for (final file in files) {
      final name = file.name;
      if (name == null || !name.endsWith('.json') || file.isDir == true) {
        continue;
      }
      metas.add(RemoteEntryMeta(
        id: name.substring(0, name.length - '.json'.length),
        etag: file.eTag,
        mtimeMs: file.mTime?.millisecondsSinceEpoch ?? 0,
        size: file.size ?? 0,
      ));
    }
    return metas;
  }

  @override
  Future<DiaryEntry?> readEntry(String id) async {
    final client = await _ensureClient();
    if (client == null || _id == null) return null;
    try {
      final content = await client.read('${_getEntriesPath()}/$id.json');
      final jsonData = jsonDecode(utf8.decode(content));
      return DiaryEntry.fromJson(jsonData as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error reading entry $id: $e');
      return null;
    }
  }

  @override
  Future<List<DiaryEntry>> readEntries(List<String> ids,
      {int concurrency = 4}) async {
    if (ids.isEmpty) return const [];
    final entries = <DiaryEntry>[];
    final safeConcurrency = concurrency < 1 ? 1 : concurrency;
    for (var i = 0; i < ids.length; i += safeConcurrency) {
      final end = (i + safeConcurrency).clamp(0, ids.length);
      final chunk = ids.sublist(i, end);
      final loaded = await Future.wait(chunk.map(readEntry));
      entries.addAll(loaded.whereType<DiaryEntry>());
    }
    return entries;
  }

  @override
  Future<List<DiaryEntry>> loadAllEntries() async {
    try {
      final metas = await listEntryMeta();
      final entries = await readEntries(metas.map((m) => m.id).toList());
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    } catch (e) {
      debugPrint('Error loading entries: $e');
      return [];
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    final client = await _ensureClient();
    if (client == null || _id == null) return false;

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';

      // 分离文件名和父目录路径
      final pathParts = fullPath.split('/');
      final fileName = pathParts.last;
      final parentPath = pathParts.sublist(0, pathParts.length - 1).join('/');

      // 获取父目录内容
      final parentContents = await client.readDir(parentPath);

      // 检查文件中是否有同名文件
      return parentContents.any((file) => file.name == fileName);
    } catch (e) {
      debugPrint('Error checking if file exists: $e');
      return false;
    }
  }

  @override
  Future<File?> downloadToFile(String path,
      {String? targetFilePath, Function(double)? onProgress}) async {
    // 1. 优先检查本地磁盘缓存
    final cachedFile = await _fileCache.getExistingFile(path);
    if (cachedFile != null) {
      if (targetFilePath != null && cachedFile.path != targetFilePath) {
        final targetFile = File(targetFilePath);
        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }
        await cachedFile.copy(targetFilePath);
        return targetFile;
      }
      return cachedFile;
    }

    final client = await _ensureClient();
    if (client == null) return null;

    try {
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      final saveFile = targetFilePath != null
          ? File(targetFilePath)
          : _fileCache.getCacheFile(path);

      if (!await saveFile.parent.exists()) {
        await saveFile.parent.create(recursive: true);
      }

      // 使用临时文件流式写入，避免下载中断导致缓存损坏
      final tempSavePath =
          '${saveFile.path}.tmp_${DateTime.now().millisecondsSinceEpoch}';
      await client.read2File(
        fullPath,
        tempSavePath,
        onProgress: onProgress != null
            ? (count, total) {
                if (total > 0) {
                  onProgress(count / total);
                }
              }
            : null,
      );

      final tempFile = File(tempSavePath);
      if (await tempFile.exists()) {
        if (await saveFile.exists()) {
          await saveFile.delete();
        }
        await tempFile.rename(saveFile.path);
        debugPrint('Successfully streamed and cached file: ${saveFile.path}');
        return saveFile;
      }
      return null;
    } catch (e) {
      debugPrint('Error streaming download to file $path: $e');
      return null;
    }
  }

  @override
  Future<Uint8List?> downloadFile(String path) async {
    // 检查缓存
    final cachedData = await _fileCache.get(path);
    if (cachedData != null) {
      return cachedData;
    }

    // 检查磁盘中是否已有流式下载好的完整文件
    final existingFile = await _fileCache.getExistingFile(path);
    if (existingFile != null) {
      try {
        return await existingFile.readAsBytes();
      } catch (e) {
        debugPrint('Error reading existing cached file: $e');
      }
    }

    final client = await _ensureClient();
    if (client == null) return null;

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      final data = await client.read(fullPath);
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
    final client = await _ensureClient();
    if (client == null || _id == null) {
      throw Exception('WebDAV client not initialized');
    }

    try {
      final path = _getMediaPath(fileName);
      await client.writeFromFile(file.path, path);
      return 'media/$fileName'; // 返回相对路径
    } catch (e) {
      debugPrint('Error uploading media: $e');
      rethrow;
    }
  }

  @override
  Future<bool> uploadFile(String path, File file,
      {Function(double)? onProgress}) async {
    final client = await _ensureClient();
    if (client == null || _id == null) {
      return false;
    }

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      await client.writeFromFile(
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
    final client = await _ensureClient();
    if (client == null || _id == null) {
      return false;
    }

    try {
      // 如果路径不以 'growth_diary/' 开头，则认为是相对路径，需要拼接前缀
      final fullPath =
          path.startsWith('growth_diary/') ? path : '${_getBasePath()}/$path';
      await client.write(
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
    final client = await _ensureClient();
    if (client == null || _id == null) {
      throw Exception('WebDAV client not initialized');
    }

    try {
      // 上传原图
      final originalPath = _getMediaPath(fileName);
      await client.writeFromFile(file.path, originalPath);

      // 生成中号缩略图 (用于详情页)
      final image = img.decodeImage(await file.readAsBytes());
      if (image != null) {
        final mediumThumbnail = img.copyResize(image, width: 768);
        final mediumData = img.encodeJpg(mediumThumbnail, quality: 85);
        final mediumFileName = '${fileName}_medium.jpg';
        final mediumPath = _getThumbnailsPath(mediumFileName);
        await client.write(mediumPath, mediumData);

        // 生成小号缩略图 (用于时间轴)
        final smallThumbnail = img.copyResize(image, width: 400);
        final smallData = img.encodeJpg(smallThumbnail, quality: 80);
        final smallFileName = '${fileName}_small.jpg';
        final smallPath = _getThumbnailsPath(smallFileName);
        await client.write(smallPath, smallData);

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
    final client = await _ensureClient();
    if (client == null || _id == null) {
      throw Exception('WebDAV client not initialized');
    }

    try {
      // 上传原视频
      final originalPath = _getMediaPath(fileName);
      await client.writeFromFile(file.path, originalPath);

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
      await client.write(mediumPath, thumbnail);

      // 生成小号缩略图
      final image = img.decodeImage(thumbnail);
      if (image != null) {
        final smallThumbnail = img.copyResize(image, width: 400);
        final smallData = img.encodeJpg(smallThumbnail, quality: 70);
        final smallFileName = '${fileName}_small.jpg';
        final smallPath = _getThumbnailsPath(smallFileName);
        await client.write(smallPath, smallData);

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
    final client = await _ensureClient();
    if (client == null || _id == null) return;

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
          await client.remove(fullPath);
          debugPrint('Deleted media file: $fullPath');
        } catch (e) {
          debugPrint('Error deleting media file $path: $e');
          // 继续删除其他文件，即使某个文件删除失败
        }
      }

      // 删除条目JSON文件
      await client.remove('${_getEntriesPath()}/${entry.id}.json');
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
      if (data != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = path.split('/').last;
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(data);
        return tempFile;
      }

      // 如果未传入内存数据，直接使用零内存流式下载/缓存文件
      return await downloadToFile(path);
    } catch (e) {
      debugPrint('Error saving to temp file: $e');
      return null;
    }
  }
}
