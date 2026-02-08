import 'dart:convert';
import '../models/app_config.dart';

class QRService {
  // 简单的密钥，用于加密/解密
  static const String _encryptionKey = 'growth_diary_qr_key_2024';

  /// 生成包含完整配置信息的加密二维码数据
  static String generateEncryptedQRData(AppConfig config) {
    final configData = {
      'id': config.id,
      'babyName': config.childName,
      'birthDate': config.childBirthDate?.toIso8601String(),
      'conceptionDate': config.conceptionDate?.toIso8601String(),
      'webdavUrl': config.webdavUrl,
      'username': config.username,
      'password': config.password, // 现在包含密码
      'babyCoverImagePath': config.babyCoverImagePath,
      'videoCompressionThreshold': config.videoCompressionThreshold,
      'webdavMirrors': config.webdavMirrors,
      'version': '1.1', // 更新版本号
      'timestamp': DateTime.now().toIso8601String(), // 生成时间戳
    };

    // 转换为JSON字符串
    final jsonString = jsonEncode(configData);

    // 使用简单的XOR加密
    final encryptedBytes = _xorEncrypt(jsonString, _encryptionKey);

    // 返回Base64编码的加密数据
    return base64Encode(encryptedBytes);
  }

  /// 解码并解密二维码数据，返回AppConfig
  static AppConfig? decodeEncryptedQRData(String qrData) {
    try {
      // Base64解码
      final encryptedBytes = base64Decode(qrData);

      // XOR解密
      final decryptedBytes = _xorDecrypt(encryptedBytes, _encryptionKey);

      // UTF-8解码
      final decryptedJson = utf8.decode(decryptedBytes);

      // 解析JSON
      final configData = jsonDecode(decryptedJson) as Map<String, dynamic>;

      // 验证版本
      final version = configData['version'] as String?;
      if (version != '1.0' && version != '1.1') {
        throw Exception('不支持的二维码版本: $version');
      }

      // 构建AppConfig对象
      return AppConfig(
        id: configData['id'] as String? ?? '',
        babyName: configData['babyName'] as String? ?? '',
        babyBirthDate: configData['birthDate'] != null
            ? DateTime.parse(configData['birthDate'] as String)
            : null,
        babyConceptionDate: configData['conceptionDate'] != null
            ? DateTime.parse(configData['conceptionDate'] as String)
            : null,
        webdavUrl: configData['webdavUrl'] as String? ?? '',
        username: configData['username'] as String? ?? '',
        password: configData['password'] as String? ?? '',
        babyCoverImagePath: configData['babyCoverImagePath'] as String?,
        videoCompressionThreshold:
            configData['videoCompressionThreshold'] as int? ?? 10,
        webdavMirrors: (configData['webdavMirrors'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
    } catch (e) {
      print('解码二维码数据失败: $e');
      return null;
    }
  }

  /// 简单的XOR加密，返回字节数组
  static List<int> _xorEncrypt(String text, String key) {
    final textBytes = utf8.encode(text);
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(textBytes.length, 0);

    for (int i = 0; i < textBytes.length; i++) {
      result[i] = textBytes[i] ^ keyBytes[i % keyBytes.length];
    }

    return result;
  }

  /// XOR解密，返回字节数组
  static List<int> _xorDecrypt(List<int> encryptedBytes, String key) {
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(encryptedBytes.length, 0);

    for (int i = 0; i < encryptedBytes.length; i++) {
      result[i] = encryptedBytes[i] ^ keyBytes[i % keyBytes.length];
    }

    return result;
  }

  /// 验证二维码数据是否有效
  static bool isValidQRData(String qrData) {
    try {
      final config = decodeEncryptedQRData(qrData);
      return config != null && config.childName.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 获取二维码数据的摘要信息（用于显示，不包含敏感信息）
  static Map<String, String> getQRDataSummary(String qrData) {
    final config = decodeEncryptedQRData(qrData);
    if (config == null) {
      return {'error': '无效的二维码数据'};
    }

    return {
      '宝宝昵称': config.childName,
      'WebDAV服务器': config.webdavUrl.isNotEmpty ? config.webdavUrl : '未设置',
      '用户名': config.username.isNotEmpty ? config.username : '未设置',
      'WebDAV镜像数量': config.webdavMirrors.length.toString(),
      '生成时间': '包含在二维码中',
    };
  }
}
