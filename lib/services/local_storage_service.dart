import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_config.dart';

class LocalStorageService {
  static const String _configsKey = 'app_configs';
  static const String _currentConfigIdKey = 'current_config_id';
  static const String _deviceIdKey = 'device_id';
  static const String _mediaCacheLimitKey = 'media_cache_limit_mb';

  /// 媒体缓存默认上限（MB），0 表示不限制
  static const int defaultMediaCacheLimitMb = 500;

  Future<void> saveConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final configs = await loadAllConfigs();
    configs[config.id] = config;
    await prefs.setString(_configsKey,
        jsonEncode(configs.map((key, value) => MapEntry(key, value.toJson()))));
  }

  Future<void> saveAllConfigs(Map<String, AppConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configsKey,
        jsonEncode(configs.map((key, value) => MapEntry(key, value.toJson()))));
  }

  Future<Map<String, AppConfig>> loadAllConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsString = prefs.getString(_configsKey);
    if (configsString != null) {
      final configsJson = jsonDecode(configsString) as Map<String, dynamic>;
      return configsJson
          .map((key, value) => MapEntry(key, AppConfig.fromJson(value)));
    }
    return {};
  }

  Future<AppConfig?> loadConfig([String? configId]) async {
    final configs = await loadAllConfigs();
    if (configId != null) {
      return configs[configId];
    }
    // 如果没有指定ID，返回当前配置
    final currentId = await getCurrentConfigId();
    return currentId != null ? configs[currentId] : null;
  }

  Future<void> setCurrentConfigId(String configId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentConfigIdKey, configId);
  }

  Future<String?> getCurrentConfigId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentConfigIdKey);
  }

  Future<void> deleteConfig(String configId) async {
    final prefs = await SharedPreferences.getInstance();
    final configs = await loadAllConfigs();
    configs.remove(configId);
    await prefs.setString(_configsKey,
        jsonEncode(configs.map((key, value) => MapEntry(key, value.toJson()))));

    // 如果删除的是当前配置，选择第一个可用的配置
    final currentId = await getCurrentConfigId();
    if (currentId == configId && configs.isNotEmpty) {
      await setCurrentConfigId(configs.keys.first);
    }
  }

  /// 设备唯一标识，用于冲突裁决时区分写入方。每次安装生成一次。
  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  Future<int> getMediaCacheLimitMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_mediaCacheLimitKey) ?? defaultMediaCacheLimitMb;
  }

  Future<void> setMediaCacheLimitMb(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_mediaCacheLimitKey, mb);
  }

  Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
