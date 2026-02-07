import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';

class LocalStorageService {
  static const String _configsKey = 'app_configs';
  static const String _currentConfigIdKey = 'current_config_id';

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
