import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'dart:typed_data';
import 'dart:async';
import '../models/app_config.dart';
import '../models/diary_entry.dart';
import '../services/cloud_storage_service.dart';
import '../services/media_upload_service.dart';
import '../services/entry_creation_service.dart';
import '../utils/age_calculator.dart';
import '../utils/file_utils.dart' as file_utils;
import '../services/local_storage_service.dart';
import '../services/qr_service.dart';
import 'settings_screen.dart';
import 'diary_editor_screen.dart';
import 'batch_video_editor_screen.dart';
import 'upload_tasks_screen.dart';
import '../components/birth_date_label.dart';
import '../components/pregnancy_label.dart';
import '../components/current_month_separator.dart';
import '../components/group_separator.dart';
import '../components/timeline_item.dart';
import 'qr_scanner_screen.dart';

class UploadProgressData {
  final bool hasActiveTasks;
  final String progressText;
  final bool isRestoring;

  UploadProgressData(this.hasActiveTasks, this.progressText,
      {this.isRestoring = false});
}

class HomeScreen extends StatefulWidget {
  final Map<String, AppConfig> configs;
  final String currentConfigId;
  final CloudStorageService cloudService;
  final LocalStorageService localStorage;
  final void Function(AppConfig) onConfigChanged;

  const HomeScreen({
    super.key,
    required this.configs,
    required this.currentConfigId,
    required this.cloudService,
    required this.localStorage,
    required this.onConfigChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<DiaryEntry> _entries = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  String? _errorMessage;
  final Map<String, Uint8List?> _thumbnailCache = {};
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  Uint8List? _coverImageData;
  bool _isLoadingCoverImage = false;
  bool _isExpanded = false;
  final ValueNotifier<UploadProgressData> _uploadProgressNotifier =
      ValueNotifier(UploadProgressData(false, ''));

  late Map<String, AppConfig> configs;
  late String currentConfigId;
  late AppConfig currentConfig;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 10;
  DateTime? _targetMonth;

  late EntryCreationService _entryCreationService;

  @override
  void initState() {
    super.initState();
    configs = Map.from(widget.configs);
    currentConfigId = widget.currentConfigId;
    currentConfig = configs[currentConfigId]!;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);

    // 初始化WebDAV服务，为当前宝宝创建文件夹
    widget.cloudService.initialize(currentConfig).then((_) {
      debugPrint('WebDAV service initialized');
    }).catchError((e) {
      debugPrint('Error initializing WebDAV service: $e');
    });

    // 初始化 EntryCreationService
    _entryCreationService = EntryCreationService(widget.cloudService);

    // 初始化 MediaUploadService 并设置回调
    final uploadService = MediaUploadService();
    uploadService.initialize(
      widget.cloudService,
      currentConfig,
      _entryCreationService,
    );

    // 设置上传回调
    uploadService.setEntryCreatedCallback((entry) {
      print('created a entry: ${entry.id}');
      _updateUploadProgress();
      if (mounted) {
        _loadEntries();
      }
    });
    uploadService.setTaskCompletedCallback((task) {
      print('Upload completed for ${task.srcPath}');
      _updateUploadProgress();
    });
    uploadService.setTaskFailedCallback((task, error) {
      print('Upload failed for ${task.srcPath}: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('上传失败: ${task.srcPath.split('/').last} - $error')),
        );
      }
    });
    uploadService.setAllUploadsCompletedCallback(() => _updateUploadProgress());

    // 加载保存的任务队列
    MediaUploadService().loadTaskQueue(config: currentConfig).then((_) {
      // 如果有恢复的任务，显示恢复状态
      if (MediaUploadService.hasActiveUploads()) {
        _updateUploadProgress(isRestoring: true);
        // 延迟一下让用户看到恢复状态，然后开始正常显示
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _updateUploadProgress(isRestoring: false);
          }
        });
      }
    });

    // 初始化上传进度
    _updateUploadProgress(isRestoring: false);

    _loadEntries();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    MediaUploadService.removeUploadProgressCallback();
    MediaUploadService.removeUploadCompletedCallback();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台时，显示通知提醒用户有上传任务正在进行
        _showBackgroundUploadNotification();
        break;
      case AppLifecycleState.resumed:
        // 应用回到前台时，重新加载最新的配置（包括生日、受孕日等）
        _reloadLatestConfig();
        // 检查是否有未完成的上传
        _checkPendingUploads();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _loadEntries() async {
    debugPrint('Loading entries...');
    setState(() {
      _isLoading = true;
      _entries.clear();
      _hasMoreData = true;
      _errorMessage = null;
    });

    try {
      final entries = await widget.cloudService.loadAllEntries();
      debugPrint('Loaded ${entries.length} entries');
      setState(() {
        _entries = entries;
        _isLoading = false;
        _hasMoreData = entries.length == _pageSize;
      });

      // 加载封面图像
      _loadCoverImage();
    } catch (e) {
      debugPrint('Error loading entries: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _onRefresh() async {
    // 先获取最新的配置
    await _reloadLatestConfig();

    // 重新加载条目
    await _loadEntries();

    // 强制重新加载封面图（忽略缓存）
    await _loadCoverImage(forceRefresh: true);
  }

  Future<void> _handleEntryUpdate(
      EntryDetailResult result, DiaryEntry originalEntry) async {
    if (result.isDeleted) {
      // 删除条目
      setState(() {
        _entries.removeWhere((entry) => entry.id == originalEntry.id);
      });
    } else if (result.updatedEntry != null) {
      // 更新条目
      setState(() {
        final index =
            _entries.indexWhere((entry) => entry.id == originalEntry.id);
        if (index != -1) {
          _entries[index] = result.updatedEntry!;
        }
      });
    }
  }

  Future<void> _handleConfigChanged(AppConfig newConfig) async {
    setState(() {
      currentConfig = newConfig;
      // 清除封面图像缓存
      _coverImageData = null;
      _isLoadingCoverImage = false;
    });
    // 保存配置到本地存储
    await widget.localStorage.saveConfig(newConfig);
    // 保存到云端
    await widget.cloudService.saveConfig(newConfig);
    // 重新加载封面图像
    _loadCoverImage();
    // 通知父组件配置已更改
    widget.onConfigChanged(newConfig);
  }

  Future<void> _switchConfig() async {
    // 重新初始化WebDAV服务
    await widget.cloudService.initialize(currentConfig);

    // 清除当前数据
    setState(() {
      _entries.clear();
      _thumbnailCache.clear();
      _thumbnailFutures.clear();
      _coverImageData = null; // 清除封面图缓存
      _isLoadingCoverImage = false; // 重置加载状态
      _isLoading = true;
      _hasMoreData = true;
    });

    // 重新加载数据
    _loadEntries();
  }

  Future<void> _loadMoreEntries() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final newEntries =
          await widget.cloudService.loadEntriesPage(_entries.length, _pageSize);
      setState(() {
        _entries.addAll(newEntries);
        _isLoadingMore = false;
        _hasMoreData = newEntries.length == _pageSize;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败: $e')),
        );
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreEntries();
    }
  }

  void _scrollToMonth(DateTime date) {
    final targetMonth = date.day == 1 ? date : DateTime(date.year, date.month);
    setState(() => _targetMonth = targetMonth);
    // 滚动将在 build 后执行
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  Future<String?> _showDescriptionDialog() async {
    String description = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加描述（可选）'),
        content: TextField(
          onChanged: (value) => description = value,
          decoration: const InputDecoration(hintText: '请输入描述'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(description),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showDateAndDescriptionDialog(
      DateTime initialDate) async {
    DateTime selectedDate = initialDate;
    String description = '';

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false, // 必须选择日期，不能取消
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('选择日期并添加描述'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('检测到文件日期可能有误，请选择正确的日期'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  // 计算 firstDate：优先使用 conceptionDate，否则使用 childBirthDate 减去 280 天，最后使用 2000 年
                  final firstDate = currentConfig.conceptionDate ??
                      (currentConfig.childBirthDate
                          ?.subtract(const Duration(days: 280))) ??
                      DateTime(2000);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate.isBefore(firstDate)
                        ? firstDate
                        : selectedDate,
                    firstDate: firstDate,
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => selectedDate = picked);
                  }
                },
                child: Text(
                    '选择日期: ${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}'),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => description = value,
                decoration: const InputDecoration(hintText: '请输入描述（可选）'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: selectedDate != initialDate
                  ? () => Navigator.of(context)
                      .pop({'date': selectedDate, 'description': description})
                  : null,
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addImage() async {
    print('Add image button pressed');
    _toggleExpanded(); // 关闭菜单

    try {
      // 1. 调用 FileUtils.selectImages 选择图片
      final mediaFiles =
          await file_utils.FileUtils.selectImages(allowMultiple: true);
      if (mediaFiles.isEmpty) return;

      // 2. 显示 loading 界面
      if (!mounted) return;
      EasyLoading.show(status: '正在处理图片...');

      // 3. 并行处理所有文件
      final futures = mediaFiles.map((mediaFile) async {
        await file_utils.FileUtils.fillCreationDate(mediaFile);
        await file_utils.FileUtils.fillThumbnail(mediaFile);
      });
      await Future.wait(futures);
      // 4. 关闭 loading
      EasyLoading.dismiss();

      // 5. 检查是否有图片创建日期大于阈值日期
      DateTime? thresholdDate;
      if (currentConfig.conceptionDate != null) {
        thresholdDate = currentConfig.conceptionDate;
      } else if (currentConfig.childBirthDate != null) {
        thresholdDate =
            currentConfig.childBirthDate!.subtract(const Duration(days: 280));
      }

      // 检查是否有任何图片的创建日期早于阈值日期
      bool hasEarlyDate = false;
      DateTime earliestDate = DateTime.now();

      if (thresholdDate != null) {
        for (final mediaFile in mediaFiles) {
          if (mediaFile.createdAt != null) {
            final fileDate = mediaFile.createdAt!;
            if (fileDate.isBefore(thresholdDate)) {
              hasEarlyDate = true;
              if (fileDate.isBefore(earliestDate)) {
                earliestDate = fileDate;
              }
            }
          }
        }
      }

      // 6. 根据检查结果显示相应对话框
      String? description;
      DateTime? selectedDate;

      if (hasEarlyDate) {
        final result = await _showDateAndDescriptionDialog(earliestDate);
        if (result == null) return; // 用户取消
        selectedDate = result['date'] as DateTime;
        description = result['description'] as String;
        for (final mediaFile in mediaFiles) {
          if (mediaFile.createdAt != null) {
            final fileDate = mediaFile.createdAt!;
            if (fileDate.isBefore(thresholdDate!)) {
              // 覆盖创建日期
              mediaFile.createdAt = selectedDate; // 使用用户选择的日期
            }
            mediaFile.description = description;
          }
        }
      } else {
        description = await _showDescriptionDialog();
        if (description == null) return;
      }

      // 7. 通过 MediaUploadService 启动上传任务
      final uploadService = MediaUploadService();
      uploadService.initialize(
          widget.cloudService, currentConfig, _entryCreationService);

      // 创建 MediaTask 列表
      final tasks = mediaFiles
          .map((mediaFile) => MediaTask(
                srcPath: mediaFile.srcPath,
                type: mediaFile.type,
                thumbPathSmall: mediaFile.thumbPathSmall,
                thumbPathMedium: mediaFile.thumbPathMedium,
                createdAt: mediaFile.createdAt,
              ))
          .toList();

      // 启动上传
      uploadService.startUpload(
        tasks,
        description: description,
      );

      // 显示提示信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已开始上传，请查看上传任务')),
        );
      }
    } catch (e) {
      // 关闭可能的 loading 对话框
      EasyLoading.dismiss();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加图片失败: $e')),
        );
      }
    }
  }

  Future<void> _addVideo() async {
    print('Add video button pressed');
    _toggleExpanded(); // 关闭菜单

    try {
      // 1. 调用 FileUtils.selectVideos 选择视频
      final mediaFiles =
          await file_utils.FileUtils.selectVideos(allowMultiple: true);
      if (mediaFiles.isEmpty) return;

      // 2. 显示 loading 界面
      if (!mounted) return;
      EasyLoading.show(status: '正在处理视频...');

      // 3. 并行处理所有文件
      final futures = mediaFiles.map((mediaFile) async {
        await file_utils.FileUtils.fillCreationDate(mediaFile);
        await file_utils.FileUtils.fillThumbnail(mediaFile);
      });
      await Future.wait(futures);

      // 4. 关闭 loading
      EasyLoading.dismiss();

      // 5. 检查是否有视频创建日期大于阈值日期
      DateTime? thresholdDate;
      if (currentConfig.conceptionDate != null) {
        thresholdDate = currentConfig.conceptionDate;
      } else if (currentConfig.childBirthDate != null) {
        thresholdDate =
            currentConfig.childBirthDate!.subtract(const Duration(days: 280));
      }

      // 检查是否有任何视频的创建日期早于阈值日期
      bool hasEarlyDate = false;
      DateTime earliestDate = DateTime.now();

      if (thresholdDate != null) {
        for (final mediaFile in mediaFiles) {
          if (mediaFile.createdAt != null) {
            final fileDate = mediaFile.createdAt!;
            if (fileDate.isBefore(thresholdDate)) {
              hasEarlyDate = true;
              if (fileDate.isBefore(earliestDate)) {
                earliestDate = fileDate;
              }
            }
          }
        }
      }

      // 6. 根据检查结果显示相应对话框
      String? description;
      DateTime? selectedDate;

      if (hasEarlyDate) {
        final result = await _showDateAndDescriptionDialog(earliestDate);
        if (result == null) return; // 用户取消
        selectedDate = result['date'] as DateTime;
        description = result['description'] as String;
        for (final mediaFile in mediaFiles) {
          if (mediaFile.createdAt != null) {
            final fileDate = mediaFile.createdAt!;
            if (fileDate.isBefore(thresholdDate!)) {
              // 覆盖创建日期
              mediaFile.createdAt = selectedDate; // 使用用户选择的日期
            }
            mediaFile.description = description;
          }
        }
      } else {
        description = await _showDescriptionDialog();
        if (description == null) return;
      }

      // 7. 视频编辑步骤 - 批量编辑界面（传入 MediaFile list，返回 MediaFile list）
      final editResults = await Navigator.push(
        // ignore: use_build_context_synchronously
        context,
        MaterialPageRoute(
          builder: (context) => BatchVideoEditorScreen(
            mediaFiles: List.from(mediaFiles),
          ),
        ),
      );

      final editedMediaFiles = <file_utils.MediaFile>[];
      if (editResults != null) {
        // 用户完成了编辑，使用编辑结果
        editedMediaFiles.addAll(editResults);
      } else {
        // 用户放弃了所有编辑，取消上传
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已取消视频上传')),
          );
        }
        return;
      }

      // 8. 通过 MediaUploadService 启动上传任务
      final uploadService = MediaUploadService();
      uploadService.initialize(
          widget.cloudService, currentConfig, _entryCreationService);

      // 创建 MediaTask 列表
      final tasks = editedMediaFiles
          .map((mediaFile) => MediaTask(
                srcPath: mediaFile.srcPath,
                type: mediaFile.type,
                thumbPathSmall: mediaFile.thumbPathSmall,
                thumbPathMedium: mediaFile.thumbPathMedium,
                createdAt: mediaFile.createdAt,
              ))
          .toList();

      // 启动上传
      uploadService.startUpload(
        tasks,
        description: description,
      );

      // 显示提示信息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已开始上传，请查看上传任务')),
        );
      }
    } catch (e) {
      // 关闭可能的 loading 对话框
      EasyLoading.dismiss();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加记录失败: $e')),
        );
      }
    }
  }

  Future<void> _addDiary() async {
    print('Add diary button pressed');
    _toggleExpanded(); // 关闭菜单
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryEditorScreen(
          config: currentConfig,
          webdavService: widget.cloudService,
        ),
      ),
    ).then((_) => _loadEntries());
  }

  void _showBackgroundUploadNotification() {
    // 检查是否有活跃的上传任务
    if (MediaUploadService.hasActiveUploads()) {
      // 显示一个持续的通知，提醒用户有上传任务正在后台进行
      MediaUploadService.showBackgroundNotification(
        '成长日记上传中',
        '应用已切换到后台，上传任务将继续进行',
      );
    }
  }

  Future<void> _checkPendingUploads() async {
    // 应用回到前台时，检查是否有未完成的上传
    // 更新上传进度显示
    _updateUploadProgress();
  }

  void _updateUploadProgress({bool isRestoring = false}) {
    final hasActiveTasks = MediaUploadService.hasActiveUploads();
    final progressText = hasActiveTasks
        ? '${MediaUploadService.getCompletedTasks()}/${MediaUploadService.getTotalTasks()}'
        : '';

    _uploadProgressNotifier.value = UploadProgressData(
        hasActiveTasks, progressText,
        isRestoring: isRestoring);
  }

  Widget _buildSliverAppBar() {
    final bool showExpanded = _coverImageData != null || _isLoadingCoverImage;

    return SliverAppBar(
      expandedHeight: showExpanded ? 260.0 : null,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.pink,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          color: Colors.white,
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
        ),
      ),
      title: GestureDetector(
        onDoubleTap: () {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
        child: ValueListenableBuilder<UploadProgressData>(
          valueListenable: _uploadProgressNotifier,
          builder: (context, progressData, child) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  currentConfig.babyName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              if (progressData.hasActiveTasks) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        progressData.progressText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios,
                      size: 14, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UploadTasksScreen(),
                      ),
                    );
                  },
                  tooltip: '查看上传任务',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.calendar_month),
            color: Colors.white,
            onPressed: () {
              Scaffold.of(context).openEndDrawer();
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          color: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsScreen(
                  config: currentConfig,
                  cloudService: widget.cloudService,
                  onConfigChanged: (newConfig) async {
                    // 重新加载所有配置，以确保删除的配置被正确移除
                    final updatedConfigs =
                        await widget.localStorage.loadAllConfigs();
                    final currentId =
                        await widget.localStorage.getCurrentConfigId();
                    setState(() {
                      configs = updatedConfigs;
                      currentConfigId = currentId ?? '';
                      currentConfig =
                          configs[currentConfigId] ?? configs.values.first;
                    });
                    // 切换到新配置，确保界面更新
                    await _handleConfigChanged(newConfig);
                  },
                ),
              ),
            );
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.pink.shade300, Colors.pink.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            if (showExpanded && _coverImageData != null) ...[
              Image.memory(
                _coverImageData!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
              // 蒙版
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ] else if (showExpanded && _isLoadingCoverImage)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildConfigDrawer(),
      endDrawer: _buildTimelineDrawer(),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _onRefresh,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildSliverAppBar(),
                if (_isLoading)
                  const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()))
                else if (_errorMessage != null)
                  SliverFillRemaining(child: _buildErrorState())
                else if (_entries.isEmpty)
                  SliverFillRemaining(child: _buildEmptyState())
                else
                  _buildTimelineSliver(),
              ],
            ),
          ),
          Positioned(
            bottom: 16.0,
            right: 16.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 视频按钮 - 向上展开
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '添加视频',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.pink.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          heroTag: 'video_fab',
                          onPressed: _addVideo,
                          backgroundColor: Colors.pink.shade300,
                          foregroundColor: Colors.white,
                          mini: true,
                          shape: const CircleBorder(),
                          child: const Icon(Icons.videocam),
                        ),
                      ],
                    ),
                  ),
                // 图片按钮 - 向上展开
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '添加照片',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.pink.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          heroTag: 'image_fab',
                          onPressed: _addImage,
                          backgroundColor: Colors.pink.shade400,
                          foregroundColor: Colors.white,
                          mini: true,
                          shape: const CircleBorder(),
                          child: const Icon(Icons.photo),
                        ),
                      ],
                    ),
                  ),
                // 日记按钮 - 向上展开
                if (_isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '写日记',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.pink.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          heroTag: 'diary_fab',
                          onPressed: _addDiary,
                          backgroundColor: Colors.pink.shade500,
                          foregroundColor: Colors.white,
                          mini: true,
                          shape: const CircleBorder(),
                          child: const Icon(Icons.edit_note),
                        ),
                      ],
                    ),
                  ),

                FloatingActionButton(
                  heroTag: 'main_fab',
                  onPressed: _toggleExpanded,
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: AnimatedRotation(
                    turns: _isExpanded ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.add, size: 28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 100,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 20),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 20,
              color: Colors.red.shade600,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? '未知错误',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadEntries,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: Colors.pink.shade200,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '开启成长之旅',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '记录宝宝的每一个珍贵瞬间\n照片、视频或日记',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSliver() {
    if (_entries.isEmpty && !_isLoading) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    // Sort entries by date descending
    final sortedEntries = List<DiaryEntry>.from(_entries)
      ..sort((a, b) => b.date.compareTo(a.date));

    int? currentGroupKey;
    bool isFirstGroup = true;
    int? latestEntryGroupKey;

    // Build items list with special labels inserted dynamically
    final items = <Widget>[];
    final Map<DateTime, int> itemIndexMap = {};

    // Always add current month separator at the top
    items.add(CurrentMonthSeparator(config: currentConfig));

    // Check if the latest entry is not in current month, add its month separator
    if (sortedEntries.isNotEmpty) {
      final latestEntry = sortedEntries.first;
      final currentDate = DateTime.now();
      final birthDate = currentConfig.childBirthDate;
      if (birthDate != null) {
        final currentAgeInMonths =
            AgeCalculator.calculateAgeInMonths(birthDate, currentDate);
        final latestEntryGroupKey = latestEntry.getGroupKey(currentConfig);

        // If latest entry is not in current month, mark it as already handled
        if (latestEntryGroupKey != currentAgeInMonths) {
          currentGroupKey = latestEntryGroupKey;
          isFirstGroup = false;
        }
      }
    }

    // Find insertion points for special labels
    DateTime? birthDate = currentConfig.childBirthDate;
    DateTime? conceptionDate = currentConfig.conceptionDate;

    // Track if we've inserted special labels
    bool hasInsertedBirthLabel = false;
    bool hasInsertedConceptionLabel = false;

    // Pre-scan to find the first post-birth entry and last post-birth entry
    int? firstPostBirthIndex;
    int? lastPostBirthIndex;
    bool hasPreBirthEntries = false;
    bool hasPregnancyEntries = false;

    for (int i = 0; i < sortedEntries.length; i++) {
      if (birthDate != null) {
        if (sortedEntries[i].date.isBefore(birthDate)) {
          hasPreBirthEntries = true;
          // Check if this is a pregnancy entry (between conception and birth)
          if (conceptionDate != null &&
              sortedEntries[i].date.isAfter(conceptionDate)) {
            hasPregnancyEntries = true;
          }
        } else {
          firstPostBirthIndex ??= i;
          lastPostBirthIndex = i; // Keep updating to get the last one
        }
      } else if (conceptionDate != null &&
          sortedEntries[i].date.isAfter(conceptionDate)) {
        // If no birth date is set, any entry after conception is considered pregnancy entry
        hasPregnancyEntries = true;
      }
    }

    // Get the latest entry's group key if we already added its separator
    if (sortedEntries.isNotEmpty) {
      final latestEntry = sortedEntries.first;
      final currentDate = DateTime.now();
      final birthDate = currentConfig.childBirthDate;
      if (birthDate != null) {
        final currentAgeInMonths =
            AgeCalculator.calculateAgeInMonths(birthDate, currentDate);
        latestEntryGroupKey = latestEntry.getGroupKey(currentConfig);
        // If we added the latest entry's month separator above, mark it as already handled
        if (latestEntryGroupKey != currentAgeInMonths) {
          currentGroupKey = latestEntryGroupKey;
          isFirstGroup = false;
        }
      }
    }

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final entryGroupKey = entry.getGroupKey(currentConfig);

      // Check if we need to insert group separator
      if (currentGroupKey != entryGroupKey) {
        currentGroupKey = entryGroupKey;
      }

      // Check if we need to insert conception label before this entry
      if (conceptionDate != null &&
          !hasInsertedConceptionLabel &&
          hasPregnancyEntries &&
          entry.date.isBefore(conceptionDate) &&
          (i == 0 || sortedEntries[i - 1].date.isAfter(conceptionDate))) {
        items.add(PregnancyLabel(config: currentConfig));
        hasInsertedConceptionLabel = true;
      }

      // Add the entry
      final isFirst = i == 0;
      final isLast = i == sortedEntries.length - 1 && hasPregnancyEntries;
      final isFirstInGroup = entryGroupKey !=
          (i > 0 ? sortedEntries[i - 1].getGroupKey(currentConfig) : null);
      final isLastInGroup = i == sortedEntries.length - 1 ||
          entryGroupKey != sortedEntries[i + 1].getGroupKey(currentConfig);

      items.add(TimelineItem(
        entry: entry,
        isFirst: isFirst,
        isLast: isLast,
        isFirstInGroup: isFirstInGroup,
        isLastInGroup: isLastInGroup && conceptionDate == null,
        config: currentConfig,
        webdavService: widget.cloudService,
        onEntryUpdated: _handleEntryUpdate,
        onConfigChanged: _handleConfigChanged,
        thumbnailCache: _thumbnailCache,
        thumbnailFutures: _thumbnailFutures,
      ));
      itemIndexMap[DateTime(entry.date.year, entry.date.month)] =
          items.length - 1;

      // Add group separator after the entry if it's the last in the group
      if (isLastInGroup) {
        bool isPregnancyPeriod = currentConfig.conceptionDate != null &&
            entry.date.isBefore(birthDate ?? DateTime.now());
        // For pregnancy period, only skip separator if this is the last pregnancy entry
        // and there are post-birth entries after it
        bool shouldSkipSeparator = false;
        if (isPregnancyPeriod && i < sortedEntries.length - 1) {
          // Check if there are post-birth entries after this pregnancy group
          bool hasPostBirthEntries = false;
          for (int j = i + 1; j < sortedEntries.length; j++) {
            if (sortedEntries[j].date.isAfter(birthDate ?? DateTime.now())) {
              hasPostBirthEntries = true;
              break;
            }
          }
          shouldSkipSeparator = hasPostBirthEntries;
        }

        if (!shouldSkipSeparator) {
          // Calculate display value to check if it's 0 (which we don't want to show)
          final groupValue = entry.getGroupKey(currentConfig);
          final displayValue = isPregnancyPeriod
              ? groupValue
              : (groupValue < 0 ? -groupValue + 1 : groupValue);

          // Skip separator for 0 month
          if (displayValue != 0) {
            bool isLastGroupOverall = i == sortedEntries.length - 1;
            items.add(GroupSeparator(
                representativeEntry: entry,
                isFirstGroup: isFirstGroup,
                isLastGroup: isLastGroupOverall,
                isPregnancyPeriod: isPregnancyPeriod,
                config: currentConfig));
            isFirstGroup = false;
          }
        }
      }

      // Check if we need to insert birth label after the last post-birth entry
      if (birthDate != null &&
          !hasInsertedBirthLabel &&
          hasPreBirthEntries &&
          lastPostBirthIndex != null &&
          i == lastPostBirthIndex) {
        items.add(BirthDateLabel(config: currentConfig, showBottomLine: true));
        hasInsertedBirthLabel = true;
      }
    }

    // Add special labels at the end if not inserted yet
    if (conceptionDate != null &&
        !hasInsertedConceptionLabel &&
        hasPregnancyEntries) {
      items.add(PregnancyLabel(config: currentConfig));
    }
    if (birthDate != null && !hasInsertedBirthLabel) {
      items.add(BirthDateLabel(config: currentConfig, showBottomLine: false));
    }

    // Add loading indicator if loading more
    if (_isLoadingMore) {
      items.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ));
    }

    // 如果有目标月份，滚动到对应位置
    if (_targetMonth != null) {
      final index = itemIndexMap[_targetMonth];
      if (index != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            index * 250.0 + 150.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
      _targetMonth = null; // 重置
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => items[index],
        childCount: items.length,
      ),
    );
  }

  Widget _buildTimelineDrawer() {
    final birthDate = currentConfig.childBirthDate;

    // 1. 收集所有时间轴点：月份和出生日期
    final Set<DateTime> timelinePoints = {};

    // 添加有日记的月份
    for (var entry in _entries) {
      timelinePoints.add(DateTime(entry.date.year, entry.date.month));
    }

    // 添加出生日期（如果有）
    if (birthDate != null) {
      timelinePoints.add(birthDate);
    }

    // 2. 转换为列表并排序 (从新到旧)
    final sortedPoints = timelinePoints.toList()
      ..sort((a, b) => b.compareTo(a));

    return Drawer(
      width: 200, // 窄一点的抽屉，类似时间轴条
      child: Column(
        children: [
          Container(
            height: MediaQuery.of(context).padding.top + 60,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.pink.shade400, Colors.pink.shade300],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  '时间轴',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sortedPoints.isEmpty
                ? const Center(child: Text('暂无记录'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    itemCount: sortedPoints.length + 1, // +1 for "今天"
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // 顶部 "今天" 节点
                        return _buildTimelineItem(
                          date: DateTime.now(),
                          birthDate: birthDate,
                          isToday: true,
                          isFirst: true,
                          isLast: sortedPoints.isEmpty,
                          config: currentConfig,
                        );
                      }

                      final date = sortedPoints[index - 1];
                      return _buildTimelineItem(
                        date: date,
                        birthDate: birthDate,
                        isToday: false,
                        isFirst: false,
                        isLast: index == sortedPoints.length,
                        config: currentConfig,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required DateTime date,
    required DateTime? birthDate,
    required bool isToday,
    required bool isFirst,
    required bool isLast,
    required AppConfig config,
  }) {
    String label;
    bool isBirthdayMonth = false;
    bool isBirthDay = false;
    Color color = Colors.black87;
    double fontSize = 14;
    bool isTodayBirthday = false;

    if (isToday) {
      label = "今天";
      color = Colors.pink.shade500;
      fontSize = 16;
      if (birthDate != null) {
        isTodayBirthday = DateTime.now().month == birthDate.month &&
            DateTime.now().day == birthDate.day &&
            DateTime.now().year != birthDate.year;
        label = isTodayBirthday ? "生日快乐！" : "今天";
      }
    } else if (birthDate != null) {
      if (date == birthDate) {
        label = "出生";
        isBirthDay = true;
        color = Colors.blue;
        fontSize = 16;
      } else if (date.day == 1) {
        // 月份项
        label = AgeCalculator.formatSimplifiedAgeLabel(date, config);
        // 检查是否是生日月份（所有周岁）
        isBirthdayMonth = date.month == birthDate.month &&
            date.year > birthDate.year &&
            date.day >= birthDate.day;
        if (isBirthdayMonth) {
          color = Colors.pink.shade500;
          fontSize = 16;
        }
      } else {
        // 其他日期（理论上不会发生）
        label = date.toString();
      }
    } else {
      if (date.day == 1) {
        label = "${date.year}年${date.month}月";
      } else {
        label = date.toString();
      }
    }

    return InkWell(
      onTap: () {
        _scrollToMonth(date);
        Navigator.pop(context); // Close drawer
      },
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 24), // Left padding
            // Timeline line and node
            SizedBox(
              width: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Node Icon
                  if (isToday)
                    Icon(
                        isTodayBirthday ? Icons.celebration : Icons.access_time,
                        size: 20,
                        color: Colors.pink.shade500)
                  else if (isBirthDay)
                    const Icon(Icons.child_care, size: 20, color: Colors.blue)
                  else if (isBirthdayMonth)
                    Icon(Icons.cake, size: 20, color: Colors.pink.shade500)
                  else
                    // Small dot for normal months
                    Container(
                      width: 1,
                      height: 50,
                      color: Colors.grey.shade300,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: isBirthdayMonth || isToday
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigDrawer() {
    return Drawer(
      child: Column(
        children: [
          // 抽屉头部
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                24, MediaQuery.of(context).padding.top + 32, 24, 32),
            decoration: BoxDecoration(
              image: _coverImageData != null
                  ? DecorationImage(
                      image: MemoryImage(_coverImageData!),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.3),
                        BlendMode.darken,
                      ),
                    )
                  : null,
              gradient: _coverImageData == null
                  ? LinearGradient(
                      colors: [Colors.pink.shade400, Colors.pink.shade200],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '成长日记',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    shadows: [
                      Shadow(
                        blurRadius: 4,
                        color: Colors.black26,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '记录每一天的惊喜',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            blurRadius: 2,
                            color: Colors.black26,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 配置列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              children: [
                Text(
                  '  我的宝宝',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                ...configs.values.map((config) {
                  final isSelected = currentConfigId == config.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.pink.shade50 : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? Colors.pink.shade100
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.child_care,
                          color: isSelected ? Colors.pink : Colors.grey,
                        ),
                      ),
                      title: Text(
                        config.babyName,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                          color:
                              isSelected ? Colors.pink.shade700 : Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        config.getAgeLabel(),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.pink.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      trailing: isSelected
                          ? const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.pink,
                              child: Icon(Icons.check,
                                  size: 16, color: Colors.white),
                            )
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () {
                        setState(() {
                          currentConfigId = config.id;
                          currentConfig = config;
                          widget.localStorage.setCurrentConfigId(config.id);
                        });
                        Navigator.of(context).pop(); // 关闭抽屉
                        _switchConfig(); // 切换配置
                      },
                    ),
                  );
                }),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(),
                ),

                // 添加宝宝选项
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade100,
                    child: const Icon(
                      Icons.add,
                      color: Colors.black87,
                    ),
                  ),
                  title: const Text(
                    '添加宝宝',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(); // 关闭抽屉
                    _showAddBabyDialog();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<AppConfig?> _scanQRCodeForBaby() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(),
      ),
    );

    if (!mounted) return null;

    if (result != null && result is String) {
      // 尝试解码二维码数据
      final importedConfig = QRService.decodeEncryptedQRData(result);

      if (importedConfig != null) {
        // 显示确认对话框
        final shouldImport = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认导入配置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('宝宝昵称: ${importedConfig.babyName}'),
                Text(
                    '出生日期: ${importedConfig.babyBirthDate?.toString().split(' ')[0] ?? '未设置'}'),
                Text(
                    '受孕日期: ${importedConfig.babyConceptionDate?.toString().split(' ')[0] ?? '未设置'}'),
                const SizedBox(height: 10),
                const Text(
                  '导入后将使用此宝宝信息，确定继续吗？',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('导入'),
              ),
            ],
          ),
        );

        if (shouldImport == true) {
          return importedConfig;
        }
      } else {
        // 无效的二维码
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无效的二维码数据')),
          );
        }
      }
    }
    return null;
  }

  Future<void> _showAddBabyDialog() async {
    String babyName = '';
    DateTime? birthDate;
    DateTime? conceptionDate;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加宝宝'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 扫码导入按钮
                OutlinedButton.icon(
                  onPressed: () async {
                    final importedConfig = await _scanQRCodeForBaby();
                    if (importedConfig != null && mounted) {
                      // 直接创建新配置并跳转，不填充表单
                      final newConfig = AppConfig(
                        id: importedConfig.id,
                        webdavUrl: importedConfig.webdavUrl,
                        username: importedConfig.username,
                        password: importedConfig.password,
                        babyName: importedConfig.babyName,
                        babyBirthDate: importedConfig.babyBirthDate,
                        babyConceptionDate: importedConfig.babyConceptionDate,
                      );

                      // 添加到配置列表
                      setState(() {
                        configs[newConfig.id] = newConfig;
                        currentConfigId = newConfig.id;
                        currentConfig = newConfig;
                      });

                      // 保存配置
                      await widget.localStorage.saveAllConfigs(configs);
                      await widget.localStorage
                          .setCurrentConfigId(newConfig.id);

                      // 关闭对话框并切换到新宝宝
                      // ignore: use_build_context_synchronously
                      Navigator.of(context).pop();
                      Future.delayed(Duration.zero, () => _switchConfig());
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫码导入配置'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.pink,
                    side: const BorderSide(color: Colors.pink),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '或手动输入',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '宝宝姓名',
                    hintText: '请输入宝宝姓名',
                  ),
                  controller: TextEditingController(text: babyName),
                  onChanged: (value) => babyName = value,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('出生日期'),
                  subtitle: Text(
                    birthDate != null
                        ? '${birthDate!.year}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}'
                        : '未设置',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => birthDate = picked);
                    }
                  },
                ),
                ListTile(
                  title: const Text('受孕日期'),
                  subtitle: Text(
                    conceptionDate != null
                        ? '${conceptionDate!.year}-${conceptionDate!.month.toString().padLeft(2, '0')}-${conceptionDate!.day.toString().padLeft(2, '0')}'
                        : '未设置',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          birthDate?.subtract(const Duration(days: 280)) ??
                              DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => conceptionDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: babyName.trim().isNotEmpty
                  ? () => Navigator.of(context).pop({
                        'name': babyName.trim(),
                        'birthDate': birthDate,
                        'conceptionDate': conceptionDate,
                      })
                  : null,
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      // 创建新配置，复制当前配置的WebDAV设置
      final newConfig = AppConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        webdavUrl: currentConfig.webdavUrl,
        username: currentConfig.username,
        password: currentConfig.password,
        babyName: result['name'],
        babyBirthDate: result['birthDate'],
        babyConceptionDate: result['conceptionDate'],
      );

      // 添加到配置列表
      setState(() {
        configs[newConfig.id] = newConfig;
        currentConfigId = newConfig.id;
        currentConfig = newConfig;
      });

      // 保存配置
      await widget.localStorage.saveAllConfigs(configs);
      await widget.localStorage.setCurrentConfigId(newConfig.id);

      // 直接切换到新宝宝，不导航到设置页面
      _switchConfig();
    }
  }

  /// 重新加载最新的配置（包括生日、受孕日等）
  Future<void> _reloadLatestConfig() async {
    try {
      debugPrint('Reloading latest config from WebDAV...');

      // 从WebDAV加载最新的配置
      final webdavConfig = await widget.cloudService.loadConfig();

      if (webdavConfig != null) {
        debugPrint(
            'Loaded updated config from WebDAV: ${webdavConfig.babyName}, birthDate: ${webdavConfig.babyBirthDate}, conceptionDate: ${webdavConfig.babyConceptionDate}');

        // 更新本地配置
        setState(() {
          configs[currentConfigId] = webdavConfig;
          currentConfig = webdavConfig;
        });

        // 保存到本地存储
        await widget.localStorage.saveAllConfigs(configs);

        debugPrint('Config reloaded successfully');
      } else {
        debugPrint('No updated config found on WebDAV');
      }
    } catch (e) {
      debugPrint('Error reloading config: $e');
      // 不显示错误给用户，因为这不是关键功能
    }
  }

  Future<void> _loadCoverImage({bool forceRefresh = false}) async {
    final coverImagePath = currentConfig.babyCoverImagePath;
    if (coverImagePath == null || coverImagePath.isEmpty) {
      setState(() {
        _coverImageData = null;
        _isLoadingCoverImage = false;
      });
      return;
    }

    if (_coverImageData != null && !forceRefresh) return; // 已经加载过了，除非强制刷新

    setState(() {
      _isLoadingCoverImage = true;
    });

    try {
      final data = await widget.cloudService.downloadFile(coverImagePath);
      if (mounted) {
        setState(() {
          _coverImageData = data;
          _isLoadingCoverImage = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading cover image: $e');
      if (mounted) {
        setState(() {
          _isLoadingCoverImage = false;
        });
      }
    }
  }
}
