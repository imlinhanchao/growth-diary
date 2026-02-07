import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import '../models/app_config.dart';
import '../services/cloud_storage_service.dart';
import '../services/local_storage_service.dart';
import '../services/qr_service.dart';
import 'setup_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  final AppConfig config;
  final CloudStorageService cloudService;
  final Function(AppConfig) onConfigChanged;

  const AppSettingsScreen({
    super.key,
    required this.config,
    required this.cloudService,
    required this.onConfigChanged,
  });

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final LocalStorageService _localStorage = LocalStorageService();
  final ScreenshotController _screenshotController = ScreenshotController();
  late AppConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
  }

  Future<void> _showQRCode() async {
    // 使用QRService生成加密的二维码数据
    final qrData = QRService.generateEncryptedQRData(_config);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Screenshot(
              controller: _screenshotController,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Decorative element
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.pink.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: SvgPicture.asset(
                        'assets/images/logo.svg',
                        height: 48,
                        width: 48,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFFE91E63), // Pink
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      '${_config.babyName}的成长日记',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE91E63),
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '扫一扫，同步这份美好',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // QR Code with border
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.pink.shade100,
                          width: 2,
                        ),
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200.0,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        // Add some style to QR dots if possible or keep simple
                        dataModuleStyle:
                            const QrDataModuleStyle(color: Color(0xFFE91E63)),
                        eyeStyle: const QrEyeStyle(color: Color(0xFFE91E63)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Footer text
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.pink.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '配置信息已加密处理',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFAD1457),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton(
                  icon: Icons.close_rounded,
                  label: '关闭',
                  onTap: () => Navigator.of(context).pop(),
                  color: Colors.white,
                  textColor: Colors.white,
                  isOutlined: true,
                ),
                const SizedBox(width: 20),
                _buildActionButton(
                  icon: Icons.share_rounded,
                  label: '分享',
                  onTap: () async {
                    // Capture and share
                    final image = await _screenshotController.capture();
                    if (image != null && mounted) {
                      final directory = await getTemporaryDirectory();
                      final imagePath = '${directory.path}/qr_code.png';
                      final imageFile = File(imagePath);
                      await imageFile.writeAsBytes(image);

                      await SharePlus.instance.share(ShareParams(
                        files: [XFile(imagePath)],
                        text: '扫描二维码导入${_config.babyName}的成长日记配置',
                      ));
                    }
                  },
                  color: Colors.white,
                  textColor: Colors.pink,
                  isOutlined: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required Color textColor,
    required bool isOutlined,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: isOutlined ? Colors.white.withValues(alpha: 0.2) : color,
            borderRadius: BorderRadius.circular(30),
            border:
                isOutlined ? Border.all(color: Colors.white, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: isOutlined ? Colors.white : textColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isOutlined ? Colors.white : textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('这将删除所有已缓存的媒体文件。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // 显示loading对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在清除缓存...'),
            ],
          ),
        ),
      );

      try {
        await widget.cloudService.clearCache();

        // 关闭loading对话框
        if (mounted) {
          Navigator.of(context).pop(); // 关闭loading对话框

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('缓存已清除')),
          );
        }
      } catch (e) {
        // 关闭loading对话框
        if (mounted) {
          Navigator.of(context).pop(); // 关闭loading对话框

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清除缓存失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('挥手告别'),
        content: const Text('这将清除当前宝宝的本地配置，线上文件仍然保留。确定要和宝宝说再见吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('挥手告别'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 删除当前配置
      await _localStorage.deleteConfig(_config.id);

      // 检查是否还有其他配置
      final remainingConfigs = await _localStorage.loadAllConfigs();

      if (remainingConfigs.isNotEmpty) {
        // deleteConfig已经设置了第一个配置为当前配置，这里不需要再设置
        // 通知父组件配置已更改（会重新加载所有配置）
        widget.onConfigChanged(remainingConfigs.values.first);

        // 返回首页，会自动切换到第一个宝宝
        if (mounted) {
          Navigator.of(context).pop(); // 返回首页
        }
      } else {
        // 如果没有配置了，返回初始化界面
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const SetupScreen(),
            ),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title:
            const Text('应用设置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSection('数据管理'),
          _buildSettingsGroup([
            _buildSettingsTile(
              icon: Icons.qr_code_2,
              title: '导出配置二维码',
              subtitle: '生成包含宝宝配置信息的二维码',
              onTap: _showQRCode,
              iconColor: Colors.blue,
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: '清除缓存',
              subtitle: '清除已下载的媒体文件缓存',
              onTap: _clearCache,
              iconColor: Colors.orange,
            ),
          ]),
          _buildSection('账户管理'),
          _buildSettingsGroup([
            _buildSettingsTile(
              icon: Icons.waving_hand_outlined,
              title: '挥手告别',
              subtitle: '清除当前宝宝的本地配置',
              onTap: _logout,
              iconColor: Colors.red,
              textColor: Colors.red.shade700,
              showTrailing: false,
              backgroundColor: Colors.red.shade50,
            ),
          ]),
          const SizedBox(height: 48),
          Center(
            child: Text(
              '成长日记 v1.0.0',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color iconColor = Colors.grey,
    Color? textColor,
    bool showTrailing = true,
    Color? backgroundColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: backgroundColor ?? iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: textColor ?? Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showTrailing)
                Icon(Icons.chevron_right, color: Colors.grey[300], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
        height: 1, thickness: 0.5, indent: 64, color: Colors.grey[100]);
  }
}
