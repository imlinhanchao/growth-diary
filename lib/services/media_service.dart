import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'cloud_storage_service.dart';

/// 媒体服务类，负责媒体文件的分享和下载功能
class MediaService {
  static const String _appFolder = 'Growth Diary';

  /// 分享图片
  static Future<bool> shareImage({
    required String imagePath,
    required Uint8List imageData,
    required CloudStorageService cloudService,
  }) async {
    try {
      final tempFile = await cloudService.saveToTempFile(imagePath, imageData);
      if (tempFile != null) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(tempFile.path)]),
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error sharing image: $e');
      return false;
    }
  }

  /// 分享视频
  static Future<bool> shareVideo({
    required String videoPath,
    required CloudStorageService cloudService,
  }) async {
    try {
      final tempFile = await cloudService.saveToTempFile(videoPath, null);
      if (tempFile != null) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(tempFile.path)]),
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error sharing video: $e');
      return false;
    }
  }

  /// 下载图片
  static Future<DownloadResult> downloadImage({
    required String imagePath,
    required Uint8List imageData,
    required CloudStorageService cloudService,
  }) async {
    try {
      final tempFilePath = await _saveImageToTempFile(imageData);

      if (Platform.isAndroid) {
        // Android使用MediaStore
        await MediaStore.ensureInitialized();
        final mediaStore = MediaStore();

        // 设置应用文件夹为 Growth Diary
        MediaStore.appFolder = _appFolder;

        // 保存图片到下载目录的 Growth Diary 文件夹
        final result = await mediaStore.saveFile(
          tempFilePath: tempFilePath,
          dirType: DirType.download,
          dirName: DirName.download,
        );

        if (result != null) {
          return const DownloadResult(
            success: true,
            message: '图片已保存到下载目录: Growth Diary文件夹',
          );
        }
      } else if (Platform.isIOS) {
        // iOS使用PhotoManager保存到相册，先请求权限
        final permission = await PhotoManager.requestPermissionExtend();
        if (permission.isAuth) {
          await PhotoManager.editor.saveImage(
            imageData,
            filename:
                'growth_diary_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
            title: 'Growth Diary Image',
          );
          return const DownloadResult(
            success: true,
            message: '图片已保存到相册',
          );
        } else {
          return const DownloadResult(
            success: false,
            message: '需要相册权限才能保存图片',
          );
        }
      }

      return const DownloadResult(
        success: false,
        message: '保存失败',
      );
    } catch (e) {
      debugPrint('Error downloading image: $e');
      return const DownloadResult(
        success: false,
        message: '保存图片失败，请检查存储权限',
      );
    }
  }

  /// 下载视频
  static Future<DownloadResult> downloadVideo({
    required String videoPath,
    required CloudStorageService cloudService,
  }) async {
    try {
      final videoData = await cloudService.downloadFile(videoPath);
      if (videoData == null) {
        return const DownloadResult(
          success: false,
          message: '下载视频数据失败',
        );
      }

      final tempFilePath = await _saveVideoToTempFile(videoData);

      if (Platform.isAndroid) {
        // Android使用MediaStore
        await MediaStore.ensureInitialized();
        final mediaStore = MediaStore();

        // 设置应用文件夹为 Growth Diary
        MediaStore.appFolder = _appFolder;

        // 保存视频到下载目录的 Growth Diary 文件夹
        final result = await mediaStore.saveFile(
          tempFilePath: tempFilePath,
          dirType: DirType.download,
          dirName: DirName.download,
        );

        if (result != null) {
          return const DownloadResult(
            success: true,
            message: '视频已保存到下载目录: Growth Diary文件夹',
          );
        }
      } else if (Platform.isIOS) {
        // iOS使用PhotoManager保存到相册，先请求权限
        final permission = await PhotoManager.requestPermissionExtend();
        if (permission.isAuth) {
          await PhotoManager.editor.saveVideo(
            File(tempFilePath),
            title: 'Growth Diary Video',
          );
          return const DownloadResult(
            success: true,
            message: '视频已保存到相册',
          );
        } else {
          return const DownloadResult(
            success: false,
            message: '需要相册权限才能保存视频',
          );
        }
      }

      return const DownloadResult(
        success: false,
        message: '保存失败',
      );
    } catch (e) {
      debugPrint('Error downloading video: $e');
      return const DownloadResult(
        success: false,
        message: '保存视频失败，请检查存储权限',
      );
    }
  }

  /// 保存图片到临时文件
  static Future<String> _saveImageToTempFile(Uint8List data) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_image.jpg');
    await tempFile.writeAsBytes(data);
    return tempFile.path;
  }

  /// 保存视频到临时文件
  static Future<String> _saveVideoToTempFile(Uint8List data) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_video.mp4');
    await tempFile.writeAsBytes(data);
    return tempFile.path;
  }
}

/// 下载结果类
class DownloadResult {
  final bool success;
  final String message;

  const DownloadResult({
    required this.success,
    required this.message,
  });
}
