import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiDetectionResult {
  final String? ssid;
  final bool hasPermission;
  final bool isLocationServiceEnabled;
  final bool isPermanentlyDenied;

  const WifiDetectionResult({
    this.ssid,
    required this.hasPermission,
    required this.isLocationServiceEnabled,
    this.isPermanentlyDenied = false,
  });
}

class NetworkService {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// 检查是否有获取 WiFi 信息的权限（位置权限）
  static Future<bool> hasLocationPermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.location.status;
      return status.isGranted;
    }
    return true;
  }

  /// 请求位置权限
  static Future<PermissionStatus> requestLocationPermission() async {
    if (kIsWeb) return PermissionStatus.granted;
    if (Platform.isAndroid || Platform.isIOS) {
      return await Permission.location.request();
    }
    return PermissionStatus.granted;
  }

  /// 检查系统定位开关 (GPS) 是否已开启
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid || Platform.isIOS) {
      return await Permission.location.serviceStatus.isEnabled;
    }
    return true;
  }

  /// 打开系统设置
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// 获取详细的 WiFi 状态检测结果
  static Future<WifiDetectionResult> getWifiStatus({bool requestPermission = false}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      final rawSsid = await _networkInfo.getWifiName();
      return WifiDetectionResult(
        ssid: cleanWifiSSID(rawSsid),
        hasPermission: true,
        isLocationServiceEnabled: true,
      );
    }

    var permStatus = await Permission.location.status;
    if (!permStatus.isGranted && requestPermission) {
      permStatus = await Permission.location.request();
    }

    final hasPerm = permStatus.isGranted;
    final isPermDeniedForever = permStatus.isPermanentlyDenied;
    final isLocEnabled = await isLocationServiceEnabled();

    String? ssid;
    if (hasPerm) {
      try {
        final rawSsid = await _networkInfo.getWifiName();
        ssid = cleanWifiSSID(rawSsid);
      } catch (e) {
        debugPrint('获取当前 WiFi SSID 异常: $e');
      }
    }

    return WifiDetectionResult(
      ssid: ssid,
      hasPermission: hasPerm,
      isLocationServiceEnabled: isLocEnabled,
      isPermanentlyDenied: isPermDeniedForever,
    );
  }

  /// 获取当前连接的 WiFi 名称 (SSID)
  static Future<String?> getCurrentWifiSSID({bool requestPermission = false}) async {
    final result = await getWifiStatus(requestPermission: requestPermission);
    return result.ssid;
  }

  /// 规范化并清理 SSID（去除两端引号、过滤未知占位符）
  static String? cleanWifiSSID(String? ssid) {
    if (ssid == null) return null;
    var clean = ssid.trim();

    // 某些平台（如 iOS/Android）会返回包含双引号的 SSID，例如 "MyHomeWiFi"
    if (clean.startsWith('"') && clean.endsWith('"') && clean.length >= 2) {
      clean = clean.substring(1, clean.length - 1).trim();
    }

    // 过滤 Android/iOS 未知网络或者未授权时的特殊占位符
    if (clean.isEmpty ||
        clean == '"' ||
        clean == '<unknown ssid>' ||
        clean.toLowerCase() == 'unknown' ||
        clean == '0x') {
      return null;
    }

    return clean;
  }
}
