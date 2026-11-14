import 'package:uuid/uuid.dart';
import '../utils/age_calculator.dart';
import 'app_config.dart';

class DiaryEntry {
  final String id;
  final DateTime date;
  final String title;
  final String description;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final List<String> imageThumbnails; // 小号缩略图，用于时间轴
  final List<String> videoThumbnails; // 小号缩略图，用于时间轴
  final int ageInMonths;

  // 同步控制字段。旧版本写下的条目没有这些字段，读取时一律按 0 / 空处理。
  final int updatedAt; // 毫秒时间戳，用于同版本号时的裁决与展示
  final int rev; // 版本递增计数器，冲突裁决以它为主
  final String deviceId; // 最后写入的设备

  DiaryEntry({
    String? id,
    required this.date,
    required this.title,
    this.description = '',
    this.imagePaths = const [],
    this.videoPaths = const [],
    this.imageThumbnails = const [],
    this.videoThumbnails = const [],
    required this.ageInMonths,
    this.updatedAt = 0,
    this.rev = 0,
    this.deviceId = '',
  }) : id = id ?? const Uuid().v4();

  DiaryEntry copyWith({
    String? id,
    DateTime? date,
    String? title,
    String? description,
    List<String>? imagePaths,
    List<String>? videoPaths,
    List<String>? imageThumbnails,
    List<String>? videoThumbnails,
    int? ageInMonths,
    int? updatedAt,
    int? rev,
    String? deviceId,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      description: description ?? this.description,
      imagePaths: imagePaths ?? this.imagePaths,
      videoPaths: videoPaths ?? this.videoPaths,
      imageThumbnails: imageThumbnails ?? this.imageThumbnails,
      videoThumbnails: videoThumbnails ?? this.videoThumbnails,
      ageInMonths: ageInMonths ?? this.ageInMonths,
      updatedAt: updatedAt ?? this.updatedAt,
      rev: rev ?? this.rev,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'title': title,
      'description': description,
      'imagePaths': imagePaths,
      'videoPaths': videoPaths,
      'imageThumbnails': imageThumbnails,
      'videoThumbnails': videoThumbnails,
      'ageInMonths': ageInMonths,
      'updatedAt': updatedAt,
      'rev': rev,
      'deviceId': deviceId,
    };
  }

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      id: json['id'],
      date: DateTime.parse(json['date']),
      title: json['title'],
      description: json['description'] ?? '',
      imagePaths: List<String>.from(json['imagePaths'] ?? []),
      videoPaths: List<String>.from(json['videoPaths'] ?? []),
      imageThumbnails: List<String>.from(json['imageThumbnails'] ?? []),
      videoThumbnails: List<String>.from(json['videoThumbnails'] ?? []),
      ageInMonths: json['ageInMonths'],
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      rev: (json['rev'] as num?)?.toInt() ?? 0,
      deviceId: json['deviceId'] as String? ?? '',
    );
  }

  String getAgeLabel(AppConfig? config) {
    if (config != null) {
      return AgeCalculator.formatDetailedAgeLabel(date, config);
    } else {
      return AgeCalculator.formatAgeLabel(ageInMonths);
    }
  }

  String getSimplifiedAgeLabel(AppConfig config) {
    if (config.childBirthDate != null) {
      return AgeCalculator.formatSimplifiedAgeLabel(date, config);
    } else {
      return AgeCalculator.formatAgeLabel(ageInMonths);
    }
  }

  int getGroupKey(AppConfig config) {
    if (config.conceptionDate != null &&
        date.isBefore(config.childBirthDate ?? DateTime.now())) {
      return AgeCalculator.calculateWeeksDifference(
          config.conceptionDate!, date);
    } else {
      return AgeCalculator.calculateDateDifference(
          config.childBirthDate!, date)['months']!;
    }
  }
}

/// 详情页返回结果
class EntryDetailResult {
  final bool isDeleted;
  final DiaryEntry? updatedEntry;

  const EntryDetailResult({
    this.isDeleted = false,
    this.updatedEntry,
  });

  factory EntryDetailResult.updated(DiaryEntry entry) {
    return EntryDetailResult(isDeleted: false, updatedEntry: entry);
  }

  factory EntryDetailResult.deleted() {
    return const EntryDetailResult(isDeleted: true, updatedEntry: null);
  }
}
