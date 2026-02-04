import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:video_trimmer/video_trimmer.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class BatchVideoEditorScreen extends StatefulWidget {
  final List<String> videoPaths;
  final List<DateTime> originalDates;

  const BatchVideoEditorScreen({
    super.key,
    required this.videoPaths,
    required this.originalDates,
  });

  @override
  State<BatchVideoEditorScreen> createState() => _BatchVideoEditorScreenState();
}

class _BatchVideoEditorScreenState extends State<BatchVideoEditorScreen> {
  final Trimmer _trimmer = Trimmer();
  int _currentIndex = 0;
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;

  // 存储每个视频的编辑状态
  final List<Map<String, dynamic>> _videoStates = [];

  // 存储视频缩略图
  final List<String?> _thumbnails = [];

  @override
  void initState() {
    super.initState();
    // 初始化每个视频的状态和缩略图
    for (int i = 0; i < widget.videoPaths.length; i++) {
      _videoStates.add({
        'isEdited': false,
        'startValue': 0.0,
        'endValue': 0.0,
        'trimmedPath': null,
      });
      _thumbnails.add(null);
    }

    // 异步生成缩略图
    _generateThumbnails();

    _loadCurrentVideo();
  }

  Future<void> _generateThumbnails() async {
    for (int i = 0; i < widget.videoPaths.length; i++) {
      try {
        final thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: widget.videoPaths[i],
          thumbnailPath: (await getTemporaryDirectory()).path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 200,
          quality: 75,
        );

        if (mounted) {
          setState(() {
            _thumbnails[i] = thumbnailPath.path;
          });
        }
      } catch (e) {
        // 生成缩略图失败，使用默认占位符
        debugPrint('生成视频缩略图失败: $e');
      }
    }
  }

  void _loadCurrentVideo() async {
    await _trimmer.loadVideo(videoFile: File(widget.videoPaths[_currentIndex]));
    // 恢复之前保存的状态
    final state = _videoStates[_currentIndex];
    setState(() {
      _startValue = state['startValue'];
      _endValue = state['endValue'];
    });
  }

  @override
  void dispose() {
    _trimmer.dispose();

    // 清理所有缩略图文件
    for (final thumbnailPath in _thumbnails) {
      if (thumbnailPath != null) {
        try {
          File(thumbnailPath).deleteSync();
        } catch (e) {
          // 忽略删除失败的错误
        }
      }
    }

    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _saveCurrentVideo() async {
    setState(() {
      _progressVisibility = true;
    });

    try {
      _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (String? trimmedPath) {
          if (trimmedPath != null) {
            // 保留原始文件的创建时间
            final originalFile = File(widget.videoPaths[_currentIndex]);
            final trimmedFile = File(trimmedPath);

            // 复制文件的修改时间
            final originalStat = originalFile.statSync();
            trimmedFile.setLastModifiedSync(originalStat.modified);

            // 保存编辑状态
            _videoStates[_currentIndex]['isEdited'] = true;
            _videoStates[_currentIndex]['trimmedPath'] = trimmedPath;
          }
          setState(() {
            _progressVisibility = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _progressVisibility = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频剪辑失败: $e')),
        );
      }
    }
  }

  void _switchToVideo(int index) async {
    if (index == _currentIndex) return;

    // 保存当前视频的状态
    _videoStates[_currentIndex]['startValue'] = _startValue;
    _videoStates[_currentIndex]['endValue'] = _endValue;

    setState(() {
      _currentIndex = index;
    });

    _loadCurrentVideo();
  }

  void _removeVideo(int index) {
    if (widget.videoPaths.length <= 1) {
      // 如果只剩一个视频，不允许移除
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要保留一个视频')),
      );
      return;
    }

    setState(() {
      // 删除缩略图文件
      if (_thumbnails[index] != null) {
        try {
          File(_thumbnails[index]!).deleteSync();
        } catch (e) {
          // 忽略删除失败的错误
        }
      }

      widget.videoPaths.removeAt(index);
      widget.originalDates.removeAt(index);
      _videoStates.removeAt(index);
      _thumbnails.removeAt(index);

      // 调整当前索引
      if (_currentIndex >= index && _currentIndex > 0) {
        _currentIndex--;
      }

      // 重新加载当前视频
      _loadCurrentVideo();
    });
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃编辑'),
        content: const Text('确定要放弃所有视频编辑吗？未保存的更改将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _finishEditing() {
    // 收集所有编辑结果
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.videoPaths.length; i++) {
      final state = _videoStates[i];
      if (state['isEdited'] && state['trimmedPath'] != null) {
        results.add({
          'path': state['trimmedPath'],
          'originalDate': widget.originalDates[i],
        });
      } else {
        results.add({
          'path': widget.videoPaths[i],
          'originalDate': widget.originalDates[i],
        });
      }
    }

    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    // 获取颜色方案
    final primaryColor = Theme.of(context).primaryColor;
    const backgroundColor = Colors.black;
    const surfaceColor = Color(0xFF1E1E1E);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop || !mounted) return;

        final shouldPop = await _onWillPop();
        if (shouldPop) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop(null);
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            '编辑视频 (${_currentIndex + 1}/${widget.videoPaths.length})',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (!mounted) return;

              final shouldPop = await _onWillPop();
              if (shouldPop) {
                // ignore: use_build_context_synchronously
                Navigator.of(context).pop(null);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (!mounted) return;

                final shouldPop = await _onWillPop();
                if (shouldPop) {
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).pop(null);
                }
              },
              child: const Text(
                '放弃',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0, top: 4, bottom: 4),
              child: FilledButton(
                onPressed: _finishEditing,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('完成',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // 视频播放器
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: VideoViewer(trimmer: _trimmer),
                  ),
                ),
              ),

              // 控制区域和视频列表的容器
              Container(
                decoration: const BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),

                    // 进度条 TrimViewer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TrimViewer(
                        trimmer: _trimmer,
                        viewerHeight: 50,
                        viewerWidth: MediaQuery.of(context).size.width - 32,
                        onChangeStart: (value) =>
                            setState(() => _startValue = value),
                        onChangeEnd: (value) =>
                            setState(() => _endValue = value),
                        onChangePlaybackState: (value) =>
                            setState(() => _isPlaying = value),
                        // 样式参数
                        durationStyle: DurationStyle.FORMAT_MM_SS,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 时间显示和控制按钮
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              _formatDuration(
                                  Duration(seconds: _startValue.toInt())),
                              style: const TextStyle(color: Colors.white70)),

                          // 播放控制区
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_fill,
                                    size: 48,
                                    color: Colors.white),
                                onPressed: () async {
                                  final playbackState =
                                      await _trimmer.videoPlaybackControl(
                                    startValue: _startValue,
                                    endValue: _endValue,
                                  );
                                  setState(() => _isPlaying = playbackState);
                                },
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _saveCurrentVideo,
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('应用剪辑'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.1),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),

                          Text(
                              _formatDuration(
                                  Duration(seconds: _endValue.toInt())),
                              style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),

                    const Divider(color: Colors.white12, height: 24),

                    // 视频列表
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: widget.videoPaths.length,
                        itemBuilder: (context, index) {
                          final isSelected = index == _currentIndex;
                          final isEdited = _videoStates[index]['isEdited'];

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: GestureDetector(
                              onTap: () => _switchToVideo(index),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // 视频缩略图容器
                                  Container(
                                    width: 76,
                                    height: 90,
                                    margin: const EdgeInsets.only(
                                        top: 8, right: 8), // 留出右上角按钮空间
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: isSelected
                                          ? Border.all(
                                              color: primaryColor, width: 2)
                                          : null,
                                      image: _thumbnails[index] != null
                                          ? DecorationImage(
                                              image: FileImage(
                                                  File(_thumbnails[index]!)),
                                              fit: BoxFit.cover,
                                              colorFilter: isSelected
                                                  ? null
                                                  : const ColorFilter.mode(
                                                      Colors.black45,
                                                      BlendMode.darken),
                                            )
                                          : null,
                                      color: Colors.grey[800],
                                    ),
                                    child: _thumbnails[index] == null
                                        ? const Center(
                                            child: Icon(Icons.videocam,
                                                color: Colors.white24))
                                        : null,
                                  ),

                                  // 编辑状态指示器
                                  if (isEdited)
                                    Positioned(
                                      bottom: 4,
                                      right: 12, // 考虑 margin
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.check,
                                            size: 12, color: Colors.white),
                                      ),
                                    ),

                                  // 移除按钮
                                  if (widget.videoPaths.length > 1)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () => _removeVideo(index),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 2)
                                            ],
                                          ),
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(Icons.close,
                                              size: 12, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 进度指示器
                    if (_progressVisibility)
                      LinearProgressIndicator(
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
