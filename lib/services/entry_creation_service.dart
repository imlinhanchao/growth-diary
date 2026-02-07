import 'dart:io';

import '../models/app_config.dart';
import '../models/diary_entry.dart';

import '../services/cloud_storage_service.dart';
import '../utils/age_calculator.dart';
import '../utils/file_utils.dart' as file_utils;

typedef UploadProgressCallback = void Function(int uploaded, int total);

class EntryCreationService {
  final CloudStorageService webdavService;

  EntryCreationService(this.webdavService);

  int _calculateAgeInMonths(DateTime date, AppConfig config) {
    final birthDate = config.childBirthDate!;
    return AgeCalculator.calculateAgeInMonths(birthDate, date);
  }

  Future<List<DiaryEntry>> createMediaEntry(
      List<file_utils.MediaFile> mediaFiles,
      String description,
      AppConfig config,
      [UploadProgressCallback? onProgress,
      DateTime? overrideDate,
      String? uploadTaskId]) async {
    if (mediaFiles.isEmpty) return [];

    // 如果指定了overrideDate，所有媒体都使用这个日期
    if (overrideDate != null) {
      final entry = DiaryEntry(
        id: overrideDate.millisecondsSinceEpoch.toString(),
        date: overrideDate,
        title: description,
        description: description,
        imagePaths: mediaFiles
            .where((f) => f.type == file_utils.MediaType.image)
            .map((f) => f.srcPath)
            .toList(),
        videoPaths: mediaFiles
            .where((f) => f.type == file_utils.MediaType.video)
            .map((f) => f.srcPath)
            .toList(),
        imageThumbnails: [],
        videoThumbnails: [],
        ageInMonths: AgeCalculator.calculateDateDifference(
            overrideDate, config.childBirthDate!)['months']!,
      );

      await webdavService.saveDiaryEntry(entry);
      return [entry];
    }

    // 按日期分组媒体文件
    final Map<String, List<Map<String, dynamic>>> dateGroups = {};

    for (var i = 0; i < mediaFiles.length; i++) {
      final mediaFile = mediaFiles[i];
      final file = File(mediaFile.srcPath);

      // 提取媒体文件日期
      DateTime mediaDate;
      if (mediaFile.createdAt != null) {
        try {
          mediaDate = mediaFile.createdAt!;
        } catch (e) {
          // 如果解析失败，使用文件修改时间
          final stat = await file.stat();
          mediaDate = stat.modified;
        }
      } else {
        // 如果没有createdAt，使用文件修改时间
        final stat = await file.stat();
        mediaDate = stat.modified;
      }

      // 使用日期的YYYY-MM-DD格式作为分组键
      final dateKey =
          '${mediaDate.year}-${mediaDate.month.toString().padLeft(2, '0')}-${mediaDate.day.toString().padLeft(2, '0')}';

      if (!dateGroups.containsKey(dateKey)) {
        dateGroups[dateKey] = [];
      }

      dateGroups[dateKey]!.add({
        'mediaFile': mediaFile,
        'date': mediaDate,
        'index': i,
      });
    }

    // 为每个日期组创建entry
    final List<DiaryEntry> entries = [];
    int totalProcessed = 0;

    for (final dateKey in dateGroups.keys) {
      final mediaDataList = dateGroups[dateKey]!;
      final List<String> imagePaths = [];
      final List<String> videoPaths = [];

      // 使用该组第一个媒体文件的日期作为entry日期
      final entryDate = mediaDataList.first['date'] as DateTime;
      final mediaTimestampId = entryDate.millisecondsSinceEpoch.toString();

      // 上传该组的所有媒体文件
      for (final mediaData in mediaDataList) {
        final mediaFile = mediaData['mediaFile'] as file_utils.MediaFile;

        if (mediaFile.type == file_utils.MediaType.image) {
          imagePaths.add(mediaFile.srcPath);
        } else if (mediaFile.type == file_utils.MediaType.video) {
          videoPaths.add(mediaFile.srcPath);
        }

        totalProcessed++;
        onProgress?.call(totalProcessed, mediaFiles.length);
      }

      final entry = DiaryEntry(
        id: mediaTimestampId,
        date: entryDate,
        title: description,
        description: description,
        imagePaths: imagePaths,
        videoPaths: videoPaths,
        imageThumbnails: [],
        videoThumbnails: [],
        ageInMonths: _calculateAgeInMonths(entryDate, config),
      );

      entries.add(entry);
    }

    return entries;
  }

  Future<DiaryEntry> createDiaryEntry(
      String title, String content, AppConfig config,
      {DateTime? customDate}) async {
    final date = customDate ?? DateTime.now();
    final publicationTime = DateTime.now();

    // 如果有自定义日期，使用自定义日期 + 发布时间戳作为ID
    // 否则只使用发布时间戳
    final id = customDate != null
        ? '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}_${publicationTime.millisecondsSinceEpoch}'
        : publicationTime.millisecondsSinceEpoch.toString();

    final entry = DiaryEntry(
      id: id,
      date: date,
      title: title,
      description: content,
      imagePaths: [],
      videoPaths: [],
      ageInMonths: _calculateAgeInMonths(date, config),
    );

    return entry;
  }
}
