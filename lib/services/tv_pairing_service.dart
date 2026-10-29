import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import 'qr_service.dart';

/// 电视局域网配对数据包模型
class TvPairingInfo {
  final String ip;
  final int port;
  final String token;
  final String deviceName;

  TvPairingInfo({
    required this.ip,
    required this.port,
    required this.token,
    this.deviceName = 'Android TV',
  });

  /// 转换为用于生成二维码的字符串
  String toQrString() {
    return jsonEncode({
      'type': 'growth_diary_pair',
      'ip': ip,
      'port': port,
      'token': token,
      'device': deviceName,
      'version': '1.0',
    });
  }

  /// 尝试从扫码字符串中解析配对信息
  static TvPairingInfo? tryParse(String rawData) {
    try {
      final json = jsonDecode(rawData);
      if (json is Map && json['type'] == 'growth_diary_pair') {
        final ip = json['ip'] as String?;
        final port = json['port'] as int?;
        final token = json['token'] as String?;
        final device = json['device'] as String? ?? 'Android TV';

        if (ip != null && port != null && token != null) {
          return TvPairingInfo(
            ip: ip,
            port: port,
            token: token,
            deviceName: device,
          );
        }
      }
    } catch (_) {
      // 不是合法的配对 JSON
    }
    return null;
  }
}

/// 电视端局域网配对服务器
///
/// 电视端运行此服务等待手机 App 发送配置
class TvPairingServer {
  HttpServer? _server;
  String? _token;
  int? _port;
  String? _ip;

  bool get isRunning => _server != null;
  String? get ip => _ip;
  int? get port => _port;
  String? get token => _token;

  /// 获取本机的局域网 IPv4 地址
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      // 优先寻找 Wi-Fi 或以太网接口 (wlan, eth)
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('eth') || name.contains('en')) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // 如果没匹配到常见名字，取第一个非回环的 IPv4
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('获取本机 IP 失败: $e');
    }
    return null;
  }

  /// 启动配对服务
  /// [onConfigReceived] 当收到手机发来的配置时回调
  Future<TvPairingInfo?> start({
    required void Function(AppConfig config) onConfigReceived,
  }) async {
    await stop();

    final localIp = await getLocalIp();
    if (localIp == null) {
      debugPrint('无法获取本机局域网 IP 地址');
      return null;
    }

    // 生成随机 8 位 Token
    final rand = Random();
    final token = List.generate(8, (_) => rand.nextInt(10)).join();

    try {
      // 绑定任意端口 (port = 0 代表由系统分配空闲端口)
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );

      _server = server;
      _ip = localIp;
      _port = server.port;
      _token = token;

      server.listen((HttpRequest request) async {
        // 设置跨域头
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        if (request.uri.path == '/pair' && request.method == 'POST') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;

            final reqToken = json['token'] as String?;
            final encryptedConfig = json['config'] as String?;

            if (reqToken == _token && encryptedConfig != null) {
              final config = QRService.decodeEncryptedQRData(encryptedConfig);
              if (config != null) {
                // 响应成功
                request.response.statusCode = HttpStatus.ok;
                request.response.headers.contentType = ContentType.json;
                request.response.write(jsonEncode({'success': true}));
                await request.response.close();

                // 回调通知外部
                onConfigReceived(config);
                return;
              }
            }

            request.response.statusCode = HttpStatus.badRequest;
            request.response.write(jsonEncode({'error': '无效的配置数据或口令不匹配'}));
            await request.response.close();
          } catch (e) {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write(jsonEncode({'error': e.toString()}));
            await request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });

      return TvPairingInfo(
        ip: localIp,
        port: server.port,
        token: token,
        deviceName: 'Android TV',
      );
    } catch (e) {
      debugPrint('启动配对服务器失败: $e');
      await stop();
      return null;
    }
  }

  /// 停止配对服务
  Future<void> stop() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _token = null;
    _port = null;
    _ip = null;
  }
}

/// 手机客户端发送配置的工具方法
class TvPairingClient {
  /// 手机将 AppConfig 推送到指定电视
  static Future<bool> sendConfigToTv({
    required TvPairingInfo pairingInfo,
    required AppConfig config,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    try {
      final url = Uri.parse('http://${pairingInfo.ip}:${pairingInfo.port}/pair');
      final request = await client.postUrl(url);

      request.headers.contentType = ContentType.json;

      final encryptedConfig = QRService.generateEncryptedQRData(config);
      final body = jsonEncode({
        'token': pairingInfo.token,
        'config': encryptedConfig,
      });

      request.write(body);
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final respStr = await utf8.decoder.bind(response).join();
        final json = jsonDecode(respStr);
        return json['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('推送配置到电视失败: $e');
      return false;
    } finally {
      client.close();
    }
  }
}
