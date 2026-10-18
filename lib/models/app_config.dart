import 'package:uuid/uuid.dart';
import '../utils/age_calculator.dart';
import 'webdav_mirror.dart';

export 'webdav_mirror.dart';

class Baby {
  String id;
  String name;
  DateTime? birthDate;
  DateTime? conceptionDate;

  Baby({
    this.id = '',
    this.name = '',
    this.birthDate,
    this.conceptionDate,
  }) {
    if (id.isEmpty) {
      id = const Uuid().v4();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'birthDate': birthDate?.toIso8601String(),
      'conceptionDate': conceptionDate?.toIso8601String(),
    };
  }

  factory Baby.fromJson(Map<String, dynamic> json) {
    return Baby(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? '',
      birthDate:
          json['birthDate'] != null ? DateTime.parse(json['birthDate']) : null,
      conceptionDate: json['conceptionDate'] != null
          ? DateTime.parse(json['conceptionDate'])
          : null,
    );
  }

  // 获取年龄标签的辅助方法
  String getAgeLabel() {
    if (birthDate == null) return name;
    final now = DateTime.now();
    final ageInMonths = AgeCalculator.calculateAgeInMonths(birthDate!, now);
    if (ageInMonths < 0) {
      // 还没出生，显示孕期
      final weeks = AgeCalculator.calculateWeeksDifference(birthDate!, now);
      return '$name (孕$weeks周)';
    } else {
      // 已出生，显示月龄
      return '$name ($ageInMonths个月)';
    }
  }
}

class AppConfig {
  String id;
  String webdavUrl; // 保留向后兼容
  String username;
  String password;
  String babyName;
  DateTime? babyBirthDate;
  DateTime? babyConceptionDate;
  String? babyCoverImagePath; // 宝宝封面图路径
  int videoCompressionThreshold; // 视频压缩阈值，单位MB，0表示不压缩
  List<WebDavMirror> webdavMirrors = []; // WebDAV 镜像地址列表

  AppConfig({
    this.id = '',
    this.webdavUrl = '',
    this.username = '',
    this.password = '',
    this.babyName = '',
    this.babyBirthDate,
    this.babyConceptionDate,
    this.babyCoverImagePath,
    this.videoCompressionThreshold = 10, // 默认10MB
    List<dynamic>? webdavMirrors,
  }) {
    if (id.isEmpty) {
      id = const Uuid().v4();
    }
    if (webdavMirrors != null) {
      this.webdavMirrors = webdavMirrors.map((e) {
        if (e is WebDavMirror) return e;
        return WebDavMirror.fromJson(e);
      }).toList();
    } else {
      this.webdavMirrors = [];
    }

    // 向后兼容：如果有旧的 webdavUrl 但 mirrors 为空，则迁移
    if (webdavUrl.isNotEmpty && this.webdavMirrors.isEmpty) {
      this.webdavMirrors.add(WebDavMirror(url: webdavUrl));
    }
  }

  // 检查配置是否完整
  bool get isConfigured {
    return webdavUrl.isNotEmpty && username.isNotEmpty && babyName.isNotEmpty;
  }

  // 向后兼容的getter
  String get childName => babyName;
  DateTime? get childBirthDate => babyBirthDate;
  DateTime? get conceptionDate => babyConceptionDate;

  /// 获取所有镜像的 URL 列表（兼容旧代码）
  List<String> get webdavMirrorUrls => webdavMirrors.map((m) => m.url).toList();

  /// 查找与指定 WiFi SSID 匹配的镜像
  WebDavMirror? getMirrorForWifi(String? ssid) {
    if (ssid == null || ssid.trim().isEmpty) return null;
    for (final mirror in webdavMirrors) {
      if (mirror.matchesWifi(ssid)) {
        return mirror;
      }
    }
    return null;
  }

  /// 获取第一个没有配置/绑定 WiFi 的镜像（作为通用/默认镜像）
  WebDavMirror? get defaultUnboundMirror {
    for (final mirror in webdavMirrors) {
      if (!mirror.hasWifiBinding && mirror.url.isNotEmpty) {
        return mirror;
      }
    }
    return null;
  }

  // 获取年龄标签
  String getAgeLabel() {
    if (babyBirthDate == null) return babyName;
    final now = DateTime.now();
    final ageInMonths = AgeCalculator.calculateAgeInMonths(babyBirthDate!, now);
    if (ageInMonths < 0) {
      // 还没出生，显示孕期
      final weeks = AgeCalculator.calculateWeeksDifference(babyBirthDate!, now);
      return '$babyName (孕$weeks周)';
    } else {
      // 已出生，显示月龄
      return '$babyName ($ageInMonths个月)';
    }
  }

  // 创建副本的方法
  AppConfig copyWith({
    String? id,
    String? webdavUrl,
    String? username,
    String? password,
    String? babyName,
    DateTime? babyBirthDate,
    DateTime? babyConceptionDate,
    String? babyCoverImagePath,
    int? videoCompressionThreshold,
    List<WebDavMirror>? webdavMirrors,
  }) {
    return AppConfig(
      id: id ?? this.id,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      babyName: babyName ?? this.babyName,
      babyBirthDate: babyBirthDate ?? this.babyBirthDate,
      babyConceptionDate: babyConceptionDate ?? this.babyConceptionDate,
      babyCoverImagePath: babyCoverImagePath ?? this.babyCoverImagePath,
      videoCompressionThreshold:
          videoCompressionThreshold ?? this.videoCompressionThreshold,
      webdavMirrors: webdavMirrors ?? List.from(this.webdavMirrors),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'webdavUrl': webdavUrl,
      'username': username,
      'password': password,
      'babyName': babyName,
      'babyBirthDate': babyBirthDate?.toIso8601String(),
      'babyConceptionDate': babyConceptionDate?.toIso8601String(),
      'babyCoverImagePath': babyCoverImagePath,
      'videoCompressionThreshold': videoCompressionThreshold,
      'webdavMirrors': webdavMirrors.map((m) => m.toJson()).toList(),
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      id: json['id'] ?? const Uuid().v4(),
      webdavUrl: json['webdavUrl'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      babyName: json['babyName'] ?? json['childName'] ?? '', // 向后兼容
      babyBirthDate: json['babyBirthDate'] != null
          ? DateTime.parse(json['babyBirthDate'])
          : (json['childBirthDate'] != null
              ? DateTime.parse(json['childBirthDate'])
              : null),
      babyConceptionDate: json['babyConceptionDate'] != null
          ? DateTime.parse(json['babyConceptionDate'])
          : (json['conceptionDate'] != null
              ? DateTime.parse(json['conceptionDate'])
              : null),
      babyCoverImagePath: json['babyCoverImagePath'],
      videoCompressionThreshold: json['videoCompressionThreshold'] ?? 10,
      webdavMirrors: (json['webdavMirrors'] as List<dynamic>?)
              ?.map((e) => WebDavMirror.fromJson(e))
              .toList() ??
          [],
    );
  }
}
