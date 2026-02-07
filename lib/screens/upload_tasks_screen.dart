import 'dart:collection';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../services/media_upload_service.dart';
import '../utils/file_utils.dart' as file_utils;

class UploadTasksScreen extends StatefulWidget {
  const UploadTasksScreen({super.key});

  @override
  State<UploadTasksScreen> createState() => _UploadTasksScreenState();
}

class _UploadTasksScreenState extends State<UploadTasksScreen> {
  List<MediaTask> get _tasks => [
        ...(_currentTask != null ? [_currentTask!] : []),
        ..._uploadQueue
      ];
  Queue<MediaTask> _uploadQueue = Queue<MediaTask>();
  MediaTask? _currentTask;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    // 设置上传进度更新回调
    MediaUploadService.setUploadProgressCallback(() {
      _loadTasks();
    });
    // 设置上传完成回调
    MediaUploadService.setUploadCompletedCallback(() {
      _loadTasks();
    });
  }

  @override
  void dispose() {
    // 清理回调
    MediaUploadService.removeUploadProgressCallback();
    MediaUploadService.removeUploadCompletedCallback();
    super.dispose();
  }

  void _loadTasks() {
    setState(() {
      // 只显示未完成和暂停的任务
      _uploadQueue = MediaUploadService.uploadQueue;
      _currentTask = MediaUploadService.currentTask;
    });
  }

  bool _hasActiveTasks() {
    return _tasks.any((task) =>
        task.uploadStatus == file_utils.UploadStatus.uploading ||
        task.uploadStatus == file_utils.UploadStatus.compressing);
  }

  bool _hasPausedTasks() {
    return _tasks
        .any((task) => task.uploadStatus == file_utils.UploadStatus.paused);
  }

  void _clearAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有任务'),
        content: const Text('确定要清空所有上传任务吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      MediaUploadService.clearAllTasks();
      _loadTasks();
    }
  }

  String _getStatusText(file_utils.UploadStatus status) {
    switch (status) {
      case file_utils.UploadStatus.pending:
        return '等待中';
      case file_utils.UploadStatus.compressing:
        return '压缩中';
      case file_utils.UploadStatus.uploading:
        return '上传中';
      case file_utils.UploadStatus.paused:
        return '已暂停';
      case file_utils.UploadStatus.completed:
        return '已完成';
      case file_utils.UploadStatus.failed:
        return '失败';
    }
  }

  Color _getStatusColor(file_utils.UploadStatus status) {
    switch (status) {
      case file_utils.UploadStatus.pending:
        return Colors.grey;
      case file_utils.UploadStatus.compressing:
        return Colors.orange;
      case file_utils.UploadStatus.uploading:
        return Colors.blue;
      case file_utils.UploadStatus.paused:
        return Colors.orange;
      case file_utils.UploadStatus.completed:
        return Colors.green;
      case file_utils.UploadStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传任务'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          if (_hasActiveTasks())
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () {
                MediaUploadService.pauseAllUploads();
                _loadTasks();
              },
              tooltip: '暂停所有上传',
            ),
          if (_hasPausedTasks())
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                MediaUploadService.resumeAllUploads();
                _loadTasks();
              },
              tooltip: '恢复所有上传',
            ),
          if (_hasActiveTasks())
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () {
                MediaUploadService.stopAllUploads();
                _loadTasks();
              },
              tooltip: '停止所有上传',
            ),
          if (_tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearAllTasks,
              tooltip: '清空所有任务',
            ),
        ],
      ),
      body: _tasks.isEmpty
          ? const Center(
              child: Text('暂无上传任务'),
            )
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        image: task.thumbPathSmall != null
                            ? DecorationImage(
                                image: MemoryImage(task.thumbPathSmall!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: task.thumbPathSmall == null
                            ? Colors.grey[300]
                            : null,
                      ),
                      child: task.thumbPathSmall == null
                          ? Icon(
                              task.type == file_utils.MediaType.video
                                  ? Icons.videocam
                                  : Icons.image,
                              color: Colors.grey[600],
                            )
                          : null,
                    ),
                    title: Text(p.basename(task.srcPath)),
                    subtitle: Text(
                        '${(File(task.srcPath).lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(task.uploadStatus),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusText(task.uploadStatus),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
