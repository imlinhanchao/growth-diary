import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';
import 'dart:io';

class VideoEditorScreen extends StatefulWidget {
  final String videoPath;
  final DateTime originalDate;

  const VideoEditorScreen({
    super.key,
    required this.videoPath,
    required this.originalDate,
  });

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _progressVisibility = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  void _loadVideo() async {
    await _trimmer.loadVideo(videoFile: File(widget.videoPath));
    setState(() {});
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _saveVideo() async {
    setState(() {
      _progressVisibility = true;
    });

    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (String? trimmedPath) {
          if (trimmedPath != null) {
            // 保留原始文件的创建时间
            final originalFile = File(widget.videoPath);
            final trimmedFile = File(trimmedPath);

            // 复制文件的修改时间
            final originalStat = originalFile.statSync();
            trimmedFile.setLastModifiedSync(originalStat.modified);

            if (mounted) {
              Navigator.of(context).pop({
                'path': trimmedPath,
                'originalDate': widget.originalDate,
              });
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('视频剪辑失败')),
              );
            }
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

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃编辑'),
        content: const Text('确定要放弃视频编辑吗？未保存的更改将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // 取消放弃
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // 确认放弃
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return result ?? false; // 如果用户点击对话框外部，默认不放弃
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 阻止默认的弹出行为
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop || !mounted) return; // 如果已经弹出或组件未挂载，不做任何事情

        final shouldPop = await _onWillPop();
        if (shouldPop) {
          // 返回取消信号
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop({'cancelled': true});
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('编辑视频'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (!mounted) return;

              final shouldPop = await _onWillPop();
              if (shouldPop) {
                // 返回取消信号
                // ignore: use_build_context_synchronously
                Navigator.of(context).pop({'cancelled': true});
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (!mounted) return;

                final shouldPop = await _onWillPop();
                if (shouldPop) {
                  // 返回取消信号
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).pop({'cancelled': true});
                }
              },
              child: const Text(
                '放弃',
                style: TextStyle(
                    color: Color.fromARGB(255, 174, 174, 174),
                    fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: _saveVideo,
              child: Text(
                '完成',
                style: TextStyle(
                  color: Colors.pink.shade500,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // 视频播放器
            Expanded(
              child: VideoViewer(trimmer: _trimmer),
            ),

            // 进度条和控制
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black87,
              child: Column(
                children: [
                  // 时间显示
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(
                            Duration(milliseconds: _startValue.toInt())),
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        _formatDuration(
                            Duration(milliseconds: _endValue.toInt())),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),

                  // 剪辑进度条
                  TrimViewer(
                    trimmer: _trimmer,
                    viewerHeight: 50,
                    viewerWidth: MediaQuery.of(context).size.width,
                    onChangeStart: (value) => _startValue = value,
                    onChangeEnd: (value) => _endValue = value,
                    onChangePlaybackState: (value) =>
                        setState(() => _isPlaying = value),
                  ),

                  // 播放控制
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          final playbackState =
                              await _trimmer.videoPlaybackControl(
                            startValue: _startValue,
                            endValue: _endValue,
                          );
                          setState(() {
                            _isPlaying = playbackState;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 进度指示器
            if (_progressVisibility) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
