import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cloud_storage_service.dart';
import '../services/media_service.dart';

class FullScreenImageView extends StatefulWidget {
  final List<String> imagePaths;
  final List<String>? thumbnailPaths;
  final CloudStorageService webdavService;
  final int initialIndex;
  final Function(String)? onSetAsCoverImage;

  const FullScreenImageView({
    super.key,
    required this.imagePaths,
    this.thumbnailPaths,
    required this.webdavService,
    this.initialIndex = 0,
    this.onSetAsCoverImage,
  });

  @override
  State<FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, Uint8List?> _fullImageCache = {};
  final Map<int, bool> _loadingFullImages = {};
  final Map<int, Uint8List?> _thumbnailCache = {};

  bool _showControls = true;
  bool _isCurrentPageZoomed = false;
  double _verticalDragOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadFullImage(widget.initialIndex);
    _loadThumbnail(widget.initialIndex);

    // 预热相邻缩略图
    if (widget.initialIndex > 0) {
      _loadThumbnail(widget.initialIndex - 1);
    }
    if (widget.initialIndex < widget.imagePaths.length - 1) {
      _loadThumbnail(widget.initialIndex + 1);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _pruneCache(int currentIndex) {
    // 保持最多 5 张大图在内存，超过则清理距离当前页最远的图片
    if (_fullImageCache.length > 5) {
      final keys = _fullImageCache.keys.toList()
        ..sort((a, b) =>
            (b - currentIndex).abs().compareTo((a - currentIndex).abs()));
      while (keys.length > 5) {
        final furthest = keys.removeAt(0);
        _fullImageCache.remove(furthest);
      }
    }
  }

  Future<void> _loadThumbnail(int index) async {
    if (widget.thumbnailPaths == null ||
        index < 0 ||
        index >= widget.thumbnailPaths!.length) {
      return;
    }
    if (_thumbnailCache.containsKey(index)) return;

    try {
      final data =
          await widget.webdavService.downloadFile(widget.thumbnailPaths![index]);
      if (data != null && mounted) {
        setState(() {
          _thumbnailCache[index] = data;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFullImage(int index) async {
    if (index < 0 || index >= widget.imagePaths.length) return;

    if (!_fullImageCache.containsKey(index)) {
      setState(() {
        _loadingFullImages[index] = true;
      });
      try {
        final data =
            await widget.webdavService.downloadFile(widget.imagePaths[index]);
        if (data != null && mounted) {
          setState(() {
            _fullImageCache[index] = data;
            _loadingFullImages[index] = false;
          });
          _pruneCache(index);
        }
      } catch (e) {
        debugPrint('Error loading full image ${widget.imagePaths[index]}: $e');
        if (mounted) {
          setState(() {
            _loadingFullImages[index] = false;
          });
        }
      }
    }
  }

  Future<void> _shareImage() async {
    final imageData = _fullImageCache[_currentIndex];
    if (imageData != null) {
      final success = await MediaService.shareImage(
        imagePath: widget.imagePaths[_currentIndex],
        imageData: imageData,
        cloudService: widget.webdavService,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享图片失败')),
        );
      }
    }
  }

  Future<void> _downloadImage() async {
    final imageData = _fullImageCache[_currentIndex];
    if (imageData != null) {
      final result = await MediaService.downloadImage(
        imagePath: widget.imagePaths[_currentIndex],
        imageData: imageData,
        cloudService: widget.webdavService,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    }
  }

  void _setAsCoverImage() {
    if (widget.onSetAsCoverImage != null) {
      widget.onSetAsCoverImage!(widget.imagePaths[_currentIndex]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已设为宝宝封面图')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 根据下拉拖拽位移计算背景不透明度 (0.0 ~ 1.0)
    final dragProgress = (_verticalDragOffset / 300.0).clamp(0.0, 1.0);
    final bgOpacity = (1.0 - dragProgress * 0.75).clamp(0.0, 1.0);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (_currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (_currentIndex < widget.imagePaths.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: bgOpacity),
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedOpacity(
            opacity: _showControls && _verticalDragOffset == 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls || _verticalDragOffset != 0,
              child: AppBar(
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                foregroundColor: Colors.white,
                elevation: 0,
                title:
                    Text('${_currentIndex + 1} / ${widget.imagePaths.length}'),
                actions: [
                  if (widget.onSetAsCoverImage != null)
                    IconButton(
                      icon: const Icon(Icons.photo_album),
                      tooltip: '设为封面图',
                      onPressed: _setAsCoverImage,
                    ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: _shareImage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: _downloadImage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: PageView.builder(
          controller: _pageController,
          // 放大状态下禁用 PageView 滑动，防止平移大图时意外翻页
          physics: _isCurrentPageZoomed
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
              _isCurrentPageZoomed = false;
              _verticalDragOffset = 0.0;
            });
            _loadFullImage(index);
            _loadThumbnail(index);
          },
          itemCount: widget.imagePaths.length,
          itemBuilder: (context, index) {
            final fullImageData = _fullImageCache[index];
            final thumbnailData = _thumbnailCache[index];
            final isLoading = _loadingFullImages[index] ?? false;

            return _ZoomableImageView(
              fullImageData: fullImageData,
              thumbnailData: thumbnailData,
              isLoading: isLoading,
              onTap: _toggleControls,
              onZoomChanged: (isZoomed) {
                if (index == _currentIndex) {
                  setState(() {
                    _isCurrentPageZoomed = isZoomed;
                  });
                }
              },
              onDragUpdate: (offset) {
                if (index == _currentIndex) {
                  setState(() {
                    _verticalDragOffset = offset;
                  });
                }
              },
              onDismiss: () => Navigator.of(context).pop(),
            );
          },
        ),
      ),
    );
  }
}

/// 支持双击放大、手势平移、缩放与下拉退出的单个图片视口组件
class _ZoomableImageView extends StatefulWidget {
  final Uint8List? fullImageData;
  final Uint8List? thumbnailData;
  final bool isLoading;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDismiss;

  const _ZoomableImageView({
    required this.fullImageData,
    required this.thumbnailData,
    required this.isLoading,
    required this.onTap,
    required this.onZoomChanged,
    required this.onDragUpdate,
    required this.onDismiss,
  });

  @override
  State<_ZoomableImageView> createState() => _ZoomableImageViewState();
}

class _ZoomableImageViewState extends State<_ZoomableImageView>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _zoomAnimation;
  Animation<double>? _dragResetAnimation;

  double _dragOffset = 0.0;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(_onTransformationChanged);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.05;
    if (isZoomed != _isZoomed) {
      _isZoomed = isZoomed;
      widget.onZoomChanged(isZoomed);
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_animationController.isAnimating) return;

    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();

    final targetScale = currentScale > 1.2 ? 1.0 : 2.5;
    final Matrix4 endMatrix;

    if (targetScale == 1.0) {
      endMatrix = Matrix4.identity();
    } else {
      // 以双击位置为焦点进行缩放
      final tapPos = details.localPosition;
      final x = -tapPos.dx * (targetScale - 1);
      final y = -tapPos.dy * (targetScale - 1);
      endMatrix = Matrix4.identity()
        ..translateByDouble(x, y, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, targetScale, 1.0);
    }

    _zoomAnimation = Matrix4Tween(
      begin: currentMatrix,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.addListener(_applyZoomAnimation);
    _animationController.forward(from: 0).then((_) {
      _animationController.removeListener(_applyZoomAnimation);
    });
  }

  void _applyZoomAnimation() {
    if (_zoomAnimation != null) {
      _transformationController.value = _zoomAnimation!.value;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;

    // 仅在已开始下拉或向下拖动时生效
    if (_dragOffset == 0.0 && details.primaryDelta! <= 0) return;

    setState(() {
      _dragOffset = math.max(0.0, _dragOffset + details.primaryDelta!);
    });
    widget.onDragUpdate(_dragOffset);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;

    // 下拉位移超过 90px 或速度超过 500px/s 时触发退出
    if (_dragOffset > 90 || details.velocity.pixelsPerSecond.dy > 500) {
      widget.onDismiss();
    } else {
      // 弹性复位
      final startOffset = _dragOffset;
      _dragResetAnimation = Tween<double>(begin: startOffset, end: 0.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
      );

      _animationController.addListener(_applyDragReset);
      _animationController.forward(from: 0).then((_) {
        _animationController.removeListener(_applyDragReset);
      });
    }
  }

  void _applyDragReset() {
    if (_dragResetAnimation != null) {
      setState(() {
        _dragOffset = _dragResetAnimation!.value;
      });
      widget.onDragUpdate(_dragOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageScale = (1.0 - (_dragOffset / 1000.0)).clamp(0.75, 1.0);

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: _handleDoubleTap,
      onDoubleTap: () {}, // 占位以激活 doubleTapDown
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Transform.scale(
          scale: imageScale,
          child: InteractiveViewer(
            transformationController: _transformationController,
            panEnabled: _isZoomed,
            scaleEnabled: true,
            minScale: 1.0,
            maxScale: 4.5,
            child: Center(
              child: _buildImageContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (widget.fullImageData != null) {
      return Image.memory(
        widget.fullImageData!,
        fit: BoxFit.contain,
      );
    }

    // 大图还在加载中：如果已有本地缩略图，先平滑呈现缩略图占位
    if (widget.thumbnailData != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            widget.thumbnailData!,
            fit: BoxFit.contain,
          ),
          if (widget.isLoading)
            const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      );
    }

    if (widget.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: Colors.white54,
        size: 80,
      ),
    );
  }
}
