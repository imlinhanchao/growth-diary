import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import '../models/diary_entry.dart';
import '../services/cloud_storage_service.dart';
import '../services/diary_repository.dart';
import '../services/local_diary_cache.dart';
import '../services/media_upload_service.dart';
import '../services/entry_creation_service.dart';
import '../utils/age_calculator.dart';
import '../utils/file_utils.dart' as file_utils;
import '../utils/device_type.dart';
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
import 'entry_detail_screen.dart';
import 'qr_scanner_screen.dart';
import '../components/full_screen_image_view.dart';
import '../components/full_screen_video_player.dart';
import 'tv_slideshow_screen.dart';
import 'setup_screen.dart';

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
  int _entriesRevision = 0;
  // 时间轴 widget 缓存：条目/配置/选中项没变时不再重建上千个 TimelineItem
  List<Widget>? _timelineCacheItems;
  Map<DateTime, int>? _timelineCacheIndex;
  int _timelineCacheKey = 0;
  bool _timelineCacheValid = false;
  List<TvMediaItem>? _tvMediaCache;
  int _tvMediaCacheRevision = -1;
  int _tvMediaCacheFilter = -1;
  // TV 网格懒构建：只存每个条目的媒体数前缀和，按需构造 TvMediaItem
  List<int>? _tvPrefixCounts;
  int _tvTotalMediaCount = 0;
  int _tvPrefixRevision = -1;
  int _tvPrefixFilter = -1;
  DiaryRepository? _repository;
  bool _offlineHintShown = false;
  bool _isLoading = true;
  final bool _isLoadingMore = false;
  String? _errorMessage;
  final Map<String, Uint8List?> _thumbnailCache = {};
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  Uint8List? _coverImageData;
  bool _isLoadingCoverImage = false;
  bool _isExpanded = false;
  final ValueNotifier<UploadProgressData> _uploadProgressNotifier =
      ValueNotifier(UploadProgressData(false, ''));
  int _tvFilterIndex = 0; // 0: 全部, 1: 照片, 2: 视频

  late Map<String, AppConfig> configs;
  late String currentConfigId;
  late AppConfig currentConfig;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _tvScrollController = ScrollController();
  DateTime? _targetMonth;

  /// 宽屏双栏模式下当前选中的条目（右侧详情面板显示）
  DiaryEntry? _selectedEntry;

  late EntryCreationService _entryCreationService;
  static const MethodChannel _deviceChannel = MethodChannel('com.growth_diary/device');
  bool _isOpeningSettings = false;

  void _openSettings() async {
    if (!mounted || _isOpeningSettings) return;
    _isOpeningSettings = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SettingsScreen(
            config: currentConfig,
            cloudService: widget.cloudService,
            onConfigChanged: (newConfig) async {
              final updatedConfigs = await widget.localStorage.loadAllConfigs();
              final currentId = await widget.localStorage.getCurrentConfigId();
              setState(() {
                configs = updatedConfigs;
                currentConfigId = currentId ?? '';
                currentConfig = configs[currentConfigId] ?? configs.values.first;
              });
              await _handleConfigChanged(newConfig);
            },
          ),
        ),
      );
    } finally {
      _isOpeningSettings = false;
    }
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.settings ||
          event.logicalKey == LogicalKeyboardKey.contextMenu ||
          event.logicalKey.keyId == 176 ||
          event.logicalKey.keyId == 82 ||
          event.logicalKey.keyLabel.toLowerCase() == 'settings') {
        _openSettings();
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    configs = Map.from(widget.configs);
    currentConfigId = widget.currentConfigId;
    currentConfig = configs[currentConfigId]!;
    _scrollController.addListener(_onScroll);
    _tvScrollController.addListener(_onTvScroll);
    WidgetsBinding.instance.addObserver(this);

    _deviceChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') {
        _openSettings();
      }
    });
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);

    // 初始化WebDAV服务，为当前宝宝创建文件夹
    widget.cloudService.initialize(currentConfig).then((_) {
      debugPrint('WebDAV service initialized');
    }).catchError((e) {
      debugPrint('Error initializing WebDAV service: $e');
    });

    // 冲突副本：保存时被判定为并发的编辑，提示用户并刷新列表
    widget.cloudService.conflictListener = (conflict) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('检测到另一端的修改，已保留为「冲突副本」：${conflict.title}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '查看',
          onPressed: () => _loadEntries(forceSync: true),
        ),
      ));
      unawaited(_loadEntries(forceSync: true));
    };

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
    uploadService.setProgressCallback((task, progress) {
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
    widget.cloudService.conflictListener = null;
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _deviceChannel.setMethodCallHandler(null);
    _scrollController.dispose();
    _tvScrollController.removeListener(_onTvScroll);
    _tvScrollController.dispose();
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

  Future<DiaryRepository?> _ensureRepository() async {
    final existing = _repository;
    if (existing != null) return existing;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final baseDir =
          Directory('${docs.path}/growth_diary_cache/${currentConfig.id}');
      final repo = DiaryRepository(
        configId: currentConfig.id,
        cloud: widget.cloudService,
        cache: LocalDiaryCache(baseDir: baseDir),
      );
      _repository = repo;
      return repo;
    } catch (e) {
      debugPrint('初始化本地缓存失败: $e');
      return null;
    }
  }

  /// 本地优先加载：先渲染缓存，再后台对账。
  Future<void> _loadEntries({bool forceSync = false}) async {
    final total = Stopwatch()..start();
    final repo = await _ensureRepository();
    if (repo == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '本地缓存目录不可用';
      });
      return;
    }

    setState(() => _errorMessage = null);

    // 2a. 先读索引（单个小文件），只解析首屏需要的一页正文，尽快出第一帧
    final indexWatch = Stopwatch()..start();
    final metas = await repo.loadIndexMetas();
    indexWatch.stop();

    const firstPageSize = 12;
    var firstPage = <DiaryEntry>[];
    if (metas.isNotEmpty) {
      final pageWatch = Stopwatch()..start();
      firstPage = await repo.loadEntries(metas.take(firstPageSize).map((m) => m.id));
      pageWatch.stop();
      if (!mounted) return;
      setState(() {
        _entries = firstPage;
        _entriesRevision++;
        _isLoading = false;
      });
      debugPrint('[perf] first paint: ${total.elapsedMilliseconds}ms '
          '(索引 ${indexWatch.elapsedMilliseconds}ms, '
          '首屏 ${firstPage.length} 条 ${pageWatch.elapsedMilliseconds}ms)');
      _loadCoverImage();
      // 首屏缩略图提前排队下载（队列限流 4 路，不阻塞渲染）
      unawaited(_prefetchThumbnails(firstPage));
    } else {
      setState(() => _isLoading = true);
    }

    // 2b. 背景补齐剩余条目：纯本地读取，不发请求
    if (metas.length > firstPageSize) {
      final restWatch = Stopwatch()..start();
      final rest = await repo.loadEntries(
          metas.skip(firstPageSize).map((m) => m.id));
      restWatch.stop();
      if (!mounted) return;
      setState(() {
        _entries = [...firstPage, ...rest];
        _entriesRevision++;
      });
      debugPrint('[perf] rest loaded: ${rest.length} 条 in '
          '${restWatch.elapsedMilliseconds}ms');
    }

    // 3. 后台对账：1 次 PROPFIND + 变更条目
    final report = await repo.sync(force: forceSync);
    if (!mounted) return;
    debugPrint('[perf] sync done: $report');

    if (report.error != null) {
      setState(() {
        _isLoading = false;
        if (_entries.isEmpty) {
          _errorMessage = report.error.toString();
        }
      });
      if (_entries.isNotEmpty) _showOfflineHint();
      return;
    }

    _offlineHintShown = false;
    if (report.hasChanges || _entries.isEmpty) {
      final all = await repo.loadCached();
      if (!mounted) return;
      setState(() {
        _entries = all;
        _entriesRevision++;
        _isLoading = false;
      });
      _loadCoverImage(forceRefresh: true);
    } else {
      setState(() => _isLoading = false);
    }
    debugPrint('[perf] entries ready: ${_entries.length} 条');
  }

  /// 提前把首屏可见条目的缩略图排进下载队列。
  /// 下载本身受 WebDAVService 的 4 路并发限制，这里只负责发起，不 await。
  Future<void> _prefetchThumbnails(Iterable<DiaryEntry> entries) async {
    const maxEntries = 6;
    const maxFiles = 24;
    final paths = <String>[];
    for (final entry in entries.take(maxEntries)) {
      paths.addAll(entry.imageThumbnails);
      paths.addAll(entry.videoThumbnails);
      if (paths.length >= maxFiles) break;
    }
    final unique = paths.toSet().take(maxFiles).toList();
    if (unique.isEmpty) return;
    for (final path in unique) {
      unawaited(widget.cloudService.downloadFile(path));
    }
    debugPrint('[perf] 预取缩略图 ${unique.length} 张');
  }

  void _showOfflineHint() {
    if (_offlineHintShown) return;
    _offlineHintShown = true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('离线模式：显示本地缓存，数据可能不是最新'),
      duration: Duration(seconds: 4),
    ));
  }

  Future<void> _onRefresh() async {
    // 先获取最新的配置
    await _reloadLatestConfig();

    // 重新加载条目（下拉刷新强制对账）
    await _loadEntries(forceSync: true);

    // 强制重新加载封面图（忽略缓存）
    await _loadCoverImage(forceRefresh: true);
  }

  Future<void> _handleEntryUpdate(
      EntryDetailResult result, DiaryEntry originalEntry) async {
    if (result.isDeleted) {
      // 删除条目
      setState(() {
        _entries.removeWhere((entry) => entry.id == originalEntry.id);
        _entriesRevision++;
      });
      await _repository?.forgetEntry(originalEntry.id);
    } else if (result.updatedEntry != null) {
      // 更新条目
      setState(() {
        final index =
            _entries.indexWhere((entry) => entry.id == originalEntry.id);
        if (index != -1) {
          _entries[index] = result.updatedEntry!;
          _entriesRevision++;
        }
      });
      await _repository?.cacheEntry(result.updatedEntry!);
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
      _entriesRevision++;
      _thumbnailCache.clear();
      _thumbnailFutures.clear();
      _coverImageData = null; // 清除封面图缓存
      _isLoadingCoverImage = false; // 重置加载状态
      _isLoading = true;
      _repository = null; // 换宝宝后缓存目录也跟着换
      _offlineHintShown = false;
    });

    // 重新加载数据
    _loadEntries();
  }

  Future<void> _loadMoreEntries() async {
    // Phase 1：条目已全部从本地索引加载，滚动不再触发网络请求。
    // 列表按需构建，这里保持空实现以兼容现有滚动回调。
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreEntries();
    }
  }

  void _onTvScroll() {
    if (_tvScrollController.hasClients &&
        _tvScrollController.position.pixels >=
            _tvScrollController.position.maxScrollExtent - 400) {
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
      _updateUploadProgress();

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
      _updateUploadProgress();

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
    String progressText = '';
    if (hasActiveTasks) {
      final completed = MediaUploadService.getCompletedTasks();
      final total = MediaUploadService.getTotalTasks();
      final currentProgress = MediaUploadService.getCurrentTaskProgress();
      if (currentProgress > 0 && currentProgress < 1.0) {
        progressText = '$completed/$total · ${(currentProgress * 100).toInt()}%';
      } else {
        progressText = '$completed/$total';
      }
    }

    _uploadProgressNotifier.value = UploadProgressData(
        hasActiveTasks, progressText,
        isRestoring: isRestoring);
  }

  Widget _buildSliverAppBar() {
    final bool showExpanded = _coverImageData != null || _isLoadingCoverImage;
    // 宽屏（平板/TV）左栏宽度有限，封面图展开没有意义；且只读模式无需上传进度
    final bool isWide = DeviceType.isWideScreen(context);

    return SliverAppBar(
      // 宽屏不展开封面图（左栏太窄，背景图视觉效果差）
      expandedHeight: (!isWide && showExpanded) ? 260.0 : null,
      pinned: true,
      stretch: !isWide,
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
              // 宽屏只读模式不显示上传进度
              if (!isWide && progressData.hasActiveTasks) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 00.2),
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
            focusColor: Colors.white.withValues(alpha: 0.35),
            tooltip: '日历',
            onPressed: () {
              Scaffold.of(context).openEndDrawer();
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          color: Colors.white,
          focusColor: Colors.white.withValues(alpha: 0.35),
          tooltip: '设置',
          onPressed: _openSettings,
        ),
      ],
      // 宽屏不展示可伸缩背景
      flexibleSpace: isWide
          ? null
          : FlexibleSpaceBar(
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
                            Colors.black.withValues(alpha: 00.5),
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
    if (DeviceType.isTV(context)) {
      return _buildTvLayout(context);
    }
    final isWide = DeviceType.isWideScreen(context);
    if (isWide) {
      return _buildWideLayout(context);
    }
    return _buildPhoneLayout(context);
  }

  // ──────────────────────────────────────────
  // 宽屏（平板 / TV）双栏布局
  // ──────────────────────────────────────────
  Widget _buildWideLayout(BuildContext context) {
    final leftWidth = DeviceType.timelineColumnWidth(context);
    // 外层仅作布局容器，drawer 在内层 _buildTimelineColumn 的 Scaffold 里
    return Scaffold(
      body: Row(
        children: [
          // ── 左栏：时间轴列表 ──
          SizedBox(
            width: leftWidth,
            child: _buildTimelineColumn(),
          ),
          // 分隔线
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Colors.grey.shade200,
          ),
          // ── 右栏：详情面板 ──
          Expanded(
            child: _selectedEntry != null
                ? EntryDetailScreen(
                    key: ValueKey(_selectedEntry!.id),
                    entry: _selectedEntry!,
                    config: currentConfig,
                    cloudService: widget.cloudService,
                    // 宽屏只读：不传入编辑/删除回调
                    onEntryUpdated: null,
                    onConfigChanged: null,
                    isEmbedded: true,
                  )
                : _buildDetailPlaceholder(),
          ),
        ],
      ),
    );
  }

  /// 宽屏右侧占位页面（未选中任何条目时显示）
  Widget _buildDetailPlaceholder() {
    return Container(
      color: Colors.grey.shade50,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 72, color: Colors.pink.shade100),
            const SizedBox(height: 16),
            Text(
              '选择一条记录查看详情',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 左侧时间轴列（宽屏模式）
  Widget _buildTimelineColumn() {
    // 宽屏模式下，drawer 由外层 _buildWideLayout 的 Scaffold 管理
    // 这里只做时间轴内容区域
    return Stack(
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
      ],
    );
  }

  // ──────────────────────────────────────────
  // 手机单栏布局（原有逻辑）
  // ──────────────────────────────────────────
  Widget _buildPhoneLayout(BuildContext context) {
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
          if (!DeviceType.isTV(context))
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
                                color: Colors.black.withValues(alpha: 00.1),
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
                                color: Colors.black.withValues(alpha: 00.1),
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
                                color: Colors.black.withValues(alpha: 00.1),
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

    final isWide = DeviceType.isWideScreen(context);
    final cacheKey = Object.hash(
      _entriesRevision,
      _selectedEntry?.id,
      isWide,
      currentConfig.id,
      currentConfig.babyName,
      currentConfig.babyBirthDate?.millisecondsSinceEpoch,
      currentConfig.babyConceptionDate?.millisecondsSinceEpoch,
    );
    final cachedItems = _timelineCacheItems;
    final cachedIndex = _timelineCacheIndex;
    if (_timelineCacheValid &&
        _timelineCacheKey == cacheKey &&
        cachedItems != null &&
        cachedIndex != null) {
      _scheduleScrollToTargetMonth(cachedIndex);
      return _buildTimelineSliverFrom(cachedItems, isWide);
    }

    final buildWatch = Stopwatch()..start();
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
        // 宽屏模式：点击条目更新右侧详情面板，不 push 新路由
        onTapOverride: DeviceType.isWideScreen(context)
            ? (e) => setState(() => _selectedEntry = e)
            : null,
        selectedInWideMode: DeviceType.isWideScreen(context) &&
            _selectedEntry?.id == entry.id,
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

    buildWatch.stop();
    _timelineCacheItems = items;
    _timelineCacheIndex = itemIndexMap;
    _timelineCacheKey = cacheKey;
    _timelineCacheValid = true;
    if (buildWatch.elapsedMilliseconds >= 4) {
      debugPrint('[perf] timeline rebuilt in '
          '${buildWatch.elapsedMilliseconds}ms (${items.length} 项)');
    }

    _scheduleScrollToTargetMonth(itemIndexMap);
    return _buildTimelineSliverFrom(items, isWide);
  }

  Widget _buildTimelineSliverFrom(List<Widget> items, bool isWide) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 12 : 8,
        vertical: 8,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
        ),
      ),
    );
  }

  void _scheduleScrollToTargetMonth(Map<DateTime, int> itemIndexMap) {
    final target = _targetMonth;
    if (target == null) return;
    final index = itemIndexMap[target];
    if (index != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          index * 250.0 + 150.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
    _targetMonth = null;
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
                        Colors.black.withValues(alpha: 00.3),
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
                  color: Colors.black.withValues(alpha: 00.1),
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
                    color: Colors.white.withValues(alpha: 00.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 00.4),
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
                      color: Colors.white.withValues(alpha: 00.9),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '记录每一天的惊喜',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 00.95),
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
        builder: (context) => QRScannerScreen(currentConfig: currentConfig),
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
                        babyCoverImagePath: importedConfig.babyCoverImagePath,
                        videoCompressionThreshold:
                            importedConfig.videoCompressionThreshold,
                        webdavMirrors: importedConfig.webdavMirrors,
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
        videoCompressionThreshold: currentConfig.videoCompressionThreshold,
        webdavMirrors: currentConfig.webdavMirrors,
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

  // ──────────────────────────────────────────
  // 电视（Android TV）全屏画廊模式
  // ──────────────────────────────────────────

  List<TvMediaItem> _getTvMediaItems() {
    // TV 布局每次 build 都会调用这里，2000 条时全量展开很贵：
    // 按"条目修订号 + 过滤条件"缓存，列表变化时才重算。
    final cached = _tvMediaCache;
    if (cached != null &&
        _tvMediaCacheRevision == _entriesRevision &&
        _tvMediaCacheFilter == _tvFilterIndex) {
      return cached;
    }
    final List<TvMediaItem> items = [];
    for (final entry in _entries) {
      if (_tvFilterIndex == 0 || _tvFilterIndex == 1) {
        for (int i = 0; i < entry.imagePaths.length; i++) {
          final thumb = i < entry.imageThumbnails.length
              ? entry.imageThumbnails[i]
              : entry.imagePaths[i];
          items.add(TvMediaItem(
            type: TvMediaType.photo,
            mediaPath: entry.imagePaths[i],
            thumbnailPath: thumb,
            entry: entry,
            indexInEntry: i,
          ));
        }
      }
      if (_tvFilterIndex == 0 || _tvFilterIndex == 2) {
        for (int i = 0; i < entry.videoPaths.length; i++) {
          final thumb = i < entry.videoThumbnails.length
              ? entry.videoThumbnails[i]
              : '';
          items.add(TvMediaItem(
            type: TvMediaType.video,
            mediaPath: entry.videoPaths[i],
            thumbnailPath: thumb,
            entry: entry,
            indexInEntry: i,
          ));
        }
      }
    }
    _tvMediaCache = items;
    _tvMediaCacheRevision = _entriesRevision;
    _tvMediaCacheFilter = _tvFilterIndex;
    return items;
  }

  int _tvMediaCountForEntry(DiaryEntry entry) {
    if (_tvFilterIndex == 1) return entry.imagePaths.length;
    if (_tvFilterIndex == 2) return entry.videoPaths.length;
    return entry.imagePaths.length + entry.videoPaths.length;
  }

  void _ensureTvPrefix() {
    if (_tvPrefixCounts != null &&
        _tvPrefixRevision == _entriesRevision &&
        _tvPrefixFilter == _tvFilterIndex) {
      return;
    }
    final counts = <int>[];
    var total = 0;
    for (final entry in _entries) {
      total += _tvMediaCountForEntry(entry);
      counts.add(total);
    }
    _tvPrefixCounts = counts;
    _tvTotalMediaCount = total;
    _tvPrefixRevision = _entriesRevision;
    _tvPrefixFilter = _tvFilterIndex;
  }

  /// 把扁平下标映射回 (条目, 条目内序号)，用前缀和 + 二分，避免构造整张列表。
  TvMediaItem? _tvItemAt(int flatIndex) {
    final prefix = _tvPrefixCounts;
    if (prefix == null || flatIndex < 0 || flatIndex >= _tvTotalMediaCount) {
      return null;
    }
    var lo = 0;
    var hi = prefix.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (prefix[mid] > flatIndex) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final entry = _entries[lo];
    final before = lo == 0 ? 0 : prefix[lo - 1];
    final inEntry = flatIndex - before;
    return _tvItemInEntry(entry, inEntry);
  }

  TvMediaItem? _tvItemInEntry(DiaryEntry entry, int inEntry) {
    final imageCount = entry.imagePaths.length;
    if (_tvFilterIndex == 1) {
      if (inEntry >= imageCount) return null;
      return TvMediaItem(
        type: TvMediaType.photo,
        mediaPath: entry.imagePaths[inEntry],
        thumbnailPath: inEntry < entry.imageThumbnails.length
            ? entry.imageThumbnails[inEntry]
            : entry.imagePaths[inEntry],
        entry: entry,
        indexInEntry: inEntry,
      );
    }
    if (_tvFilterIndex == 2) {
      if (inEntry >= entry.videoPaths.length) return null;
      return TvMediaItem(
        type: TvMediaType.video,
        mediaPath: entry.videoPaths[inEntry],
        thumbnailPath: inEntry < entry.videoThumbnails.length
            ? entry.videoThumbnails[inEntry]
            : '',
        entry: entry,
        indexInEntry: inEntry,
      );
    }
    if (inEntry < imageCount) {
      return TvMediaItem(
        type: TvMediaType.photo,
        mediaPath: entry.imagePaths[inEntry],
        thumbnailPath: inEntry < entry.imageThumbnails.length
            ? entry.imageThumbnails[inEntry]
            : entry.imagePaths[inEntry],
        entry: entry,
        indexInEntry: inEntry,
      );
    }
    final videoIndex = inEntry - imageCount;
    if (videoIndex >= entry.videoPaths.length) return null;
    return TvMediaItem(
      type: TvMediaType.video,
      mediaPath: entry.videoPaths[videoIndex],
      thumbnailPath: videoIndex < entry.videoThumbnails.length
          ? entry.videoThumbnails[videoIndex]
          : '',
      entry: entry,
      indexInEntry: videoIndex,
    );
  }

  Future<Uint8List?> _getTvThumbnailData(String path) async {
    if (path.isEmpty) return null;
    if (_thumbnailCache.containsKey(path)) {
      return _thumbnailCache[path];
    }
    if (_thumbnailFutures.containsKey(path)) {
      return _thumbnailFutures[path];
    }
    final future = _loadTvThumbnailData(path);
    _thumbnailFutures[path] = future;
    try {
      final data = await future;
      _thumbnailCache[path] = data;
      return data;
    } finally {
      _thumbnailFutures.remove(path);
    }
  }

  Future<Uint8List?> _loadTvThumbnailData(String path) async {
    try {
      final data = await widget.cloudService.downloadFile(path);
      return data;
    } catch (e) {
      debugPrint('Error loading TV thumbnail $path: $e');
      return null;
    }
  }

  void _onTvMediaClicked(TvMediaItem item) {
    final allItems = _getTvMediaItems();
    if (item.type == TvMediaType.photo) {
      final photoItems =
          allItems.where((m) => m.type == TvMediaType.photo).toList();
      final photoPaths = photoItems.map((m) => m.mediaPath).toList();
      final initialIndex =
          photoItems.indexWhere((m) => m.mediaPath == item.mediaPath);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenImageView(
            imagePaths: photoPaths,
            webdavService: widget.cloudService,
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
            onSetAsCoverImage: (path) async {
              currentConfig.babyCoverImagePath = path;
              await _handleConfigChanged(currentConfig);
            },
          ),
        ),
      );
    } else {
      final videoItems =
          allItems.where((m) => m.type == TvMediaType.video).toList();
      final videoPaths = videoItems.map((m) => m.mediaPath).toList();
      final initialIndex =
          videoItems.indexWhere((m) => m.mediaPath == item.mediaPath);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenVideoPlayer(
            videoPaths: videoPaths,
            webdavService: widget.cloudService,
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
          ),
        ),
      );
    }
  }

  void _startTvSlideshow() {
    final photoPaths = <String>[];
    for (final entry in _entries) {
      photoPaths.addAll(entry.imagePaths);
    }
    if (photoPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可播放的照片')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TvSlideshowScreen(
          imagePaths: photoPaths,
          cloudService: widget.cloudService,
          config: currentConfig,
          entries: _entries,
        ),
      ),
    );
  }

  void _scrollToTvMonth(DateTime month) {
    if (!_tvScrollController.hasClients) return;
    final mediaItems = _getTvMediaItems();
    if (mediaItems.isEmpty) return;

    int targetIndex = mediaItems.indexWhere((it) =>
        it.entry.date.year == month.year && it.entry.date.month == month.month);

    if (targetIndex == -1) {
      targetIndex = mediaItems.indexWhere((it) =>
          it.entry.date.isBefore(DateTime(month.year, month.month + 1)));
    }

    if (targetIndex != -1) {
      final rowIndex = targetIndex ~/ 4;
      final screenWidth = MediaQuery.of(context).size.width;
      const gridPadding = 28.0 * 2;
      const crossSpacing = 18.0 * 3;
      final itemWidth = (screenWidth - gridPadding - crossSpacing) / 4;
      final itemHeight = itemWidth / 1.25;
      final rowHeight = itemHeight + 18.0;
      final targetOffset = rowIndex * rowHeight;

      _tvScrollController.animateTo(
        targetOffset.clamp(0.0, _tvScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _showTvTimelineDialog() {
    final birthDate = currentConfig.childBirthDate;
    final Map<DateTime, int> monthCounts = {};
    for (final e in _entries) {
      final m = DateTime(e.date.year, e.date.month);
      monthCounts[m] =
          (monthCounts[m] ?? 0) + e.imagePaths.length + e.videoPaths.length;
    }

    final sortedMonths = monthCounts.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _TvTimelineDialog(
          months: sortedMonths,
          monthCounts: monthCounts,
          birthDate: birthDate,
          config: currentConfig,
          onSelectMonth: (selectedMonth) {
            Navigator.of(dialogContext).pop();
            _scrollToTvMonth(selectedMonth);
          },
        );
      },
    );
  }

  void _showTvBabySwitcherDialog() {
    final allConfigs = configs.values.toList();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return _TvBabySwitcherDialog(
          configs: allConfigs,
          currentConfigId: currentConfigId,
          onSelect: (selectedConfig) {
            Navigator.of(dialogContext).pop();
            if (selectedConfig.id != currentConfigId) {
              setState(() {
                currentConfigId = selectedConfig.id;
                currentConfig = selectedConfig;
                widget.localStorage.setCurrentConfigId(selectedConfig.id);
              });
              _switchConfig();
            }
          },
          onAddNewBaby: () async {
            Navigator.of(dialogContext).pop();
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SetupScreen()),
            );
            final updatedConfigs = await widget.localStorage.loadAllConfigs();
            final currentId = await widget.localStorage.getCurrentConfigId();
            if (mounted &&
                currentId != null &&
                updatedConfigs.containsKey(currentId)) {
              setState(() {
                configs = updatedConfigs;
                currentConfigId = currentId;
                currentConfig = configs[currentConfigId]!;
              });
              _switchConfig();
            }
          },
        );
      },
    );
  }

  Widget _buildTvLayout(BuildContext context) {
    _ensureTvPrefix();
    final totalPhotos =
        _entries.fold<int>(0, (sum, e) => sum + e.imagePaths.length);
    final totalVideos =
        _entries.fold<int>(0, (sum, e) => sum + e.videoPaths.length);
    final totalAll = totalPhotos + totalVideos;

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      body: SafeArea(
        child: Column(
          children: [
            _buildTvHeader(
              totalAll: totalAll,
              totalPhotos: totalPhotos,
              totalVideos: totalVideos,
            ),
            Expanded(
              child: _isLoading
                  ? _buildTvLoadingState()
                  : _errorMessage != null
                      ? _buildTvErrorState()
                      : _tvTotalMediaCount == 0
                          ? _buildTvEmptyState()
                          : _buildTvMediaGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvHeader({
    required int totalAll,
    required int totalPhotos,
    required int totalVideos,
  }) {
    final babyName = currentConfig.childName.isNotEmpty
        ? currentConfig.childName
        : '宝宝成长相册';
    final ageText = currentConfig.childBirthDate != null
        ? AgeCalculator.formatAgeLabel(
            AgeCalculator.calculateAgeInMonths(
                currentConfig.childBirthDate!, DateTime.now()))
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _TvBabyProfileButton(
            name: babyName,
            ageText: ageText,
            coverImage: _coverImageData,
            onTap: _showTvBabySwitcherDialog,
          ),
          const SizedBox(width: 20),
          _TvFilterTab(
            label: '全部',
            icon: Icons.grid_view_rounded,
            count: totalAll,
            isSelected: _tvFilterIndex == 0,
            onTap: () => setState(() => _tvFilterIndex = 0),
          ),
          const SizedBox(width: 8),
          _TvFilterTab(
            label: '照片',
            icon: Icons.photo_library_rounded,
            count: totalPhotos,
            isSelected: _tvFilterIndex == 1,
            onTap: () => setState(() => _tvFilterIndex = 1),
          ),
          const SizedBox(width: 8),
          _TvFilterTab(
            label: '视频',
            icon: Icons.videocam_rounded,
            count: totalVideos,
            isSelected: _tvFilterIndex == 2,
            onTap: () => setState(() => _tvFilterIndex = 2),
          ),
          const Spacer(),
          _TvFocusableButton(
            icon: Icons.calendar_month_rounded,
            label: '时间轴',
            showLabelOnlyOnFocus: true,
            onTap: _showTvTimelineDialog,
          ),
          const SizedBox(width: 8),
          _TvFocusableButton(
            icon: Icons.slideshow_rounded,
            label: '幻灯片',
            isPrimary: true,
            onTap: _startTvSlideshow,
          ),
          const SizedBox(width: 8),
          _TvFocusableButton(
            icon: Icons.refresh_rounded,
            label: '刷新',
            showLabelOnlyOnFocus: true,
            onTap: _onRefresh,
          ),
          const SizedBox(width: 8),
          _TvFocusableButton(
            icon: Icons.settings_rounded,
            label: '设置',
            showLabelOnlyOnFocus: true,
            onTap: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildTvMediaGrid() {
    return GridView.builder(
      controller: _tvScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
        childAspectRatio: 1.25,
      ),
      itemCount: _tvTotalMediaCount,
      itemBuilder: (context, index) {
        final item = _tvItemAt(index);
        if (item == null) return const SizedBox.shrink();
        return _TvMediaCard(
          key: ValueKey('${item.type}_${item.mediaPath}_$index'),
          item: item,
          config: currentConfig,
          getThumbnail: _getTvThumbnailData,
          onTap: () => _onTvMediaClicked(item),
        );
      },
    );
  }

  Widget _buildTvLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.pink.shade400),
            strokeWidth: 3.5,
          ),
          const SizedBox(height: 20),
          const Text(
            '正在加载宝宝的照片与视频...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: Colors.orange.shade300),
          const SizedBox(height: 16),
          const Text(
            '加载失败',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? '网络连接或云存储配置异常',
            style: const TextStyle(fontSize: 14, color: Colors.white60),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TvFocusableButton(
                icon: Icons.refresh_rounded,
                label: '重试',
                isPrimary: true,
                onTap: _onRefresh,
              ),
              const SizedBox(width: 16),
              _TvFocusableButton(
                icon: Icons.settings_rounded,
                label: '检查设置',
                onTap: _openSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTvEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 58,
                color: Colors.pink.shade300,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '开启大屏温馨回忆',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '在手机端记录宝宝的照片与视频并同步到云端后，\n即可在电视大屏上沉浸式重温每一个珍贵瞬间。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white70,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TvFocusableButton(
                  icon: Icons.refresh_rounded,
                  label: '刷新同步',
                  isPrimary: true,
                  onTap: _onRefresh,
                ),
                const SizedBox(width: 20),
                _TvFocusableButton(
                  icon: Icons.settings_rounded,
                  label: '云存储设置',
                  onTap: _openSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────
// TV 专用数据模型与交互组件
// ──────────────────────────────────────────

enum TvMediaType { photo, video }

class TvMediaItem {
  final TvMediaType type;
  final String mediaPath;
  final String thumbnailPath;
  final DiaryEntry entry;
  final int indexInEntry;

  TvMediaItem({
    required this.type,
    required this.mediaPath,
    required this.thumbnailPath,
    required this.entry,
    required this.indexInEntry,
  });
}

class _TvMediaCard extends StatefulWidget {
  final TvMediaItem item;
  final AppConfig config;
  final Future<Uint8List?> Function(String) getThumbnail;
  final VoidCallback onTap;

  const _TvMediaCard({
    super.key,
    required this.item,
    required this.config,
    required this.getThumbnail,
    required this.onTap,
  });

  @override
  State<_TvMediaCard> createState() => _TvMediaCardState();
}

class _TvMediaCardState extends State<_TvMediaCard> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isFocused = _focusNode.hasFocus;
        });
        if (_focusNode.hasFocus) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.item.entry;
    final isVideo = widget.item.type == TvMediaType.video;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused ? Colors.pinkAccent : Colors.white12,
                width: _isFocused ? 3.5 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.55),
                        blurRadius: 18,
                        spreadRadius: 3,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景底色
                  Container(color: const Color(0xFF22242B)),

                  // 缩略图
                  FutureBuilder<Uint8List?>(
                    future: widget.getThumbnail(widget.item.thumbnailPath),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white24,
                          ),
                        );
                      }
                      if (snapshot.hasData && snapshot.data != null) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        );
                      }
                      return Center(
                        child: Icon(
                          isVideo ? Icons.videocam : Icons.photo,
                          size: 40,
                          color: Colors.white24,
                        ),
                      );
                    },
                  ),

                  // 渐变蒙层
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 视频播放图标
                  if (isVideo)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white54, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // 视频角标
                  if (isVideo)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              '视频',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 底部文字信息
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              entry.getSimplifiedAgeLabel(widget.config),
                              style: TextStyle(
                                color: Colors.pink.shade200,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}-${entry.date.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        if (entry.title.isNotEmpty ||
                            entry.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            entry.title.isNotEmpty
                                ? entry.title
                                : entry.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvFocusableButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool showLabelOnlyOnFocus;

  const _TvFocusableButton({
    required this.icon,
    this.label,
    required this.onTap,
    this.isPrimary = false,
    this.showLabelOnlyOnFocus = false,
  });

  @override
  State<_TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<_TvFocusableButton> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool shouldShowLabel = widget.label != null &&
        widget.label!.isNotEmpty &&
        (!widget.showLabelOnlyOnFocus || _isFocused);

    final bgColor = widget.isPrimary
        ? (_isFocused ? Colors.pink.shade600 : Colors.pink.shade500)
        : (_isFocused
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.12));
    const fgColor = Colors.white;
    final borderColor = widget.isPrimary
        ? (_isFocused ? Colors.pink.shade300 : Colors.transparent)
        : (_isFocused ? Colors.pink.shade300 : Colors.transparent);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: shouldShowLabel ? 14 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: borderColor, width: _isFocused ? 2.5 : 1),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.45),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: fgColor),
                if (shouldShowLabel) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label!,
                    style: const TextStyle(
                      color: fgColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvFilterTab extends StatefulWidget {
  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _TvFilterTab({
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TvFilterTab> createState() => _TvFilterTabState();
}

class _TvFilterTabState extends State<_TvFilterTab> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Border border;

    if (widget.isSelected) {
      bg = _isFocused ? Colors.pink.shade600 : Colors.pink.shade500;
      fg = Colors.white;
      border = Border.all(
          color: _isFocused ? Colors.pink.shade200 : Colors.transparent,
          width: 2);
    } else {
      bg = _isFocused
          ? Colors.white.withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.08);
      fg = _isFocused ? Colors.white : Colors.white70;
      border = Border.all(
          color: _isFocused ? Colors.pink.shade300 : Colors.transparent,
          width: 2);
    }

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: border,
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  widget.count > 0
                      ? '${widget.label} (${widget.count})'
                      : widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: widget.isSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvBabyProfileButton extends StatefulWidget {
  final String name;
  final String ageText;
  final Uint8List? coverImage;
  final VoidCallback onTap;

  const _TvBabyProfileButton({
    required this.name,
    required this.ageText,
    required this.coverImage,
    required this.onTap,
  });

  @override
  State<_TvBabyProfileButton> createState() => _TvBabyProfileButtonState();
}

class _TvBabyProfileButtonState extends State<_TvBabyProfileButton> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _isFocused
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused
                    ? Colors.pink.shade400
                    : Colors.white.withValues(alpha: 0.12),
                width: _isFocused ? 2.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.pink.shade900,
                  backgroundImage: widget.coverImage != null
                      ? MemoryImage(widget.coverImage!)
                      : null,
                  child: widget.coverImage == null
                      ? const Icon(Icons.child_care_rounded,
                          color: Colors.white, size: 24)
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          color:
                              _isFocused ? Colors.pink.shade300 : Colors.white70,
                          size: 22,
                        ),
                      ],
                    ),
                    if (widget.ageText.isNotEmpty)
                      Text(
                        widget.ageText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.pink.shade300,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvBabyDialogItem extends StatefulWidget {
  final AppConfig config;
  final bool isCurrent;
  final VoidCallback onTap;

  const _TvBabyDialogItem({
    required this.config,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  State<_TvBabyDialogItem> createState() => _TvBabyDialogItemState();
}

class _TvBabyDialogItemState extends State<_TvBabyDialogItem> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final babyName = widget.config.babyName.isNotEmpty
        ? widget.config.babyName
        : '宝宝';
    final ageText = widget.config.babyBirthDate != null
        ? AgeCalculator.formatAgeLabel(
            AgeCalculator.calculateAgeInMonths(
                widget.config.babyBirthDate!, DateTime.now()))
        : '';

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isFocused
                  ? Colors.pink.shade900.withValues(alpha: 0.4)
                  : (widget.isCurrent
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isFocused
                    ? Colors.pink.shade400
                    : (widget.isCurrent
                        ? Colors.pink.shade700.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.08)),
                width: _isFocused ? 2.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: widget.isCurrent
                      ? Colors.pink.shade600
                      : Colors.white.withValues(alpha: 0.15),
                  child: const Icon(
                    Icons.child_care_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        babyName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (ageText.isNotEmpty)
                        Text(
                          ageText,
                          style: TextStyle(
                            color: Colors.pink.shade300,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          '当前',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvBabySwitcherDialog extends StatelessWidget {
  final List<AppConfig> configs;
  final String currentConfigId;
  final ValueChanged<AppConfig> onSelect;
  final VoidCallback onAddNewBaby;

  const _TvBabySwitcherDialog({
    required this.configs,
    required this.currentConfigId,
    required this.onSelect,
    required this.onAddNewBaby,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1F24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side:
            BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
      ),
      child: Container(
        width: 640,
        height: 480,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.switch_account_rounded,
                    color: Colors.pink.shade300, size: 26),
                const SizedBox(width: 12),
                const Text(
                  '切换宝宝档案',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                const Text(
                  '按遥控器方向键选择',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: configs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final config = configs[index];
                  final isCurrent = config.id == currentConfigId;
                  return _TvBabyDialogItem(
                    config: config,
                    isCurrent: isCurrent,
                    onTap: () => onSelect(config),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TvFocusableButton(
                  icon: Icons.qr_code_2_rounded,
                  label: '扫码配对新宝宝 (接收手机配置)',
                  onTap: onAddNewBaby,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvTimelineItem extends StatefulWidget {
  final DateTime month;
  final int count;
  final DateTime? birthDate;
  final AppConfig config;
  final VoidCallback onTap;

  const _TvTimelineItem({
    required this.month,
    required this.count,
    required this.birthDate,
    required this.config,
    required this.onTap,
  });

  @override
  State<_TvTimelineItem> createState() => _TvTimelineItemState();
}

class _TvTimelineItemState extends State<_TvTimelineItem> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBirthMonth = widget.birthDate != null &&
        widget.month.year == widget.birthDate!.year &&
        widget.month.month == widget.birthDate!.month;
    final isBirthdayMonth = widget.birthDate != null &&
        widget.month.month == widget.birthDate!.month &&
        widget.month.year > widget.birthDate!.year;

    final ageLabel = AgeCalculator.formatSimplifiedAgeLabel(
      DateTime(widget.month.year, widget.month.month, 1),
      widget.config,
    );
    final monthStr = '${widget.month.year}年${widget.month.month}月';

    final IconData iconData = isBirthMonth
        ? Icons.child_friendly_rounded
        : isBirthdayMonth
            ? Icons.cake_rounded
            : Icons.calendar_today_rounded;

    final Color iconColor = isBirthMonth
        ? Colors.lightBlueAccent
        : isBirthdayMonth
            ? Colors.pinkAccent
            : Colors.white70;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _isFocused
                  ? Colors.pink.shade900.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isFocused
                    ? Colors.pink.shade400
                    : Colors.white.withValues(alpha: 0.08),
                width: _isFocused ? 2.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isBirthMonth ? '🎉 出生月' : ageLabel,
                        style: TextStyle(
                          color: isBirthMonth || isBirthdayMonth
                              ? Colors.pink.shade200
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        monthStr,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.count} 项',
                    style: TextStyle(
                      color: Colors.pink.shade200,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvTimelineDialog extends StatelessWidget {
  final List<DateTime> months;
  final Map<DateTime, int> monthCounts;
  final DateTime? birthDate;
  final AppConfig config;
  final ValueChanged<DateTime> onSelectMonth;

  const _TvTimelineDialog({
    required this.months,
    required this.monthCounts,
    required this.birthDate,
    required this.config,
    required this.onSelectMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1F24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side:
            BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
      ),
      child: Container(
        width: 760,
        height: 540,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_rounded,
                    color: Colors.pink.shade300, size: 26),
                const SizedBox(width: 12),
                const Text(
                  '时间轴快速跳转',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade900.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${months.length} 个月份',
                    style: TextStyle(
                      color: Colors.pink.shade200,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  '按遥控器方向键选择，按确认键跳转',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: months.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无记录',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 12,
                        childAspectRatio: 3.2,
                      ),
                      itemCount: months.length,
                      itemBuilder: (context, index) {
                        final month = months[index];
                        final count = monthCounts[month] ?? 0;
                        return _TvTimelineItem(
                          month: month,
                          count: count,
                          birthDate: birthDate,
                          config: config,
                          onTap: () => onSelectMonth(month),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


