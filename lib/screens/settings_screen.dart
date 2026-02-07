import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../services/cloud_storage_service.dart';
import '../services/local_storage_service.dart';
import 'webdav_config_screen.dart';
import 'app_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppConfig config;
  final CloudStorageService cloudService;
  final Function(AppConfig) onConfigChanged;

  const SettingsScreen({
    super.key,
    required this.config,
    required this.cloudService,
    required this.onConfigChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalStorageService _localStorage = LocalStorageService();
  late AppConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.pink.shade700,
        ),
      ),
    );
  }

  Future<void> _showEditChildNameDialog() async {
    String newName = _config.babyName;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改宝宝昵称'),
        content: TextField(
          controller: TextEditingController(text: newName),
          onChanged: (value) => newName = value,
          decoration: const InputDecoration(hintText: '请输入宝宝昵称'),
        ),
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
    if (result == true && newName.isNotEmpty) {
      final updatedConfig = _config.copyWith(babyName: newName);
      setState(() {
        _config = updatedConfig;
      });
      await _localStorage.saveConfig(_config);
      await widget.cloudService.saveConfig(_config);
      widget.onConfigChanged(_config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('宝宝昵称已更新')),
        );
      }
    }
  }

  Future<void> _editBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _config.babyBirthDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final updatedConfig = _config.copyWith(babyBirthDate: picked);
      setState(() {
        _config = updatedConfig;
      });
      await _localStorage.saveConfig(_config);
      await widget.cloudService.saveConfig(_config);
      widget.onConfigChanged(_config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('宝宝生日已更新')),
        );
      }
    }
  }

  Future<void> _editConceptionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _config.babyConceptionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final updatedConfig = _config.copyWith(babyConceptionDate: picked);
      setState(() {
        _config = updatedConfig;
      });
      await _localStorage.saveConfig(_config);
      await widget.cloudService.saveConfig(_config);
      widget.onConfigChanged(_config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('受孕日已更新')),
        );
      }
    }
  }

  Future<void> _editVideoCompressionThreshold() async {
    int newThreshold = _config.videoCompressionThreshold;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置视频压缩阈值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('当视频文件大小超过此阈值时，将自动压缩。设置为0表示始终不压缩。'),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: newThreshold.toString()),
              keyboardType: TextInputType.number,
              onChanged: (value) =>
                  newThreshold = int.tryParse(value) ?? newThreshold,
              decoration: const InputDecoration(
                hintText: '请输入阈值（MB）',
                suffixText: 'MB',
              ),
            ),
          ],
        ),
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
    if (result == true) {
      final updatedConfig =
          _config.copyWith(videoCompressionThreshold: newThreshold);
      setState(() {
        _config = updatedConfig;
      });
      await _localStorage.saveConfig(_config);
      await widget.cloudService.saveConfig(_config);
      widget.onConfigChanged(_config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频压缩阈值已更新')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        children: [
          _buildSection('宝宝信息'),
          _buildSettingsGroup([
            _buildSettingsTile(
              icon: Icons.baby_changing_station,
              title: '宝宝昵称',
              subtitle: _config.babyName,
              onTap: _showEditChildNameDialog,
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.cake,
              title: '宝宝生日',
              subtitle: _config.babyBirthDate != null
                  ? '${_config.babyBirthDate!.year}-${_config.babyBirthDate!.month.toString().padLeft(2, '0')}-${_config.babyBirthDate!.day.toString().padLeft(2, '0')}'
                  : '未设置',
              onTap: _editBirthDate,
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.pregnant_woman,
              title: '受孕日',
              subtitle: _config.babyConceptionDate != null
                  ? '${_config.babyConceptionDate!.year}-${_config.babyConceptionDate!.month.toString().padLeft(2, '0')}-${_config.babyConceptionDate!.day.toString().padLeft(2, '0')}'
                  : '未设置',
              onTap: _editConceptionDate,
            ),
          ]),
          _buildSection('上传设置'),
          _buildSettingsGroup([
            _buildSettingsTile(
              icon: Icons.video_file,
              title: '视频压缩阈值',
              subtitle: _config.videoCompressionThreshold == 0
                  ? '始终不压缩'
                  : '${_config.videoCompressionThreshold} MB',
              onTap: _editVideoCompressionThreshold,
            ),
          ]),
          _buildSection('云存储配置'),
          _buildSettingsGroup([
            _buildSettingsTile(
              icon: Icons.cloud,
              title: 'WebDAV',
              subtitle: '${_config.webdavUrl} (${_config.username})',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WebDAVConfigScreen(
                      mode: WebDAVConfigMode.settings,
                      config: _config,
                      webdavService: widget.cloudService,
                      onConfigChanged: widget.onConfigChanged,
                    ),
                  ),
                ).then((_) {
                  // 刷新配置
                  setState(() {});
                });
              },
            ),
          ]),
          _buildSection('应用'),
          _buildSettingsGroup([
            _buildSettingsTile(
              icon: Icons.settings_applications,
              title: '应用设置',
              subtitle: '数据管理、缓存清理、账户设置',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AppSettingsScreen(
                      config: _config,
                      cloudService: widget.cloudService,
                      onConfigChanged: widget.onConfigChanged,
                    ),
                  ),
                );
              },
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.info_outline,
              title: '关于',
              subtitle: '成长日记 v1.0.0',
              showTrailing: false,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 00.02),
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
    bool showTrailing = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 00.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]))
          : null,
      trailing: showTrailing
          ? Icon(Icons.chevron_right, color: Colors.grey[400], size: 20)
          : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildDivider() {
    return Divider(
        height: 1, thickness: 0.5, indent: 56, color: Colors.grey[200]);
  }
}
