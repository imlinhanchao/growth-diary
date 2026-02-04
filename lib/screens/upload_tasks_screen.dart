import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'dart:io';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import '../services/background_upload_service.dart';

class UploadTasksScreen extends StatefulWidget {
  const UploadTasksScreen({super.key});

  @override
  State<UploadTasksScreen> createState() => _UploadTasksScreenState();
}

class _UploadTasksScreenState extends State<UploadTasksScreen> {
  List<UploadTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
    // 设置上传进度更新回调
    BackgroundUploadService.setUploadProgressCallback(() {
      _loadTasks();
    });
    // 设置上传完成回调
    BackgroundUploadService.setUploadCompletedCallback(() {
      _loadTasks();
    });
  }

  @override
  void dispose() {
    // 清理回调
    BackgroundUploadService.removeUploadProgressCallback(_loadTasks);
    BackgroundUploadService.removeUploadCompletedCallback(_loadTasks);
    super.dispose();
  }

  void _loadTasks() {
    setState(() {
      // 只显示未完成的任务
      _tasks = BackgroundUploadService.getAllUploadTasks()
          .where((task) => task.status != UploadStatus.completed)
          .toList();
    });
  }

  Future<Map<String, dynamic>> _getFileInfo(String path) async {
    try {
      final file = File(path);
      final stat = await file.stat();
      final sizeMB = (stat.size / (1024 * 1024)).toStringAsFixed(2);
      final date = DateFormat('yyyy-MM-dd HH:mm').format(stat.modified);
      final name = basename(path);
      final isVideo = _isVideoFile(path);
      File? thumbnail;

      if (!isVideo) {
        thumbnail = file;
      } else {
        final tempDir = await getTemporaryDirectory();
        final thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: path,
          thumbnailPath: tempDir.path,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 100,
          quality: 75,
        );
        if (thumbnailPath.path.isNotEmpty) {
          thumbnail = File(thumbnailPath.path);
        }
      }

      return {
        'name': name,
        'size': sizeMB,
        'date': date,
        'isVideo': isVideo,
        'thumbnail': thumbnail,
      };
    } catch (e) {
      return {
        'name': basename(path),
        'size': '未知',
        'date': '未知',
        'isVideo': false,
        'thumbnail': null,
      };
    }
  }

  bool _isVideoFile(String path) {
    final extension = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'wmv', 'flv', 'webm']
        .contains(extension);
  }

  String _getStatusText(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return '等待中';
      case UploadStatus.compressing:
        return '压缩中';
      case UploadStatus.uploading:
        return '上传中';
      case UploadStatus.paused:
        return '已暂停';
      case UploadStatus.completed:
        return '已完成';
      case UploadStatus.failed:
        return '失败';
    }
  }

  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return Colors.grey;
      case UploadStatus.compressing:
        return Colors.orange;
      case UploadStatus.uploading:
        return Colors.blue;
      case UploadStatus.paused:
        return Colors.orange;
      case UploadStatus.completed:
        return Colors.green;
      case UploadStatus.failed:
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
          if (_tasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () async {
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
                  await BackgroundUploadService.clearAllUploadTasks();
                  _loadTasks();
                }
              },
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
                  child: ExpansionTile(
                    key: ValueKey(task.id), // 使用稳定的key避免重建时丢失展开状态
                    title: Text(task.description),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('文件数量: ${task.mediaPaths.length}'),
                        Text(
                            '已上传: ${task.uploadedCount}/${task.mediaPaths.length}'),
                        if (task.errorMessage != null)
                          Text(
                            '错误: ${task.errorMessage}',
                            style: const TextStyle(color: Colors.red),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(task.status),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getStatusText(task.status),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            switch (value) {
                              case 'pause':
                                await BackgroundUploadService.pauseUpload(
                                    task.id);
                                _loadTasks();
                                break;
                              case 'resume':
                                await BackgroundUploadService.resumeUpload(
                                    task.id);
                                _loadTasks();
                                break;
                              case 'cancel':
                                await BackgroundUploadService.cancelUpload(
                                    task.id);
                                _loadTasks();
                                break;
                              case 'retry':
                                await BackgroundUploadService.retryUpload(
                                    task.id);
                                _loadTasks();
                                break;
                              case 'delete':
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除任务'),
                                    content: const Text('确定要删除这个上传任务吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: const Text('确定'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await BackgroundUploadService
                                      .deleteUploadTask(task.id);
                                  _loadTasks();
                                }
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (task.status == UploadStatus.compressing ||
                                task.status == UploadStatus.uploading)
                              const PopupMenuItem(
                                value: 'pause',
                                child: Text('暂停'),
                              ),
                            if (task.status == UploadStatus.paused)
                              const PopupMenuItem(
                                value: 'resume',
                                child: Text('恢复'),
                              ),
                            if (task.status == UploadStatus.compressing ||
                                task.status == UploadStatus.uploading ||
                                task.status == UploadStatus.paused)
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text('取消'),
                              ),
                            if (task.status == UploadStatus.failed &&
                                task.errorMessage != '所有文件已被删除')
                              const PopupMenuItem(
                                value: 'retry',
                                child: Text('重试'),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: task.mediaPaths.map((filePath) {
                      return FutureBuilder<Map<String, dynamic>>(
                        future: _getFileInfo(filePath),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            final info = snapshot.data!;
                            final fileStatus = task.fileStatuses[filePath] ??
                                UploadStatus.pending;
                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  image: info['thumbnail'] != null
                                      ? DecorationImage(
                                          image: FileImage(info['thumbnail']),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  color: info['thumbnail'] == null
                                      ? Colors.grey[300]
                                      : null,
                                ),
                                child: info['thumbnail'] == null
                                    ? Icon(
                                        info['isVideo']
                                            ? Icons.videocam
                                            : Icons.image,
                                        color: Colors.grey[600],
                                      )
                                    : null,
                              ),
                              title: Text(info['name']),
                              subtitle:
                                  Text('${info['size']} MB\n${info['date']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(fileStatus),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _getStatusText(fileStatus),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  // 只为未完成的文件显示删除按钮
                                  if (fileStatus != UploadStatus.completed &&
                                      fileStatus != UploadStatus.failed)
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('删除文件'),
                                            content: Text(
                                                '确定要从上传任务中删除文件 "${info['name']}" 吗？'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(false),
                                                child: const Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
                                                child: const Text('确定'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          await BackgroundUploadService
                                              .removeFileFromTask(
                                                  task.id, filePath);
                                          _loadTasks();
                                        }
                                      },
                                    ),
                                ],
                              ),
                            );
                          } else {
                            return const ListTile(
                              title: Text('加载中...'),
                            );
                          }
                        },
                      );
                    }).toList(),
                  ),
                );
              },
            ),
    );
  }
}
