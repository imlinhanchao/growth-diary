import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../services/cloud_storage_service.dart';
import '../services/media_service.dart';

class FullScreenImageView extends StatefulWidget {
  final List<String> imagePaths;
  final CloudStorageService webdavService;
  final int initialIndex;
  final Function(String)? onSetAsCoverImage;

  const FullScreenImageView({
    super.key,
    required this.imagePaths,
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadFullImage(widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.imagePaths.length}'),
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
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
          _loadFullImage(index);
        },
        itemCount: widget.imagePaths.length,
        itemBuilder: (context, index) {
          final imageData = _fullImageCache[index];
          final isLoading = _loadingFullImages[index] ?? false;

          if (isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
          } else if (imageData != null) {
            return InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.memory(
                  imageData,
                  fit: BoxFit.contain,
                ),
              ),
            );
          } else {
            return const Center(
              child: Icon(
                Icons.image,
                color: Colors.white,
                size: 100,
              ),
            );
          }
        },
      ),
    );
  }
}
