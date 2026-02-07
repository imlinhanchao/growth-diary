import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/diary_entry.dart';
import '../models/app_config.dart';
import '../services/cloud_storage_service.dart';
import '../utils/age_calculator.dart';
import '../components/full_screen_image_view.dart';
import '../components/full_screen_video_player.dart';
import 'diary_editor_screen.dart';

class EntryDetailScreen extends StatefulWidget {
  final DiaryEntry entry;
  final AppConfig config;
  final CloudStorageService cloudService;
  final void Function(EntryDetailResult, DiaryEntry)? onEntryUpdated;
  final void Function(AppConfig)? onConfigChanged;

  const EntryDetailScreen({
    super.key,
    required this.entry,
    required this.config,
    required this.cloudService,
    this.onEntryUpdated,
    this.onConfigChanged,
  });

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late DiaryEntry _currentEntry;
  final Map<String, Uint8List?> _imageCache = {};
  final Map<String, bool> _loadingImages = {};
  final Map<String, Uint8List?> _videoThumbnailCache = {};
  final Map<String, bool> _loadingVideoThumbnails = {};

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.entry;
    _loadImages();
    _loadVideoThumbnails();
  }

  Future<void> _loadImages() async {
    bool mediumLoaded = widget.entry.imageThumbnails.length == 1 ||
        widget.entry.imageThumbnails.length == 2 ||
        widget.entry.imageThumbnails.length == 4;
    for (var path in widget.entry.imageThumbnails) {
      if (mediumLoaded) path = path.replaceAll('small', 'medium');
      if (!_imageCache.containsKey(path)) {
        setState(() {
          _loadingImages[path] = true;
        });
        try {
          final data = await widget.cloudService.downloadFile(path);
          if (data != null && mounted) {
            setState(() {
              _imageCache[path] = data;
              _loadingImages[path] = false;
            });
          }
        } catch (e) {
          debugPrint('Error loading image thumbnail $path: $e');
          if (mounted) {
            setState(() {
              _loadingImages[path] = false;
            });
          }
        }
      }
    }
  }

  Future<void> _loadVideoThumbnails() async {
    for (var path in widget.entry.videoThumbnails) {
      if (!_videoThumbnailCache.containsKey(path)) {
        setState(() {
          _loadingVideoThumbnails[path] = true;
        });
        try {
          final data = await widget.cloudService.downloadFile(path);
          if (data != null && mounted) {
            setState(() {
              _videoThumbnailCache[path] = data;
              _loadingVideoThumbnails[path] = false;
            });
          }
        } catch (e) {
          debugPrint('Error loading video thumbnail $path: $e');
          if (mounted) {
            setState(() {
              _loadingVideoThumbnails[path] = false;
            });
          }
        }
      }
    }
  }

  void _showFullScreenImage(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenImageView(
          imagePaths: widget.entry.imagePaths,
          webdavService: widget.cloudService,
          initialIndex: initialIndex,
          onSetAsCoverImage:
              widget.onConfigChanged != null ? _setAsCoverImage : null,
        ),
      ),
    );
  }

  void _setAsCoverImage(String imagePath) {
    final updatedConfig = widget.config.copyWith(babyCoverImagePath: imagePath);
    widget.onConfigChanged!(updatedConfig);
  }

  String _getAgeDisplayText() {
    // 检查是否是孕期记录（在出生日期之前且配置了受孕日期）
    final isPregnancyPeriod = widget.config.conceptionDate != null &&
        _currentEntry.date
            .isBefore(widget.config.childBirthDate ?? DateTime.now());

    if (isPregnancyPeriod) {
      // 孕期记录：显示孕周和天数
      final totalDays =
          _currentEntry.date.difference(widget.config.conceptionDate!).inDays;
      final weeks = totalDays ~/ 7;
      final days = totalDays % 7;
      return '孕期 $weeks 周 $days 天';
    } else if (widget.config.childBirthDate != null &&
        _currentEntry.date.isBefore(widget.config.childBirthDate!)) {
      // 出生前记录但未配置受孕日期：显示出生前 X 月 X 天
      final diff = widget.config.childBirthDate!.difference(_currentEntry.date);
      final totalDays = diff.inDays;
      final months = totalDays ~/ 30; // 近似计算
      final days = totalDays % 30;
      return '出生前 $months 月 $days 天';
    } else {
      // 出生后记录：显示年龄
      return _currentEntry.getAgeLabel(widget.config);
    }
  }

  void _showFullScreenVideo(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullScreenVideoPlayer(
          videoPaths: _currentEntry.videoPaths,
          webdavService: widget.cloudService,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Future<void> _editDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _currentEntry.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.pink,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null && pickedDate != _currentEntry.date) {
      try {
        // 计算新的年龄月份
        final ageInMonths = widget.config.childBirthDate != null
            ? AgeCalculator.calculateAgeInMonths(
                widget.config.childBirthDate!, pickedDate)
            : 0;

        // 创建更新后的entry
        final updatedEntry = DiaryEntry(
          id: _currentEntry.id,
          title: _currentEntry.title,
          description: _currentEntry.description,
          date: pickedDate,
          imagePaths: _currentEntry.imagePaths,
          imageThumbnails: _currentEntry.imageThumbnails,
          videoPaths: _currentEntry.videoPaths,
          videoThumbnails: _currentEntry.videoThumbnails,
          ageInMonths: ageInMonths,
        );

        // 保存到WebDAV
        await widget.cloudService.saveDiaryEntry(updatedEntry);

        if (!mounted) return;

        // 更新当前状态
        setState(() {
          _currentEntry = updatedEntry;
        });

        // 通知首页有更新
        widget.onEntryUpdated
            ?.call(EntryDetailResult.updated(updatedEntry), widget.entry);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日期修改成功')),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('修改失败: $e')),
        );
      }
    }
  }

  Future<void> _editDescription() async {
    // 跳转到 DiaryEditorScreen 进行编辑
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryEditorScreen(
          config: widget.config,
          webdavService: widget.cloudService,
          entryToEdit: _currentEntry,
        ),
      ),
    );

    // 如果编辑成功，更新当前条目
    if (result is DiaryEntry && mounted) {
      setState(() {
        _currentEntry = result;
      });

      // 通知父组件有更新
      widget.onEntryUpdated
          ?.call(EntryDetailResult.updated(result), widget.entry);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日记修改成功')),
      );
    }
  }

  String _getWeekday(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.black87,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.black87),
            onPressed: _editDate,
            tooltip: '修改日期',
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.black87),
            onPressed: _editDescription,
            tooltip: '编辑内容',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认删除'),
                  content: const Text('确定要删除这条记录吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                try {
                  await widget.cloudService.deleteEntry(widget.entry);
                  if (context.mounted) {
                    Navigator.pop(context, EntryDetailResult.deleted());
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('删除失败: $e')),
                    );
                  }
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部日期和年龄卡片区域
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 大号日期
                Text(
                  '${_currentEntry.date.day}',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w300,
                    color: Colors.black87,
                    height: 1.0,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(width: 12),
                // 年月和星期
                Container(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_currentEntry.date.year}年${_currentEntry.date.month}月',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _getWeekday(_currentEntry.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // 年龄胶囊
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getAgeDisplayText(),
                    style: TextStyle(
                      color: Colors.pink.shade400,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // 标题（如果有）
            if (_currentEntry.title.isNotEmpty) ...[
              Text(
                _currentEntry.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1.3,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 描述内容
            if (_currentEntry.description.isNotEmpty) ...[
              Text(
                _currentEntry.description,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.8, // 增加行高，提升阅读体验
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 32),
            ] else if (_currentEntry.title.isEmpty) ...[
              // 如果既没标题也没描述，显示占位符（虽然正常逻辑不会出现空记录）
              Text(
                '没有文字记录',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 32),
            ],

            // 照片部分
            if (_currentEntry.imagePaths.isNotEmpty) ...[
              _buildSectionHeader(Icons.photo_library_outlined, '照片',
                  _currentEntry.imagePaths.length),
              const SizedBox(height: 16),
              _buildImageGrid(),
              const SizedBox(height: 32),
            ],

            // 视频部分
            if (_currentEntry.videoPaths.isNotEmpty) ...[
              _buildSectionHeader(Icons.videocam_outlined, '视频',
                  _currentEntry.videoPaths.length),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 视频使用 2 列显示，更大一些
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6, // 16:10 比例
                ),
                itemCount: _currentEntry.videoPaths.length,
                itemBuilder: (context, index) {
                  final thumbnailPath = _currentEntry.videoThumbnails[index];
                  final thumbnail = _videoThumbnailCache[thumbnailPath];
                  final isLoading =
                      _loadingVideoThumbnails[thumbnailPath] ?? false;

                  return GestureDetector(
                    onTap: () => _showFullScreenVideo(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 缩略图
                            isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : thumbnail != null
                                    ? Image.memory(
                                        thumbnail,
                                        fit: BoxFit.cover,
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.videocam,
                                          size: 40,
                                          color: Colors.pink.shade200,
                                        ),
                                      ),
                            // 播放按钮覆盖层
                            Container(
                              color: Colors.black.withValues(alpha: 0.1),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.pink,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    final images = _currentEntry.imagePaths;
    final thumbnails = _currentEntry.imageThumbnails;

    if (images.isEmpty) return const SizedBox.shrink();

    // 只有1张图：大卡片展示
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => _showFullScreenImage(0),
        child: Hero(
          tag: 'image_${_currentEntry.id}_0',
          child: Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildImageItem(
                  0, thumbnails[0].replaceAll('small', 'medium'), BoxFit.cover),
            ),
          ),
        ),
      );
    }

    // 2张或4张图：2列布局，其他情况3列布局
    int crossAxisCount = 3;
    if (images.length == 2 || images.length == 4) {
      crossAxisCount = 2;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: images.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _showFullScreenImage(index),
          child: Hero(
            tag: 'image_${_currentEntry.id}_$index',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImageItem(
                    index,
                    crossAxisCount == 2
                        ? thumbnails[index].replaceAll('small', 'medium')
                        : thumbnails[index],
                    BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageItem(int index, String thumbnailPath, BoxFit fit) {
    final imageData = _imageCache[thumbnailPath];
    final isLoading = _loadingImages[thumbnailPath] ?? false;

    if (isLoading) {
      return Container(
        color: Colors.grey.shade100,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (imageData != null) {
      return Image.memory(
        imageData,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 30,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, int count) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.pink.shade300),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
