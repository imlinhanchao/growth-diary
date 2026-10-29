import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../models/app_config.dart';
import '../services/local_storage_service.dart';
import '../services/tv_pairing_service.dart';

class QRScannerScreen extends StatefulWidget {
  /// 可选：当前手机正在使用的配置（用于投送到电视）
  final AppConfig? currentConfig;

  const QRScannerScreen({super.key, this.currentConfig});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  bool _isScanning = true;
  final ImagePicker _picker = ImagePicker();
  AppConfig? _loadedConfig;

  @override
  void initState() {
    super.initState();
    _loadedConfig = widget.currentConfig;
    if (_loadedConfig == null) {
      _loadDefaultConfig();
    }
  }

  Future<void> _loadDefaultConfig() async {
    final storage = LocalStorageService();
    final configs = await storage.loadAllConfigs();
    final currentId = await storage.getCurrentConfigId();
    if (configs.isNotEmpty && mounted) {
      setState(() {
        _loadedConfig = configs[currentId] ?? configs.values.first;
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(String rawValue) async {
    // 检查是否是电视配对二维码
    final pairingInfo = TvPairingInfo.tryParse(rawValue);
    if (pairingInfo != null) {
      await _handleTvPairing(pairingInfo);
      return;
    }

    // 默认行为：返回扫码文本供调用方解析
    if (mounted) {
      Navigator.pop(context, rawValue);
    }
  }

  /// 处理电视投送配对
  Future<void> _handleTvPairing(TvPairingInfo pairingInfo) async {
    if (_loadedConfig == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前手机暂无可用配置可投送到电视')),
        );
        setState(() => _isScanning = true);
      }
      return;
    }

    // 弹出确认投送对话框
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.tv, color: Colors.pink.shade400),
            const SizedBox(width: 8),
            const Text('投送配置到电视'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('目标设备: ${pairingInfo.deviceName}'),
            Text('设备IP: ${pairingInfo.ip}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '宝宝昵称: ${_loadedConfig!.babyName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'WebDAV: ${_loadedConfig!.webdavUrl}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '确定将此配置直接发送至电视端吗？',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即投送'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在投送配置到电视...')),
      );

      final success = await TvPairingClient.sendConfigToTv(
        pairingInfo: pairingInfo,
        config: _loadedConfig!,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 投送成功！电视端已自动完成初始设置'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // 投送成功，关闭扫码页
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('投送失败，请确保手机与电视连接在同一 Wi-Fi 下'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isScanning = true);
        }
      }
    } else {
      setState(() => _isScanning = true);
    }
  }

  Future<void> _scanFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final capture = await controller.analyzeImage(image.path);
        if (capture != null &&
            capture.barcodes.isNotEmpty &&
            capture.barcodes.first.rawValue != null) {
          _handleBarcode(capture.barcodes.first.rawValue!);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('未检测到二维码')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码导入 / 投送电视'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: _scanFromGallery,
            tooltip: '从相册选择',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_isScanning) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                  _isScanning = false;
                  _handleBarcode(barcodes.first.rawValue!);
                }
              }
            },
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '对准日记二维码导入配置，或对准电视二维码一键投送',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
