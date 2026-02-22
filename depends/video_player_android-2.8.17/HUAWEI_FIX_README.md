# 华为麒麟设备 Video Player 兼容性修复说明

## 问题描述
华为麒麟芯片（包括 HarmonyOS 设备）上，ExoPlayer 播放 H.264 MP4 视频时可能失败。

## 原因分析
1. **HarmonyOS MediaCodec 兼容性问题**：HarmonyOS 对 Android MediaCodec API 实现不完全兼容
2. **硬件解码器驱动问题**：麒麟芯片硬件解码器与 ExoPlayer 适配不完善
3. **Media3 版本问题**：1.5.x 系列在华为设备上有已知 bug

## 修复内容

### 1. 升级 Media3 版本（推荐）
- **修改文件**：`android/build.gradle`
- **版本变更**：`1.5.1` → `1.6.0`
- **原因**：1.6.0 包含华为设备兼容性修复

### 2. 添加软解码器回退机制
- **修改文件**：
  - `android/src/main/java/io/flutter/plugins/videoplayer/texture/TextureVideoPlayer.java`
  - `android/src/main/java/io/flutter/plugins/videoplayer/platformview/PlatformViewVideoPlayer.java`
  
- **主要逻辑**：
  ```java
  // 检测华为设备
  private static boolean isHuaweiDevice() {
    String manufacturer = Build.MANUFACTURER.toLowerCase();
    String brand = Build.BRAND.toLowerCase();
    return manufacturer.contains("huawei") || 
           brand.contains("huawei") || 
           manufacturer.contains("honor") || 
           brand.contains("honor");
  }
  
  // 华为设备启用软解码器回退
  if (isHuaweiDevice()) {
    builder.setRenderersFactory(
        new DefaultRenderersFactory(context)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true));
  }
  ```

## 使用方法

### 步骤 1：在主项目 pubspec.yaml 中添加本地依赖覆盖

```yaml
dependency_overrides:
  video_player_android:
    path: ./video_player_android-2.8.17
```

### 步骤 2：清理并重新构建

```bash
cd /Users/iwpz/Documents/GitHub/eCommerceFlutter
flutter clean
flutter pub get
flutter build apk --release
```

### 步骤 3：在华为设备上测试

测试设备建议：
- 华为 Mate 系列（麒麟 9000s/990/980）
- 华为 P 系列
- 荣耀设备
- HarmonyOS 2.0+ 设备

## 性能说明

- **硬件解码（默认）**：高性能，低功耗
- **软解码（回退）**：兼容性最高，性能略低，功耗略高
- **本修复方案**：华为设备自动启用软解码回退，其他设备仍使用硬解码

## 其他解决方案（如修复无效）

### 方案 A：强制全局软解码（兼容性最高）
```java
// 所有设备都用软解码
builder.setRenderersFactory(
    new DefaultRenderersFactory(context)
        .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON));
```

### 方案 B：使用华为 HMS VideoKit（仅华为设备）
参考：https://developer.huawei.com/consumer/cn/hms/huawei-videokit/

### 方案 C：降级到 Media3 1.4.x
```gradle
def exoplayer_version = "1.4.1"
```

## 已知问题

- 软解码模式下，4K 视频可能卡顿
- HarmonyOS NEXT（纯鸿蒙）兼容性未验证

## 技术支持

如遇到其他问题，请提供：
1. 设备型号 + HarmonyOS 版本
2. 视频编码格式（ffprobe 输出）
3. Logcat 错误日志
