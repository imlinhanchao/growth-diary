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
        return Colors.grey.shade400;
      case file_utils.UploadStatus.compressing:
        return Colors.orangeAccent;
      case file_utils.UploadStatus.uploading:
        return Colors.blueAccent;
      case file_utils.UploadStatus.paused:
        return Colors.amber;
      case file_utils.UploadStatus.completed:
        return Colors.green;
      case file_utils.UploadStatus.failed:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 浅灰背景，突出卡片
      appBar: AppBar(
        elevation: 0,
        title:
            const Text('上传任务', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        actions: [
          if (_hasActiveTasks())
            IconButton(
              icon: const Icon(Icons.pause_circle_outline),
              onPressed: () {
                MediaUploadService.pauseAllUploads();
                _loadTasks();
              },
              tooltip: '暂停所有上传',
            ),
          if (_hasPausedTasks())
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () {
                MediaUploadService.resumeAllUploads();
                _loadTasks();
              },
              tooltip: '恢复所有上传',
            ),
          if (_hasActiveTasks())
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () {
                MediaUploadService.stopAllUploads();
                _loadTasks();
              },
              tooltip: '停止所有上传',
            ),
          if (_tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAllTasks,
              tooltip: '清空所有任务',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无上传任务',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                final fileSizeMB =
                    File(task.srcPath).lengthSync() / (1024 * 1024);
                final statusColor = _getStatusColor(task.uploadStatus);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        offset: const Offset(0, 4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // 缩略图区域
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[100],
                            image: task.thumbPathSmall != null
                                ? DecorationImage(
                                    image: MemoryImage(task.thumbPathSmall!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: task.thumbPathSmall == null
                              ? Icon(
                                  task.type == file_utils.MediaType.video
                                      ? Icons.videocam_outlined
                                      : Icons.image_outlined,
                                  color: Colors.grey[400],
                                  size: 28,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        // 信息区域
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(task.srcPath),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF333333),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _getStatusText(task.uploadStatus),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${fileSizeMB.toStringAsFixed(2)} MB',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
