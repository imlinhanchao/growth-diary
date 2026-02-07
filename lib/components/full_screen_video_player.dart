import 'package:flutter/material.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import '../services/cloud_storage_service.dart';
import '../services/media_service.dart';

class FullScreenVideoPlayer extends StatefulWidget {
  final List<String> videoPaths;
  final CloudStorageService webdavService;
  final int initialIndex;

  const FullScreenVideoPlayer({
    super.key,
    required this.videoPaths,
    required this.webdavService,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, VideoPlayerController?> _controllers = {};
  final Map<int, bool> _isInitialized = {};
  final Map<int, bool> _isPlaying = {};
  final Map<int, bool> _showControls = {};
  final Map<int, bool> _isLoading = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    // 初始化当前视频
    _initializeVideo(widget.initialIndex);

    // 预加载相邻视频
    if (widget.initialIndex > 0) {
      _initializeVideo(widget.initialIndex - 1);
    }
    if (widget.initialIndex < widget.videoPaths.length - 1) {
      _initializeVideo(widget.initialIndex + 1);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller?.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeVideo(int index) async {
    if (index < 0 || index >= widget.videoPaths.length) return;
    if (_controllers.containsKey(index)) return;

    try {
      setState(() {
        _isLoading[index] = true;
      });

      // 从WebDAV下载视频数据
      final videoData =
          await widget.webdavService.downloadFile(widget.videoPaths[index]);
      if (videoData == null) {
        throw Exception('无法下载视频文件');
      }

      // 创建临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_video_$index.mp4');
      await tempFile.writeAsBytes(videoData);

      // 创建视频控制器
      final controller = VideoPlayerController.file(tempFile);
      _controllers[index] = controller;

      // 初始化控制器
      await controller.initialize();

      // 设置循环播放
      controller.setLooping(false); // 不循环，播放完后自动切换

      // 监听播放状态变化
      controller.addListener(() => _onVideoStateChanged(index));

      if (mounted) {
        setState(() {
          _isInitialized[index] = true;
          _isPlaying[index] = true;
          _showControls[index] = true;
          _isLoading[index] = false;
        });

        // 自动开始播放
        controller.play();
      }
    } catch (e) {
      debugPrint('Error initializing video $index: $e');
      if (mounted) {
        setState(() {
          _isLoading[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频加载失败: $e')),
        );
      }
    }
  }

  void _onVideoStateChanged(int index) {
    if (!mounted) return;

    final controller = _controllers[index];
    if (controller == null) return;

    final wasPlaying = _isPlaying[index] ?? false;
    final isPlaying = controller.value.isPlaying;

    // 如果播放状态发生变化，更新UI
    if (wasPlaying != isPlaying) {
      setState(() {
        _isPlaying[index] = isPlaying;
      });
    }

    // 检查是否播放完成
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration.inMilliseconds > 0) {
      // 播放完成，自动切换到下一个视频
      _playNextVideo();
    }
  }

  void _playNextVideo() {
    if (_currentIndex < widget.videoPaths.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 如果是最后一个视频，停止播放
      final controller = _controllers[_currentIndex];
      if (controller != null) {
        controller.pause();
        controller.seekTo(Duration.zero);
      }
    }
  }

  void _togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller == null) return;

    if (_isPlaying[index] ?? false) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  void _toggleControls(int index) {
    setState(() {
      _showControls[index] = !(_showControls[index] ?? true);
    });
  }

  Future<void> _shareVideo() async {
    final videoPath = widget.videoPaths[_currentIndex];
    final success = await MediaService.shareVideo(
      videoPath: videoPath,
      cloudService: widget.webdavService,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享视频失败')),
      );
    }
  }

  Future<void> _downloadVideo() async {
    final videoPath = widget.videoPaths[_currentIndex];
    final result = await MediaService.downloadVideo(
      videoPath: videoPath,
      cloudService: widget.webdavService,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onPageChanged(int index) {
    // 暂停之前的视频
    final previousController = _controllers[_currentIndex];
    if (previousController != null) {
      previousController.pause();
    }

    setState(() {
      _currentIndex = index;
    });

    // 如果视频已经初始化，自动播放
    if (_isInitialized[index] == true) {
      final controller = _controllers[index];
      if (controller != null) {
        setState(() {
          _isPlaying[index] = true;
        });
        controller.play();
      }
    } else {
      // 初始化新视频（如果还没初始化）
      _initializeVideo(index);
    }

    // 预加载相邻视频
    if (index > 0 && !_controllers.containsKey(index - 1)) {
      _initializeVideo(index - 1);
    }
    if (index < widget.videoPaths.length - 1 &&
        !_controllers.containsKey(index + 1)) {
      _initializeVideo(index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.videoPaths.length,
        itemBuilder: (context, index) {
          final controller = _controllers[index];
          final isInitialized = _isInitialized[index] ?? false;
          final isPlaying = _isPlaying[index] ?? false;
          final showControls = _showControls[index] ?? true;
          final isLoading = _isLoading[index] ?? false;

          return Stack(
            children: [
              // 视频播放器
              if (isInitialized && controller != null)
                GestureDetector(
                  onTap: () => _toggleControls(index),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                )
              else if (isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else
                const Center(
                  child: Icon(
                    Icons.videocam_off,
                    color: Colors.white,
                    size: 100,
                  ),
                ),

              // 控制层
              if (showControls && isInitialized && controller != null)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Column(
                    children: [
                      // 顶部栏
                      AppBar(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        leading: IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        title: Text(
                          '${index + 1} / ${widget.videoPaths.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.share, color: Colors.white),
                            onPressed: _shareVideo,
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.download, color: Colors.white),
                            onPressed: _downloadVideo,
                          ),
                        ],
                      ),

                      const Spacer(),

                      // 底部控制栏
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 进度条
                            VideoProgressIndicator(
                              controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.pink,
                                bufferedColor: Colors.white30,
                                backgroundColor: Colors.white12,
                              ),
                            ),

                            const SizedBox(height: 8),

                            // 时间和控制按钮
                            Row(
                              children: [
                                // 当前时间
                                Text(
                                  _formatDuration(controller.value.position),
                                  style: const TextStyle(color: Colors.white),
                                ),

                                const Spacer(),

                                // 播放/暂停按钮
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: () => _togglePlayPause(index),
                                ),

                                const Spacer(),

                                // 总时长
                                Text(
                                  _formatDuration(controller.value.duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 加载中指示器
              if (isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
