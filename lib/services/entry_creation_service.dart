import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:exif/exif.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_video_info/flutter_video_info.dart';

import '../models/app_config.dart';
import '../models/diary_entry.dart';

import '../services/cloud_storage_service.dart';
import '../utils/age_calculator.dart';
import '../utils/file_utils.dart' as file_utils;

typedef UploadProgressCallback = void Function(int uploaded, int total);

class EntryCreationService {
  final CloudStorageService webdavService;

  EntryCreationService(this.webdavService);

  String _generateFileName(File file, FileStat stat) {
    final extension = path.extension(file.path);
    final isLargeVideo = stat.size > 4 * 1024 * 1024; // 4MB

    Digest hash;

    if (isLargeVideo) {
      // 对于大视频，只读取前1MB内容 + 文件大小 + 修改时间
      final fileStream = file.openSync(mode: FileMode.read);
      final buffer = Uint8List(1024 * 1024); // 1MB buffer
      final bytesRead = fileStream.readIntoSync(buffer);
      fileStream.closeSync();

      final prefix =
          bytesRead < buffer.length ? buffer.sublist(0, bytesRead) : buffer;
      final sizeStr = stat.size.toString();
      final mtimeStr = stat.modified.millisecondsSinceEpoch.toString();
      final combined = prefix + sizeStr.codeUnits + mtimeStr.codeUnits;
      hash = sha256.convert(combined);
    } else {
      // 对于其他文件，使用整个文件的SHA256
      final bytes = file.readAsBytesSync();
      hash = sha256.convert(bytes);
    }

    return '${hash.toString()}$extension';
  }

  DateTime _parseExifDate(String exifDate) {
    try {
      return DateTime.parse(exifDate);
    } catch (e) {
      // EXIF日期格式: "YYYY:MM:DD HH:MM:SS"
      final parts = exifDate.split(' ');
      if (parts.length == 2) {
        final dateParts = parts[0].split(':');
        final timeParts = parts[1].split(':');
        if (dateParts.length == 3 && timeParts.length == 3) {
          return DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
            int.parse(timeParts[2]),
          );
        }
      }
    }
    // 如果解析失败，返回当前时间
    return DateTime.now();
  }

  /// 从视频文件中提取原始创建时间
  Future<DateTime> _getVideoCreationDate(String videoPath) async {
    try {
      // 首先尝试使用 flutter_video_info 获取视频元数据
      try {
        final videoInfo = FlutterVideoInfo();
        final info = await videoInfo.getVideoInfo(videoPath);

        if (info != null && info.date != null) {
          // flutter_video_info 返回的 date 字段就是创建时间
          final date = info.date;
          if (date is String) {
            // 如果是字符串，尝试解析
            final parsedDate = _parseExifDate(date);
            if (parsedDate != DateTime.now()) {
              // _parseExifDate 在失败时返回当前时间
              return parsedDate;
            }
          }
        }
      } catch (e) {
        // flutter_video_info 失败，继续使用其他方法
      }

      // 其次尝试从文件名解析时间戳
      final fileName = path.basename(videoPath);
      final dateFromFileName = _parseDateFromFileName(fileName);
      if (dateFromFileName != null) {
        return dateFromFileName;
      }

      // 最后回退到文件的修改时间
      final file = File(videoPath);
      final stat = await file.stat();
      return stat.modified;
    } catch (e) {
      // 如果所有方法都失败，使用文件的修改时间
      final file = File(videoPath);
      final stat = await file.stat();
      return stat.modified;
    }
  }

  /// 从文件名中解析日期
  /// 支持常见的相机命名格式，如 IMG_20231201_123456.jpg 或 VID_20231201_123456.mp4
  DateTime? _parseDateFromFileName(String fileName) {
    // 移除扩展名
    final nameWithoutExt = fileName.split('.').first;

    // 查找日期时间模式：YYYYMMDD_HHMMSS 或 YYYYMMDDHHMMSS
    final dateTimePattern = RegExp(r'(\d{8})_?(\d{6})');
    final match = dateTimePattern.firstMatch(nameWithoutExt);

    if (match != null) {
      final dateStr = match.group(1)!;
      final timeStr = match.group(2)!;

      try {
        final year = int.parse(dateStr.substring(0, 4));
        final month = int.parse(dateStr.substring(4, 6));
        final day = int.parse(dateStr.substring(6, 8));
        final hour = int.parse(timeStr.substring(0, 2));
        final minute = int.parse(timeStr.substring(2, 4));
        final second = int.parse(timeStr.substring(4, 6));

        return DateTime(year, month, day, hour, minute, second);
      } catch (e) {
        // 解析失败
        return null;
      }
    }

    return null;
  }

  int _calculateAgeInMonths(DateTime date, AppConfig config) {
    final birthDate = config.childBirthDate!;
    return AgeCalculator.calculateAgeInMonths(birthDate, date);
  }

  Future<List<DiaryEntry>> createImageEntry(
      List<XFile> images, String description, AppConfig config,
      [UploadProgressCallback? onProgress,
      DateTime? overrideDate,
      String? uploadTaskId]) async {
    if (images.isEmpty) return [];

    // 如果指定了overrideDate，所有图片都使用这个日期
    if (overrideDate != null) {
      final List<String> imagePaths = [];
      final List<String> imageThumbnails = [];

      for (var i = 0; i < images.length; i++) {
        final xfile = images[i];
        final file = File(xfile.path);
        final stat = await file.stat();
        final fileName = _generateFileName(file, stat);
        final paths =
            await webdavService.uploadImageWithThumbnails(file, fileName);
        final pathList = paths.split('|');
        if (pathList.length >= 3) {
          imagePaths.add(pathList[0]); // 原图
          imageThumbnails.add(pathList[2]); // 小号缩略图
        } else {
          imagePaths.add(paths);
          imageThumbnails.add(paths); // 如果没有缩略图，使用原图
        }
        onProgress?.call(i + 1, images.length);
      }

      final entry = DiaryEntry(
        id: overrideDate.millisecondsSinceEpoch.toString(),
        date: overrideDate,
        title: description,
        description: description,
        imagePaths: imagePaths,
        videoPaths: [],
        imageThumbnails: imageThumbnails,
        videoThumbnails: [],
        ageInMonths: _calculateAgeInMonths(overrideDate, config),
      );

      await webdavService.saveDiaryEntry(entry);
      return [entry];
    }

    // 按日期分组图片
    final Map<String, List<Map<String, dynamic>>> dateGroups = {};

    for (var i = 0; i < images.length; i++) {
      final xfile = images[i];
      final file = File(xfile.path);

      // 提取图片日期
      DateTime imageDate = DateTime.now();
      try {
        final exifData = await readExifFromBytes(await file.readAsBytes());
        final dateTimeOriginal = exifData['EXIF DateTimeOriginal'];
        final imageDateTime = exifData['Image DateTime'];
        if (dateTimeOriginal != null) {
          imageDate = _parseExifDate(dateTimeOriginal.toString());
        } else if (imageDateTime != null) {
          imageDate = _parseExifDate(imageDateTime.toString());
        } else {
          final stat = await file.stat();
          imageDate = stat.modified;
        }
      } catch (e) {
        final stat = await file.stat();
        imageDate = stat.modified;
      }

      // 使用日期的YYYY-MM-DD格式作为分组键
      final dateKey =
          '${imageDate.year}-${imageDate.month.toString().padLeft(2, '0')}-${imageDate.day.toString().padLeft(2, '0')}';

      if (!dateGroups.containsKey(dateKey)) {
        dateGroups[dateKey] = [];
      }

      dateGroups[dateKey]!.add({
        'file': file,
        'date': imageDate,
        'index': i,
      });
    }

    // 为每个日期组创建entry
    final List<DiaryEntry> entries = [];
    int totalProcessed = 0;

    for (final dateKey in dateGroups.keys) {
      final imageDataList = dateGroups[dateKey]!;
      final List<String> imagePaths = [];
      final List<String> imageThumbnails = [];

      // 使用该组第一张图片的日期作为entry日期
      final entryDate = imageDataList.first['date'] as DateTime;
      final photoTimestampId = entryDate.millisecondsSinceEpoch.toString();

      // 上传该组的所有图片
      for (final imageData in imageDataList) {
        final file = imageData['file'] as File;
        final stat = await file.stat();
        final fileName = _generateFileName(file, stat);
        final paths =
            await webdavService.uploadImageWithThumbnails(file, fileName);
        final pathList = paths.split('|');
        if (pathList.length >= 3) {
          imagePaths.add(pathList[0]); // 原图
          imageThumbnails.add(pathList[2]); // 小号缩略图
        } else {
          imagePaths.add(paths);
          imageThumbnails.add(paths); // 如果没有缩略图，使用原图
        }

        totalProcessed++;
        onProgress?.call(totalProcessed, images.length);
      }

      final entry = DiaryEntry(
        id: photoTimestampId,
        date: entryDate,
        title: description,
        description: description,
        imagePaths: imagePaths,
        videoPaths: [],
        imageThumbnails: imageThumbnails,
        videoThumbnails: [],
        ageInMonths: _calculateAgeInMonths(entryDate, config),
      );

      await webdavService.saveDiaryEntry(entry);
      entries.add(entry);
    }

    return entries;
  }

  Future<List<DiaryEntry>> createVideoEntry(
      List<XFile> videos, String description, AppConfig config,
      [UploadProgressCallback? onProgress,
      DateTime? overrideDate,
      String? uploadTaskId]) async {
    if (videos.isEmpty) return [];

    // 如果指定了overrideDate，所有视频都使用这个日期
    if (overrideDate != null) {
      final List<String> videoPaths = [];
      final List<String> videoThumbnails = [];

      for (var i = 0; i < videos.length; i++) {
        final xfile = videos[i];
        final file = File(xfile.path);
        final stat = await file.stat();
        final fileName = _generateFileName(file, stat);
        final paths =
            await webdavService.uploadVideoWithThumbnails(file, fileName);
        final pathList = paths.split('|');
        final uploadedPath = pathList[0];
        final thumbnailPath = pathList.length >= 3 && pathList[2].isNotEmpty
            ? pathList[2]
            : pathList[0];

        videoPaths.add(uploadedPath);
        videoThumbnails.add(thumbnailPath);
        onProgress?.call(i + 1, videos.length);
      }

      final entry = DiaryEntry(
        id: overrideDate.millisecondsSinceEpoch.toString(),
        date: overrideDate,
        title: description,
        description: description,
        imagePaths: [],
        videoPaths: videoPaths,
        imageThumbnails: [],
        videoThumbnails: videoThumbnails,
        ageInMonths: _calculateAgeInMonths(overrideDate, config),
      );

      await webdavService.saveDiaryEntry(entry);
      return [entry];
    }

    // 按日期分组视频
    final Map<String, List<Map<String, dynamic>>> dateGroups = {};

    for (var i = 0; i < videos.length; i++) {
      final xfile = videos[i];
      final file = File(xfile.path);

      // 提取视频日期
      final videoDate = await _getVideoCreationDate(file.path);

      // 使用日期的YYYY-MM-DD格式作为分组键
      final dateKey =
          '${videoDate.year}-${videoDate.month.toString().padLeft(2, '0')}-${videoDate.day.toString().padLeft(2, '0')}';

      if (!dateGroups.containsKey(dateKey)) {
        dateGroups[dateKey] = [];
      }

      dateGroups[dateKey]!.add({
        'file': file,
        'date': videoDate,
        'index': i,
      });
    }

    // 为每个日期组创建entry
    final List<DiaryEntry> entries = [];
    int totalProcessed = 0;

    for (final dateKey in dateGroups.keys) {
      final videoDataList = dateGroups[dateKey]!;
      final List<String> videoPaths = [];
      final List<String> videoThumbnails = [];

      // 使用该组第一个视频的日期作为entry日期
      final entryDate = videoDataList.first['date'] as DateTime;
      final videoTimestampId = entryDate.millisecondsSinceEpoch.toString();

      // 上传该组的所有视频
      for (final videoData in videoDataList) {
        final file = videoData['file'] as File;
        final stat = await file.stat();
        final fileName = _generateFileName(file, stat);
        final paths =
            await webdavService.uploadVideoWithThumbnails(file, fileName);
        final pathList = paths.split('|');
        final uploadedPath = pathList[0];
        final thumbnailPath =
            pathList.length >= 3 && pathList[2].isNotEmpty ? pathList[2] : null;

        videoPaths.add(uploadedPath);
        if (thumbnailPath != null) {
          videoThumbnails.add(thumbnailPath);
        }

        totalProcessed++;
        onProgress?.call(totalProcessed, videos.length);
      }

      final entry = DiaryEntry(
        id: videoTimestampId,
        date: entryDate,
        title: description,
        description: description,
        imagePaths: [],
        videoPaths: videoPaths,
        imageThumbnails: [],
        videoThumbnails: videoThumbnails,
        ageInMonths: _calculateAgeInMonths(entryDate, config),
      );

      await webdavService.saveDiaryEntry(entry);
      entries.add(entry);
    }

    return entries;
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
        ageInMonths: _calculateAgeInMonths(overrideDate, config),
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

      // 对于视频，尝试获取更准确的创建时间
      if (mediaFile.type == file_utils.MediaType.video) {
        try {
          mediaDate = await _getVideoCreationDate(mediaFile.srcPath);
        } catch (e) {
          // 如果获取失败，使用已有的日期
        }
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
