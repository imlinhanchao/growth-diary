import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
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

  // 控制层自动隐藏定时器
  Timer? _hideControlsTimer;

  // 双击快进快退反馈
  TapDownDetails? _lastTapDownDetails;
  String? _seekFeedbackText;
  bool _isSeekForward = false;
  Timer? _feedbackTimer;

  // 播放倍速
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    // 仅初始化当前视频，避免打开即并发全量下载多个视频导致内存溢出
    _initializeVideo(widget.initialIndex);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _feedbackTimer?.cancel();
    // 恢复默认屏幕旋转方向
    SystemChrome.setPreferredOrientations([]);
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller?.dispose();
    }
    super.dispose();
  }

  void _disposeDistantControllers(int activeIndex) {
    final keysToRemove = <int>[];
    _controllers.forEach((idx, controller) {
      // 保持当前和相邻视频（如果有），销毁较远的控制器，释放硬件解码器和资源
      if ((idx - activeIndex).abs() > 1) {
        controller?.dispose();
        keysToRemove.add(idx);
      }
    });
    for (final key in keysToRemove) {
      _controllers.remove(key);
      _isInitialized.remove(key);
      _isPlaying.remove(key);
      _isLoading.remove(key);
      _showControls.remove(key);
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isPlaying[_currentIndex] == true) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && (_isPlaying[_currentIndex] == true)) {
          setState(() {
            _showControls[_currentIndex] = false;
          });
        }
      });
    }
  }

  Future<void> _initializeVideo(int index) async {
    if (index < 0 || index >= widget.videoPaths.length) return;
    if (_controllers.containsKey(index)) return;

    try {
      setState(() {
        _isLoading[index] = true;
      });

      // 从WebDAV以流式写入本地磁盘文件（零内存缓冲，并自动走本地缓存）
      final videoFile =
          await widget.webdavService.downloadToFile(widget.videoPaths[index]);
      if (videoFile == null || !await videoFile.exists()) {
        throw Exception('无法下载视频文件');
      }

      // 如果下载期间用户已滑走较远，不再初始化控制器
      if (!mounted || (_currentIndex - index).abs() > 1) {
        return;
      }

      // 创建视频控制器，直接播放本地缓存文件
      final controller = VideoPlayerController.file(videoFile);
      _controllers[index] = controller;

      // 初始化控制器
      await controller.initialize();

      // 设置循环播放
      controller.setLooping(false); // 不循环，播放完后自动切换

      // 应用当前选择的倍速
      if (_playbackSpeed != 1.0) {
        await controller.setPlaybackSpeed(_playbackSpeed);
      }

      // 监听播放状态变化
      controller.addListener(() => _onVideoStateChanged(index));

      if (mounted) {
        final isCurrent = index == _currentIndex;
        setState(() {
          _isInitialized[index] = true;
          _isPlaying[index] = isCurrent;
          _showControls[index] = true;
          _isLoading[index] = false;
        });

        // 仅在当前视图时自动开始播放
        if (isCurrent) {
          controller.play();
          _startHideControlsTimer();
        }
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
      if (isPlaying) {
        _startHideControlsTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
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
      _hideControlsTimer?.cancel();
      setState(() {
        _isPlaying[index] = false;
        _showControls[index] = true;
      });
    } else {
      controller.play();
      setState(() {
        _isPlaying[index] = true;
      });
      _startHideControlsTimer();
    }
  }

  void _toggleControls(int index) {
    setState(() {
      final willShow = !(_showControls[index] ?? true);
      _showControls[index] = willShow;
      if (willShow) {
        _startHideControlsTimer();
      } else {
        _hideControlsTimer?.cancel();
      }
    });
  }

  void _triggerSeekFeedback(String text, bool isForward) {
    HapticFeedback.lightImpact();
    _feedbackTimer?.cancel();
    setState(() {
      _seekFeedbackText = text;
      _isSeekForward = isForward;
    });
    _feedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _seekFeedbackText = null;
        });
      }
    });
    _startHideControlsTimer();
  }

  void _seekRelative(int seconds) {
    final controller = _controllers[_currentIndex];
    if (controller != null && controller.value.isInitialized) {
      final newPos = controller.value.position + Duration(seconds: seconds);
      final duration = controller.value.duration;
      final clampedPos = newPos < Duration.zero
          ? Duration.zero
          : (newPos > duration ? duration : newPos);
      controller.seekTo(clampedPos);
      _startHideControlsTimer();
    }
  }

  void _toggleOrientation() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _showSpeedSelectionModal(VideoPlayerController controller) {
    _startHideControlsTimer();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '播放速度',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...speeds.map((speed) {
                  final isSelected = (_playbackSpeed == speed);
                  return ListTile(
                    dense: true,
                    title: Center(
                      child: Text(
                        '${speed}x${speed == 1.0 ? ' (正常)' : ''}',
                        style: TextStyle(
                          color: isSelected ? Colors.pink : Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _playbackSpeed = speed;
                      });
                      controller.setPlaybackSpeed(speed);
                      Navigator.of(context).pop();
                      _startHideControlsTimer();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
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

    _hideControlsTimer?.cancel();

    // 释放过远的解码器控制器，避免内存泄漏与解码器耗尽
    _disposeDistantControllers(index);

    setState(() {
      _currentIndex = index;
    });

    // 如果视频已经初始化，自动播放
    if (_isInitialized[index] == true) {
      final controller = _controllers[index];
      if (controller != null) {
        if (_playbackSpeed != 1.0) {
          controller.setPlaybackSpeed(_playbackSpeed);
        }
        setState(() {
          _isPlaying[index] = true;
          _showControls[index] = true;
        });
        controller.play();
        _startHideControlsTimer();
      }
    } else {
      // 初始化新视频
      _initializeVideo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            _togglePlayPause(_currentIndex);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _seekRelative(-5);
            _triggerSeekFeedback('-5s', false);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _seekRelative(5);
            _triggerSeekFeedback('+5s', true);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (_currentIndex < widget.videoPaths.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
                // 视频播放器与手势捕获
                if (isInitialized && controller != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        _lastTapDownDetails = details;
                      },
                      onDoubleTap: () {
                        if (_lastTapDownDetails == null) return;
                        final screenWidth = MediaQuery.of(context).size.width;
                        final dx = _lastTapDownDetails!.globalPosition.dx;
                        if (dx < screenWidth * 0.35) {
                          _seekRelative(-10);
                          _triggerSeekFeedback('-10s', false);
                        } else if (dx > screenWidth * 0.65) {
                          _seekRelative(10);
                          _triggerSeekFeedback('+10s', true);
                        } else {
                          _togglePlayPause(index);
                        }
                      },
                      onTap: () => _toggleControls(index),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
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

                // 双击快退指示器
                if (_seekFeedbackText != null && !_isSeekForward)
                  Positioned(
                    left: 36,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fast_rewind,
                                color: Colors.white, size: 28),
                            const SizedBox(width: 6),
                            Text(
                              _seekFeedbackText!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 双击快进指示器
                if (_seekFeedbackText != null && _isSeekForward)
                  Positioned(
                    right: 36,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _seekFeedbackText!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.fast_forward,
                                color: Colors.white, size: 28),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 控制层
                if (showControls && isInitialized && controller != null)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: Column(
                        children: [
                          // 顶部栏
                          AppBar(
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            leading: IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            title: Text(
                              '${index + 1} / ${widget.videoPaths.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            actions: [
                              IconButton(
                                icon: const Icon(Icons.share,
                                    color: Colors.white),
                                onPressed: _shareVideo,
                              ),
                              IconButton(
                                icon: const Icon(Icons.download,
                                    color: Colors.white),
                                onPressed: _downloadVideo,
                              ),
                            ],
                          ),

                          // 中间点击空白区与居中播放/暂停按钮
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => _toggleControls(index),
                              child: Center(
                                child: GestureDetector(
                                  onTap: () => _togglePlayPause(index),
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 38,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 底部控制栏
                          SafeArea(
                            top: false,
                            left: false,
                            right: false,
                            bottom: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 进度条
                                  VideoProgressIndicator(
                                    controller,
                                    allowScrubbing: true,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8),
                                    colors: const VideoProgressColors(
                                      playedColor: Colors.pink,
                                      bufferedColor: Colors.white30,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  // 时间、倍速与全屏控制
                                  Row(
                                    children: [
                                      // 当前时间 / 总时长
                                      Text(
                                        _formatDuration(
                                            controller.value.position),
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 13),
                                      ),
                                      const Text(
                                        ' / ',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        _formatDuration(
                                            controller.value.duration),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13),
                                      ),

                                      const Spacer(),

                                      // 倍速切换按钮
                                      GestureDetector(
                                        onTap: () =>
                                            _showSpeedSelectionModal(
                                                controller),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.18),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _playbackSpeed == 1.0
                                                ? '倍速'
                                                : '${_playbackSpeed}x',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 8),

                                      // 横竖屏旋转切换
                                      IconButton(
                                        icon: Icon(
                                          isLandscape
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                        tooltip: isLandscape ? '竖屏' : '全屏横屏',
                                        onPressed: _toggleOrientation,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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
      ),
    );
  }
}
