import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../models/diary_entry.dart';
import '../services/cloud_storage_service.dart';

class TvSlideshowScreen extends StatefulWidget {
  final List<String> imagePaths;
  final CloudStorageService cloudService;
  final AppConfig config;
  final List<DiaryEntry> entries;

  const TvSlideshowScreen({
    super.key,
    required this.imagePaths,
    required this.cloudService,
    required this.config,
    required this.entries,
  });

  @override
  State<TvSlideshowScreen> createState() => _TvSlideshowScreenState();
}

class _TvSlideshowScreenState extends State<TvSlideshowScreen> {
  int _currentIndex = 0;
  bool _isPlaying = true;
  Timer? _timer;
  final Map<int, Uint8List?> _imageCache = {};
  final Map<int, bool> _loadingMap = {};
  bool _showOverlay = true;
  Timer? _overlayTimer;

  // 路径到条目的快速索引
  late final Map<String, DiaryEntry> _pathToEntry;

  @override
  void initState() {
    super.initState();
    _buildPathIndex();
    _loadImage(_currentIndex);
    _preloadAdjacent(_currentIndex);
    _startTimer();
    _resetOverlayTimer();
  }

  void _buildPathIndex() {
    _pathToEntry = {};
    for (final entry in widget.entries) {
      for (final path in entry.imagePaths) {
        _pathToEntry[path] = entry;
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_isPlaying) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _nextImage();
    });
  }

  void _resetOverlayTimer() {
    _overlayTimer?.cancel();
    setState(() => _showOverlay = true);
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    if (_isPlaying) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
    _resetOverlayTimer();
  }

  void _nextImage() {
    if (widget.imagePaths.isEmpty) return;
    final next = (_currentIndex + 1) % widget.imagePaths.length;
    _goToIndex(next);
  }

  void _prevImage() {
    if (widget.imagePaths.isEmpty) return;
    final prev =
        (_currentIndex - 1 + widget.imagePaths.length) % widget.imagePaths.length;
    _goToIndex(prev);
  }

  void _goToIndex(int index) {
    setState(() {
      _currentIndex = index;
    });
    _loadImage(index);
    _preloadAdjacent(index);
    if (_isPlaying) _startTimer();
    _resetOverlayTimer();
  }

  Future<void> _loadImage(int index) async {
    if (index < 0 || index >= widget.imagePaths.length) return;
    if (_imageCache.containsKey(index)) return;

    setState(() => _loadingMap[index] = true);
    try {
      final path = widget.imagePaths[index];
      final bytes = await widget.cloudService.downloadFile(path);
      if (mounted) {
        setState(() {
          _imageCache[index] = bytes;
          _loadingMap[index] = false;
        });
      }
    } catch (e) {
      debugPrint('Error downloading slideshow image $index: $e');
      if (mounted) {
        setState(() => _loadingMap[index] = false);
      }
    }
  }

  void _preloadAdjacent(int current) {
    if (widget.imagePaths.length <= 1) return;
    final next1 = (current + 1) % widget.imagePaths.length;
    final next2 = (current + 2) % widget.imagePaths.length;
    _loadImage(next1);
    _loadImage(next2);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = widget.imagePaths.isNotEmpty
        ? widget.imagePaths[_currentIndex]
        : '';
    final currentEntry = _pathToEntry[currentPath];
    final currentImage = _imageCache[_currentIndex];
    final isLoading = _loadingMap[_currentIndex] ?? false;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _nextImage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _prevImage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _togglePlayPause();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _togglePlayPause,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 主画面 (带淡入淡出切换)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: currentImage != null
                    ? Image.memory(
                        currentImage,
                        key: ValueKey(_currentIndex),
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : (isLoading
                        ? const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white70),
                          )
                        : const Center(
                            child: Icon(Icons.broken_image,
                                size: 64, color: Colors.white38),
                          )),
              ),

              // 播放/暂停快捷提示
              if (!_isPlaying)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.pause, size: 56, color: Colors.white70),
                  ),
                ),

              // 顶部状态条
              AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black54, Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Text(
                          '${_currentIndex + 1} / ${widget.imagePaths.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 底部信息卡片
              AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (currentEntry != null) ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.pink.shade600,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        currentEntry.getSimplifiedAgeLabel(
                                            widget.config),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${currentEntry.date.year}-${currentEntry.date.month.toString().padLeft(2, '0')}-${currentEntry.date.day.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 14),
                                    ),
                                  ],
                                ),
                                if (currentEntry.title.isNotEmpty ||
                                    currentEntry.description.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    currentEntry.title.isNotEmpty
                                        ? currentEntry.title
                                        : currentEntry.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        Text(
                          _isPlaying ? '自动播放中 (按确定键暂停)' : '已暂停 (按确定键继续)',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
