import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:flutter_video_info/flutter_video_info.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:video_compress/video_compress.dart';

enum MediaType {
  image,
  video,
}

enum UploadStatus {
  pending, // 等待上传
  compressing, // 压缩中
  uploading, // 正在上传
  completed, // 上传完成
  failed, // 上传失败
  paused, // 已暂停
}

class MediaFile {
  String srcPath;
  Uint8List? thumbPathSmall;
  Uint8List? thumbPathMedium;
  String? uploadPath;
  DateTime? createdAt;
  MediaType type;
  bool isCompressed = false;
  String? description;
  MediaFile({
    required this.srcPath,
    this.type = MediaType.image,
    this.thumbPathSmall,
    this.thumbPathMedium,
    this.uploadPath,
    this.createdAt,
  });
}

/// 文件选择工具类
class FileUtils {
  static final ImagePicker _picker = ImagePicker();

  /// 选择图片文件
  /// 返回选中的图片文件对象数组
  static Future<List<MediaFile>> selectImages({
    ImageSource source = ImageSource.gallery,
    bool allowMultiple = true,
  }) async {
    try {
      if (allowMultiple) {
        final List<XFile> images = await _picker.pickMultiImage();
        return images
            .map((image) => MediaFile(
                  srcPath: image.path,
                  type: MediaType.image,
                ))
            .toList();
      } else {
        final XFile? image = await _picker.pickImage(source: source);
        return image != null
            ? [
                MediaFile(
                  srcPath: image.path,
                  type: MediaType.image,
                )
              ]
            : [];
      }
    } catch (e) {
      print('选择图片失败: $e');
      return [];
    }
  }

  /// 选择视频文件
  /// 返回选中的视频文件对象数组
  static Future<List<MediaFile>> selectVideos({
    ImageSource source = ImageSource.gallery,
    bool allowMultiple = true,
  }) async {
    try {
      if (allowMultiple) {
        var result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );
        if (result != null) {
          return result.files
              .map((file) => MediaFile(
                    srcPath: file.path!,
                    type: MediaType.video,
                  ))
              .toList();
        } else {
          return [];
        }
      } else {
        final XFile? video = await _picker.pickVideo(source: source);
        return video != null
            ? [
                MediaFile(
                  srcPath: video.path,
                  type: MediaType.video,
                )
              ]
            : [];
      }
    } catch (e) {
      print('选择视频失败: $e');
      return [];
    }
  }

  /// 从相机拍摄照片
  static Future<List<MediaFile>> takePhoto() async {
    return await selectImages(source: ImageSource.camera, allowMultiple: false);
  }

  /// 从相机录制视频
  static Future<List<MediaFile>> recordVideo() async {
    return await selectVideos(source: ImageSource.camera, allowMultiple: false);
  }

  /// 填充文件的创建日期
  /// 对于图片：从EXIF数据中读取创建日期
  /// 对于视频：使用FlutterVideoInfo获取视频信息
  /// 获取不到则设置为今天
  static Future<void> fillCreationDate(MediaFile mediaFile) async {
    try {
      final file = File(mediaFile.srcPath);

      if (mediaFile.type == MediaType.image) {
        // 处理图片：读取EXIF数据
        final bytes = await file.readAsBytes();
        final exifData = await readExifFromBytes(bytes);

        // 尝试从不同的EXIF字段获取日期
        String? dateStr;
        if (exifData['EXIF DateTimeOriginal'] != null) {
          dateStr = exifData['EXIF DateTimeOriginal'].toString();
        } else if (exifData['Image DateTime'] != null) {
          dateStr = exifData['Image DateTime'].toString();
        }

        if (dateStr != null) {
          final dateTime = _parseExifDate(dateStr);
          if (dateTime != null) {
            mediaFile.createdAt = dateTime;
            return;
          }
        }
      } else if (mediaFile.type == MediaType.video) {
        // 处理视频：使用FlutterVideoInfo
        final videoInfo = FlutterVideoInfo();
        final info = await videoInfo.getVideoInfo(mediaFile.srcPath);

        if (info != null && info.date != null) {
          // FlutterVideoInfo 返回的 date 可能是字符串或 DateTime
          if (info.date is DateTime) {
            mediaFile.createdAt = (info.date as DateTime);
          } else if (info.date is String) {
            // 如果是字符串，尝试解析或直接使用
            mediaFile.createdAt = _parseExifDate(info.date ?? '');
          }
          return;
        }
      }

      // 如果获取不到日期，使用文件修改时间或今天
      final stat = await file.stat();
      final dateTime = stat.modified;
      mediaFile.createdAt = dateTime;
    } catch (e) {
      print('获取文件创建日期失败: $e，使用今天日期');
      // 获取失败，使用今天日期
      final now = DateTime.now();
      mediaFile.createdAt = now;
    }
  }

  /// 填充文件的缩略图
  /// 生成中等尺寸(768px)和小尺寸(400px)的缩略图
  static Future<void> fillThumbnail(MediaFile mediaFile) async {
    try {
      // 生成中等尺寸缩略图 (768px)
      final mediumThumbnail = await generateThumbnail(
        mediaFile.srcPath,
        mediaFile.type,
        size: 768,
      );
      mediaFile.thumbPathMedium = mediumThumbnail;

      // 生成小尺寸缩略图 (400px)
      final smallThumbnail = await generateThumbnail(
        mediaFile.srcPath,
        mediaFile.type,
        size: 400,
      );
      mediaFile.thumbPathSmall = smallThumbnail;
    } catch (e) {
      print('填充缩略图失败: $e');
      // 失败时保持 null 值
    }
  }

  /// 根据文件内容生成唯一文件名
  static String generateFileName(File file, FileStat stat) {
    final extension = path.extension(file.path);
    final isLargeVideo = stat.size > 4 * 1024 * 1024; // 4MB

    Digest hash;

    if (isLargeVideo) {
      // 对于大视频，只读取前1MB内容 + 文件大小
      final fileStream = file.openSync(mode: FileMode.read);
      final buffer = Uint8List(1024 * 1024); // 1MB buffer
      final bytesRead = fileStream.readIntoSync(buffer);
      fileStream.closeSync();

      final prefix =
          bytesRead < buffer.length ? buffer.sublist(0, bytesRead) : buffer;
      final sizeStr = stat.size.toString();
      final combined = prefix + sizeStr.codeUnits;
      hash = sha256.convert(combined);
    } else {
      // 对于其他文件，使用整个文件的SHA256
      final bytes = file.readAsBytesSync();
      hash = sha256.convert(bytes);
    }

    return '${hash.toString()}$extension';
  }

  /// 压缩视频文件
  static Future<File?> compressVideo(String videoPath) async {
    try {
      final info = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false, // 不删除原文件
      );
      return info?.file;
    } catch (e) {
      debugPrint('Video compression failed: $e');
      return null;
    }
  }

  /// 生成缩略图
  /// [filePath] 文件路径
  /// [type] 媒体类型
  /// [size] 缩略图尺寸（正方形边长）
  /// 返回 Uint8List 格式的缩略图数据
  static Future<Uint8List?> generateThumbnail(
    String filePath,
    MediaType type, {
    int size = 200,
  }) async {
    try {
      if (type == MediaType.image) {
        return await _generateImageThumbnail(filePath, size);
      } else if (type == MediaType.video) {
        return await _generateVideoThumbnail(filePath, size);
      }
      return null;
    } catch (e) {
      print('生成缩略图失败: $e');
      return null;
    }
  }

  /// 生成图片缩略图
  static Future<Uint8List?> _generateImageThumbnail(
      String filePath, int size) async {
    try {
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        filePath,
        minWidth: size,
        minHeight: size,
        quality: 85,
        format: CompressFormat.jpeg,
      );

      return compressedBytes;
    } catch (e) {
      print('生成图片缩略图失败: $e');
      return null;
    }
  }

  /// 生成视频缩略图
  static Future<Uint8List?> _generateVideoThumbnail(
      String filePath, int size) async {
    try {
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: filePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: size,
        maxHeight: size,
        quality: 85,
        timeMs: 1000, // 从第1秒开始截取
      );

      return thumbnailBytes;
    } catch (e) {
      print('生成视频缩略图失败: $e');
      return null;
    }
  }

  /// 解析EXIF日期字符串
  /// EXIF日期格式：YYYY:MM:DD HH:MM:SS
  static DateTime? _parseExifDate(String dateStr) {
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      try {
        // EXIF格式：YYYY:MM:DD HH:MM:SS
        final parts = dateStr.split(' ');
        if (parts.length != 2) return null;

        final dateParts = parts[0].split(':');
        final timeParts = parts[1].split(':');

        if (dateParts.length != 3 || timeParts.length != 3) return null;

        final year = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day = int.parse(dateParts[2]);
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final second = int.parse(timeParts[2]);

        return DateTime(year, month, day, hour, minute, second);
      } catch (e) {
        print('解析EXIF日期失败: $e');
        return null;
      }
    }
  }
}
