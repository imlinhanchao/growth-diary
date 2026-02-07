import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:growth_diary/models/app_config.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/file_utils.dart';
import '../services/cloud_storage_service.dart';
import '../services/entry_creation_service.dart';
import '../models/diary_entry.dart';

class MediaTask extends MediaFile {
  UploadStatus uploadStatus;
  MediaTask({
    required super.srcPath,
    super.type,
    super.thumbPathSmall,
    super.thumbPathMedium,
    super.uploadPath,
    super.createdAt,
    this.uploadStatus = UploadStatus.pending,
  });

  // 序列化方法
  Map<String, dynamic> toJson() {
    return {
      'srcPath': srcPath,
      'type': type.toString().split('.').last, // 转换为字符串
      'thumbPathSmall':
          thumbPathSmall != null ? base64Encode(thumbPathSmall!) : null,
      'thumbPathMedium':
          thumbPathMedium != null ? base64Encode(thumbPathMedium!) : null,
      'uploadPath': uploadPath,
      'createdAt': createdAt?.toIso8601String(),
      'uploadStatus': uploadStatus.toString().split('.').last,
    };
  }

  // 反序列化方法
  factory MediaTask.fromJson(Map<String, dynamic> json) {
    return MediaTask(
      srcPath: json['srcPath'],
      type: MediaType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => MediaType.image,
      ),
      thumbPathSmall: json['thumbPathSmall'] != null
          ? base64Decode(json['thumbPathSmall'])
          : null,
      thumbPathMedium: json['thumbPathMedium'] != null
          ? base64Decode(json['thumbPathMedium'])
          : null,
      uploadPath: json['uploadPath'],
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      uploadStatus: UploadStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['uploadStatus'],
        orElse: () => UploadStatus.pending,
      ),
    );
  }
}

/// 媒体上传服务
/// 管理 MediaTask 的后台上传任务
class MediaUploadService {
  static final MediaUploadService _instance = MediaUploadService._internal();
  factory MediaUploadService() => _instance;
  MediaUploadService._internal();

  CloudStorageService? _cloudStorage;

  // 上传任务队列
  final Queue<MediaTask> _uploadQueue = Queue<MediaTask>();

  // 当前正在上传的任务
  MediaTask? _currentTask;

  // 是否正在运行
  bool _isRunning = false;

  AppConfig? config;

  // 任务统计
  int _totalTasks = 0; // 总任务数
  int _completedTasks = 0; // 完成任务数

  static getTotalTasks() {
    return _instance._totalTasks;
  }

  static getCompletedTasks() {
    return _instance._completedTasks;
  }

  static get uploadQueue {
    return _instance._uploadQueue;
  }

  static get currentTask {
    return _instance._currentTask;
  }

  // 上传进度回调
  Function(MediaTask task, double progress)? _onProgress;
  Function(MediaTask task)? _onTaskCompleted;
  Function(MediaTask task, String error)? _onTaskFailed;
  Function(DiaryEntry entry)? _onEntryCreated;
  Function()? _onAllUploadsCompleted;

  // Entry 创建相关
  EntryCreationService? _entryCreationService;
  String? _currentUploadDescription;
  List<DiaryEntry>? _pendingEntries;
  Map<String, List<String>> _entryMediaMapping = {}; // entryId -> [mediaPaths]

  // 全局回调
  static Function()? _globalUploadCompletedCallback;
  static Function()? _globalUploadProgressCallback;

  /// 设置上传完成回调
  static void setUploadCompletedCallback(Function() callback) {
    _globalUploadCompletedCallback = callback;
  }

  /// 设置上传进度更新回调
  static void setUploadProgressCallback(Function() callback) {
    _globalUploadProgressCallback = callback;
  }

  /// 移除上传完成回调
  static void removeUploadCompletedCallback() {
    _globalUploadCompletedCallback = null;
  }

  /// 移除上传进度更新回调
  static void removeUploadProgressCallback() {
    _globalUploadProgressCallback = null;
  }

  /// 暂停所有上传任务
  static void pauseAllUploads() {
    _instance.pauseUpload();
  }

  /// 恢复所有上传任务
  static void resumeAllUploads() {
    _instance.resumeUpload();
  }

  /// 停止所有上传任务
  static void stopAllUploads() {
    _instance.stopUpload();
  }

  /// 清空所有任务
  static void clearAllTasks() {
    _instance._uploadQueue.clear();
    _instance._currentTask = null;
    _instance._isRunning = false;
    _instance._totalTasks = 0;
    _instance._completedTasks = 0;
    _instance._saveTaskQueue();
    // 触发进度回调
    _globalUploadProgressCallback?.call();
  }

  /// 获取所有上传任务
  static List<MediaTask> getAllUploadTasks() {
    final tasks = <MediaTask>[];
    if (_instance._currentTask != null) {
      tasks.add(_instance._currentTask!);
    }
    tasks.addAll(_instance._uploadQueue);
    return tasks;
  }

  /// 检查是否有活跃的上传任务
  static bool hasActiveUploads() {
    return _instance._isRunning || _instance._uploadQueue.isNotEmpty;
  }

  /// 显示后台上传通知
  static void showBackgroundNotification(String title, String body) {
    // 这里可以实现通知，但暂时留空或使用flutter_local_notifications
  }

  /// 初始化云存储服务
  void initialize(CloudStorageService cloudStorage, AppConfig config,
      EntryCreationService entryCreationService) {
    _cloudStorage = cloudStorage;
    this.config = config;
    _entryCreationService = entryCreationService;
  }

  /// 保存任务队列到本地存储
  Future<void> _saveTaskQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/upload_tasks.json');

      final tasksData = {
        'queue': _uploadQueue.map((task) => task.toJson()).toList(),
        'currentTask': _currentTask?.toJson(),
        'isRunning': _isRunning,
        'totalTasks': _totalTasks,
        'completedTasks': _completedTasks,
        'description': _currentUploadDescription,
        'pendingEntries':
            _pendingEntries?.map((entry) => entry.toJson()).toList(),
        'entryMediaMapping': _entryMediaMapping,
      };

      await file.writeAsString(jsonEncode(tasksData));
    } catch (e) {
      print('保存任务队列失败: $e');
    }
  }

  /// 从本地存储加载任务队列
  Future<void> loadTaskQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/upload_tasks.json');

      if (!await file.exists()) {
        return; // 文件不存在，直接返回
      }

      final content = await file.readAsString();
      final tasksData = jsonDecode(content) as Map<String, dynamic>;

      // 恢复队列
      final queueData = tasksData['queue'] as List<dynamic>;
      _uploadQueue.clear();
      for (final taskJson in queueData) {
        final task = MediaTask.fromJson(taskJson as Map<String, dynamic>);
        _uploadQueue.add(task);
      }

      // 恢复当前任务
      if (tasksData['currentTask'] != null) {
        _currentTask = MediaTask.fromJson(
            tasksData['currentTask'] as Map<String, dynamic>);
      }

      // 恢复运行状态
      _isRunning = tasksData['isRunning'] ?? false;

      // 恢复统计数据
      _totalTasks = tasksData['totalTasks'] ?? 0;
      _completedTasks = tasksData['completedTasks'] ?? 0;

      // 恢复描述和待处理 entries
      _currentUploadDescription = tasksData['description'];
      if (tasksData['pendingEntries'] != null) {
        final entriesData = tasksData['pendingEntries'] as List<dynamic>;
        _pendingEntries = entriesData
            .map((entryJson) =>
                DiaryEntry.fromJson(entryJson as Map<String, dynamic>))
            .toList();
      }
      if (tasksData['entryMediaMapping'] != null) {
        final mappingData =
            tasksData['entryMediaMapping'] as Map<String, dynamic>;
        _entryMediaMapping = Map<String, List<String>>.from(mappingData.map(
          (key, value) =>
              MapEntry(key, List<String>.from(value as List<dynamic>)),
        ));
      }

      // 如果之前正在运行，继续处理
      if (_isRunning && _uploadQueue.isNotEmpty) {
        _processNextTask();
      }
    } catch (e) {
      print('加载任务队列失败: $e');
    }
  }

  /// 清除保存的任务队列
  Future<void> clearSavedTasks() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/upload_tasks.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('清除保存的任务失败: $e');
    }
  }

  /// 开始上传任务
  void startUpload(
    List<MediaTask> tasks, {
    required String description,
    Function(MediaTask task, double progress)? onProgress,
    Function(MediaTask task)? onTaskCompleted,
    Function(MediaTask task, String error)? onTaskFailed,
    Function(DiaryEntry entry)? onEntryCreated,
    Function()? onAllUploadsCompleted,
  }) {
    if (_cloudStorage == null ||
        _entryCreationService == null ||
        config == null) {
      throw Exception('MediaUploadService not fully initialized');
    }

    _onProgress = onProgress;
    _onTaskCompleted = onTaskCompleted;
    _onTaskFailed = onTaskFailed;
    _onEntryCreated = onEntryCreated;
    _onAllUploadsCompleted = onAllUploadsCompleted;
    _currentUploadDescription = description;

    // 将 MediaTask 转换为 MediaFile 列表
    final mediaFiles = tasks
        .map((task) => MediaFile(
              srcPath: task.srcPath,
              type: task.type,
              thumbPathSmall: task.thumbPathSmall,
              thumbPathMedium: task.thumbPathMedium,
              uploadPath: task.uploadPath,
              createdAt: task.createdAt,
            ))
        .toList();

    // 创建 DiaryEntry 列表
    _createPendingEntries(mediaFiles, description);

    // 添加任务到队列
    _uploadQueue.addAll(tasks);

    // 更新总任务数
    _totalTasks += tasks.length;

    // 保存任务队列
    _saveTaskQueue();

    // 如果没有在运行，开始处理
    if (!_isRunning) {
      _startProcessing();
    }
  }

  /// 创建待处理的 DiaryEntry 列表
  Future<void> _createPendingEntries(
      List<MediaFile> mediaFiles, String description) async {
    _pendingEntries = await _entryCreationService!.createMediaEntry(
      mediaFiles,
      description,
      config!,
    );

    // 初始化 entry-media 映射
    _entryMediaMapping.clear();
    for (final entry in _pendingEntries!) {
      final mediaPaths = <String>[];
      for (var i = 0; i < entry.imagePaths.length; i++) {
        entry.imagePaths[i] = '@${entry.imagePaths[i]}';
      }
      for (var i = 0; i < entry.videoPaths.length; i++) {
        entry.videoPaths[i] = '@${entry.videoPaths[i]}';
      }
      mediaPaths.addAll(entry.imagePaths);
      mediaPaths.addAll(entry.videoPaths);
      _entryMediaMapping[entry.id] = mediaPaths;
    }
  }

  /// 暂停上传
  void pauseUpload() {
    _isRunning = false;
    if (_currentTask != null) {
      _currentTask!.uploadStatus = UploadStatus.paused;
    }
    // 保存当前状态
    _saveTaskQueue();
    // 触发进度回调
    _globalUploadProgressCallback?.call();
  }

  /// 恢复上传
  void resumeUpload() {
    if (!_isRunning && _uploadQueue.isNotEmpty) {
      _startProcessing();
    }
    // 保存当前状态
    _saveTaskQueue();
    // 触发进度回调
    _globalUploadProgressCallback?.call();
  }

  /// 停止上传
  void stopUpload() {
    _isRunning = false;
    _uploadQueue.clear();
    _currentTask = null;
    // 重置统计数据
    _totalTasks = 0;
    _completedTasks = 0;
    // 重置 entry 相关数据
    _currentUploadDescription = null;
    _pendingEntries = null;
    _entryMediaMapping.clear();
    // 保存当前状态（清空状态）
    _saveTaskQueue();
  }

  /// 获取当前任务
  MediaTask? getCurrentTask() => _currentTask;

  /// 获取队列中的任务数量
  int getQueueLength() => _uploadQueue.length;

  /// 移除尚未进行的任务
  bool removePendingTask(String srcPath) {
    // 不能移除当前正在上传的任务
    if (_currentTask != null && _currentTask!.srcPath == srcPath) {
      return false;
    }

    // 从队列中查找并移除任务
    MediaTask? taskToRemove;
    for (final task in _uploadQueue) {
      if (task.srcPath == srcPath) {
        taskToRemove = task;
        break;
      }
    }

    if (taskToRemove == null) {
      return false; // 任务不在队列中
    }

    // 从队列中移除任务
    _uploadQueue.remove(taskToRemove);

    // 更新总任务数
    _totalTasks = _totalTasks > 0 ? _totalTasks - 1 : 0;

    // 从对应的 entry 中移除该媒体文件
    _removeMediaFromPendingEntries(taskToRemove);

    // 保存状态
    _saveTaskQueue();

    return true;
  }

  /// 从待处理的 entries 中移除指定的媒体文件
  void _removeMediaFromPendingEntries(MediaTask task) {
    if (_pendingEntries == null) return;

    final fileName = task.srcPath.split('/').last;

    for (final entry in _pendingEntries!) {
      final mediaPaths = _entryMediaMapping[entry.id];
      if (mediaPaths == null) continue;

      bool removed = false;

      // 检查图片路径
      final imageIndex =
          entry.imagePaths.indexWhere((path) => path.contains(fileName));
      if (imageIndex != -1) {
        entry.imagePaths.removeAt(imageIndex);
        mediaPaths.removeAt(imageIndex);
        removed = true;
      }

      // 检查视频路径
      final videoIndex =
          entry.videoPaths.indexWhere((path) => path.contains(fileName));
      if (videoIndex != -1) {
        entry.videoPaths.removeAt(videoIndex);
        // 调整映射中的索引（因为视频在图片之后）
        final mappingIndex = entry.imagePaths.length + videoIndex;
        if (mappingIndex < mediaPaths.length) {
          mediaPaths.removeAt(mappingIndex);
        }
        removed = true;
      }

      if (removed) {
        // 如果 entry 中没有媒体文件了，删除这个 entry
        if (entry.imagePaths.isEmpty && entry.videoPaths.isEmpty) {
          _pendingEntries!.remove(entry);
          _entryMediaMapping.remove(entry.id);
        }
        break; // 假设一个文件只属于一个 entry
      }
    }
  }

  /// 获取总任务数
  int get totalTasks => _totalTasks;

  /// 获取完成任务数
  int get completedTasks => _completedTasks;

  /// 获取保存的任务信息（用于调试或UI显示）
  Future<Map<String, dynamic>?> getSavedTasksInfo() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/upload_tasks.json');

      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      print('获取保存的任务信息失败: $e');
      return null;
    }
  }

  /// 重置统计数据
  void resetStatistics() {
    _totalTasks = 0;
    _completedTasks = 0;
    _saveTaskQueue();
  }

  /// 开始处理队列
  void _startProcessing() {
    _isRunning = true;
    _processNextTask();
  }

  /// 处理下一个任务
  Future<void> _processNextTask() async {
    if (!_isRunning || _uploadQueue.isEmpty) {
      _isRunning = false;
      if (_uploadQueue.isEmpty) {
        resetStatistics();
        _onAllUploadsCompleted?.call();
        // 触发完成回调
        _globalUploadCompletedCallback?.call();
      }
      return;
    }

    _currentTask = _uploadQueue.removeFirst();
    _currentTask!.uploadStatus = UploadStatus.uploading;
    // 触发进度回调
    _globalUploadProgressCallback?.call();

    try {
      // 执行上传（暂时留空）
      await _uploadTask(_currentTask!);

      // 上传成功
      _currentTask!.uploadStatus = UploadStatus.completed;
      _completedTasks++; // 增加完成任务数
      _onTaskCompleted?.call(_currentTask!);
      // 保存状态
      _saveTaskQueue();
      // 触发进度回调
      _globalUploadProgressCallback?.call();
    } catch (e) {
      // 上传失败
      _currentTask!.uploadStatus = UploadStatus.failed;
      _onTaskFailed?.call(_currentTask!, e.toString());
      // 保存状态
      _saveTaskQueue();
      // 触发进度回调
      _globalUploadProgressCallback?.call();
    }

    _currentTask = null;

    // 处理下一个任务
    _processNextTask();
  }

  /// 上传任务的具体实现
  Future<void> _uploadTask(MediaTask task) async {
    if (_cloudStorage == null) {
      throw Exception('CloudStorageService not initialized');
    }

    try {
      // 1. 先上传原始文件
      // 检查是否被暂停
      if (!_isRunning) {
        task.uploadStatus = UploadStatus.paused;
        throw Exception('Upload paused by user');
      }

      var file = File(task.srcPath);
      if (!await file.exists()) {
        throw Exception('Source file does not exist: ${task.srcPath}');
      }

      final fileName = FileUtils.generateFileName(file, await file.stat());
      final mediaPath = 'media/$fileName';

      // 如果文件已经上传过了（在服务器上存在相同路径文件），则跳过上传步骤，并从Task和entry中移除这个文件，进行下一个任务的上传
      final existingFile = await _cloudStorage!.fileExists(mediaPath);
      if (existingFile) {
        // 从对应的 entry 中移除该媒体文件
        _removeMediaFromPendingEntries(task);

        // 更新统计数据
        _completedTasks++; // 增加完成任务数

        // 保存状态
        _saveTaskQueue();

        // 触发完成回调
        _onTaskCompleted?.call(task);

        return; // 跳过上传，直接返回
      }

      // 如果是视频，先检查是否需要压缩
      if (task.type == MediaType.video && !task.isCompressed) {
        if (config != null && config!.videoCompressionThreshold > 0) {
          final fileSizeMB = await file.length() / (1024 * 1024);
          if (fileSizeMB >= config!.videoCompressionThreshold) {
            // 设置状态为压缩中
            task.uploadStatus = UploadStatus.compressing;
            // 保存状态
            _saveTaskQueue();
            // 触发进度回调
            _globalUploadProgressCallback?.call();

            // 压缩视频
            final compressedFile = await FileUtils.compressVideo(task.srcPath);
            if (compressedFile != null) {
              file = compressedFile;
              task.srcPath = compressedFile.path;
              task.isCompressed = true;
            }
          }
        }
      }

      // 检查是否被暂停
      if (!_isRunning) {
        task.uploadStatus = UploadStatus.paused;
        throw Exception('Upload paused by user');
      }

      // 设置状态为上传中
      task.uploadStatus = UploadStatus.uploading;
      // 保存状态
      _saveTaskQueue();
      // 触发进度回调
      _globalUploadProgressCallback?.call();

      if (task.uploadPath?.isEmpty ?? true) {
        final success = await _cloudStorage!.uploadFile(
          mediaPath,
          file,
          onProgress: (progress) {
            // 主文件上传进度：0-70%
            _onProgress?.call(task, progress * 0.7);
          },
        );
        if (!success) {
          throw Exception('Failed to upload media file');
        }

        // 设置上传路径
        task.uploadPath = mediaPath;

        // 保存状态
        _saveTaskQueue();
      }

      _onProgress?.call(task, 0.7); // 70% 进度

      // 2. 上传缩略图（如果存在）
      if (task.thumbPathMedium != null && task.thumbPathMedium!.isNotEmpty) {
        // 检查是否被暂停
        if (!_isRunning) {
          task.uploadStatus = UploadStatus.paused;
          throw Exception('Upload paused by user');
        }

        final thumbMediumPath = 'thumbnails/${fileName}_medium.jpg';
        final success = await _cloudStorage!.uploadData(
          thumbMediumPath,
          task.thumbPathMedium!,
          onProgress: (progress) {
            // 中等缩略图上传进度：70-85%
            _onProgress?.call(task, 0.7 + progress * 0.15);
          },
        );
        if (!success) {
          throw Exception('Failed to upload medium thumbnail');
        } else {
          task.thumbPathMedium = null; // 释放内存
          _saveTaskQueue();
        }

        _onProgress?.call(task, 0.85); // 85% 进度
      }

      if (task.thumbPathSmall != null && task.thumbPathSmall!.isNotEmpty) {
        // 检查是否被暂停
        if (!_isRunning) {
          task.uploadStatus = UploadStatus.paused;
          throw Exception('Upload paused by user');
        }

        final thumbSmallPath = 'thumbnails/${fileName}_small.jpg';
        final success = await _cloudStorage!.uploadData(
          thumbSmallPath,
          task.thumbPathSmall!,
          onProgress: (progress) {
            // 小缩略图上传进度：85-100%
            _onProgress?.call(task, 0.85 + progress * 0.15);
          },
        );
        if (!success) {
          throw Exception('Failed to upload small thumbnail');
        } else {
          task.thumbPathSmall = null; // 释放内存
          _saveTaskQueue();
        }

        _onProgress?.call(task, 1.0); // 100% 进度
      } else {
        _onProgress?.call(task, 1.0); // 如果没有小缩略图，直接完成
      }

      // 上传成功
      task.uploadStatus = UploadStatus.completed;

      // 更新对应的 DiaryEntry
      await _updateEntryWithUploadedMedia(task);
    } catch (e) {
      // 如果是暂停异常，保持暂停状态
      if (e.toString().contains('Upload paused by user')) {
        task.uploadStatus = UploadStatus.paused;
        // 触发进度回调
        _globalUploadProgressCallback?.call();
      } else {
        // 其他错误，设置为失败状态
        task.uploadStatus = UploadStatus.failed;
        // 触发进度回调
        _globalUploadProgressCallback?.call();
      }
      rethrow;
    }
  }

  /// 更新 DiaryEntry 中的媒体文件地址
  Future<void> _updateEntryWithUploadedMedia(MediaTask task) async {
    if (_pendingEntries == null || task.uploadPath == null) return;

    // 找到对应的 entry
    for (final entry in _pendingEntries!) {
      final mediaPaths = _entryMediaMapping[entry.id];
      if (mediaPaths == null) continue;

      // 检查这个 entry 是否包含这个媒体文件
      final originalFileName = task.srcPath.split('/').last;
      var fileName = task.uploadPath?.split('/').last ?? originalFileName;
      final uploadedPath = 'media/$fileName';

      // 更新图片路径
      final imageIndex = entry.imagePaths
          .indexWhere((path) => path.contains(originalFileName));
      if (imageIndex != -1) {
        entry.imagePaths[imageIndex] = uploadedPath;
        mediaPaths[imageIndex] = uploadedPath;
        entry.imageThumbnails.add('thumbnails/${fileName}_small.jpg');
      }

      // 更新视频路径
      final videoIndex = entry.videoPaths
          .indexWhere((path) => path.contains(originalFileName));
      if (videoIndex != -1) {
        entry.videoPaths[videoIndex] = uploadedPath;
        mediaPaths[videoIndex] = uploadedPath;
        entry.videoThumbnails.add('thumbnails/${fileName}_small.jpg');
      }

      // 检查是否所有媒体都已上传完成
      final allUploaded = mediaPaths.every((path) => !path.startsWith('@'));
      if (allUploaded) {
        // 上传完成的 entry 到服务器
        await _entryCreationService!.webdavService.saveDiaryEntry(entry);
        // 从待处理列表中移除
        _pendingEntries!.remove(entry);
        _onEntryCreated?.call(entry);
        break;
      }
    }
  }
}
