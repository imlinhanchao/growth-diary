import 'package:flutter/material.dart';

/// 设备形态枚举
enum DeviceFormFactor { phone, tablet, tv }

/// 设备类型检测工具类
///
/// 使用方式：
/// ```dart
/// if (DeviceType.isTablet(context)) { ... }
/// final cols = DeviceType.gridColumns(context);
/// ```
class DeviceType {
  /// 判断设备类型
  static DeviceFormFactor of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortestSide = size.shortestSide;

    // Android TV / 大屏设备：最短边 >= 540 且最长边 >= 960
    if (shortestSide >= 540 && size.longestSide >= 960) {
      // 进一步区分 TV（极宽）和平板
      if (size.width >= 1200 && size.height <= 800) {
        return DeviceFormFactor.tv;
      }
      return DeviceFormFactor.tablet;
    }

    if (shortestSide >= 600) return DeviceFormFactor.tablet;

    return DeviceFormFactor.phone;
  }

  /// 是否为平板（含 TV）
  static bool isTablet(BuildContext context) {
    final f = of(context);
    return f == DeviceFormFactor.tablet || f == DeviceFormFactor.tv;
  }

  /// 是否为 TV
  static bool isTV(BuildContext context) {
    return of(context) == DeviceFormFactor.tv;
  }

  /// 是否为手机
  static bool isPhone(BuildContext context) {
    return of(context) == DeviceFormFactor.phone;
  }

  /// 是否为大屏（Tablet 或 TV），用于决定是否显示双栏布局
  static bool isWideScreen(BuildContext context) {
    return !isPhone(context);
  }

  /// 主内容区最大宽度（用于居中约束）
  static double maxContentWidth(BuildContext context) {
    switch (of(context)) {
      case DeviceFormFactor.tv:
        return 1100;
      case DeviceFormFactor.tablet:
        return 860;
      case DeviceFormFactor.phone:
        return double.infinity;
    }
  }

  /// 时间轴列表宽度（双栏布局时左侧宽度）
  static double timelineColumnWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (isTablet(context)) {
      // 平板横屏：左侧占 40%，最小 360，最大 460
      final w = screenWidth * 0.4;
      return w.clamp(360.0, 460.0);
    }
    return screenWidth;
  }

  /// 媒体网格列数
  static int gridColumns(BuildContext context) {
    switch (of(context)) {
      case DeviceFormFactor.tv:
        return 5;
      case DeviceFormFactor.tablet:
        return 4;
      case DeviceFormFactor.phone:
        return 3;
    }
  }

  /// 详情页图片网格列数
  static int detailImageColumns(BuildContext context) {
    if (isTablet(context)) return 3;
    return 2;
  }

  /// 对话框最大宽度
  static double dialogMaxWidth(BuildContext context) {
    if (isTablet(context)) return 520;
    return double.infinity;
  }
}
