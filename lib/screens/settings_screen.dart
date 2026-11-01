import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../services/cloud_storage_service.dart';
import '../services/local_storage_service.dart';
import '../utils/device_type.dart';
import 'webdav_config_screen.dart';
import 'app_settings_screen.dart';
import 'qr_scanner_screen.dart';
import 'setup_screen.dart';

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
  int _tvSelectedCategory = 0;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.settings ||
          event.logicalKey == LogicalKeyboardKey.contextMenu ||
          event.logicalKey.keyId == 176 ||
          event.logicalKey.keyId == 82) {
        Navigator.maybePop(context);
        return true;
      }
    }
    return false;
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: TextField(
            autofocus: true,
            controller: TextEditingController(text: newName),
            onChanged: (value) => newName = value,
            decoration: const InputDecoration(hintText: '请输入宝宝昵称'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink.shade500,
              foregroundColor: Colors.white,
            ),
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
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('当视频文件大小超过此阈值时，将自动压缩。设置为0表示始终不压缩。'),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink.shade500,
              foregroundColor: Colors.white,
            ),
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
    if (DeviceType.isTV(context)) {
      return _buildTvSettingsLayout(context);
    }
    return _buildPhoneSettingsLayout(context);
  }

  // ──────────────────────────────────────────
  // 电视（Android TV）左右分栏设置布局
  // ──────────────────────────────────────────

  Widget _buildTvSettingsLayout(BuildContext context) {
    final categories = [
      {'icon': Icons.child_care_rounded, 'title': '宝宝信息', 'sub': '昵称、生日与受孕日'},
      {'icon': Icons.cloud_sync_rounded, 'title': '存储与上传', 'sub': 'WebDAV 及视频压缩'},
      {'icon': Icons.tv_rounded, 'title': '跨设备同步', 'sub': '扫码接收手机配置'},
      {'icon': Icons.settings_rounded, 'title': '应用与系统', 'sub': '高级设置与关于'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      body: SafeArea(
        child: Row(
          children: [
            // 左侧导航栏 (Width 300)
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1C22),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部标题与返回键
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      children: [
                        _TvBackButton(onTap: () => Navigator.maybePop(context)),
                        const SizedBox(width: 14),
                        const Text(
                          '设置',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 分类列表
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        return _TvCategoryRailItem(
                          autofocus: index == 0,
                          icon: cat['icon'] as IconData,
                          title: cat['title'] as String,
                          subtitle: cat['sub'] as String,
                          isSelected: _tvSelectedCategory == index,
                          onFocusChange: (hasFocus) {
                            if (hasFocus) {
                              setState(() => _tvSelectedCategory = index);
                            }
                          },
                          onTap: () {
                            setState(() => _tvSelectedCategory = index);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // 右侧内容区 (Expanded)
            Expanded(
              child: Container(
                color: const Color(0xFF141416),
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 分类大标题
                    Row(
                      children: [
                        Icon(
                          categories[_tvSelectedCategory]['icon'] as IconData,
                          color: Colors.pink.shade300,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          categories[_tvSelectedCategory]['title'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          categories[_tvSelectedCategory]['sub'] as String,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 具体配置卡片列表
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildTvCategoryContent(_tvSelectedCategory),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvCategoryContent(int category) {
    switch (category) {
      case 0: // 宝宝信息
        final birthStr = _config.babyBirthDate != null
            ? '${_config.babyBirthDate!.year}-${_config.babyBirthDate!.month.toString().padLeft(2, '0')}-${_config.babyBirthDate!.day.toString().padLeft(2, '0')}'
            : '未设置';
        final concStr = _config.babyConceptionDate != null
            ? '${_config.babyConceptionDate!.year}-${_config.babyConceptionDate!.month.toString().padLeft(2, '0')}-${_config.babyConceptionDate!.day.toString().padLeft(2, '0')}'
            : '未设置';

        return Column(
          children: [
            _TvSettingCard(
              icon: Icons.baby_changing_station,
              title: '宝宝昵称',
              subtitle: '用于相册主页展示及云端日记归档',
              valueBadge:
                  _config.babyName.isNotEmpty ? _config.babyName : '未设置',
              onTap: _showEditChildNameDialog,
            ),
            const SizedBox(height: 14),
            _TvSettingCard(
              icon: Icons.cake,
              title: '出生日期',
              subtitle: '用于精准计算每一天的成长天数与月龄',
              valueBadge: birthStr,
              onTap: _editBirthDate,
            ),
            const SizedBox(height: 14),
            _TvSettingCard(
              icon: Icons.pregnant_woman,
              title: '受孕日期 / 孕期开始',
              subtitle: '用于计算孕周及出生前回忆记录',
              valueBadge: concStr,
              onTap: _editConceptionDate,
            ),
          ],
        );

      case 1: // 存储与上传
        final thresholdStr = _config.videoCompressionThreshold == 0
            ? '始终不压缩'
            : '${_config.videoCompressionThreshold} MB';
        final webdavStatus = _config.webdavUrl.isNotEmpty
            ? _config.webdavUrl
            : '未配置 WebDAV';

        return Column(
          children: [
            _TvSettingCard(
              icon: Icons.cloud_done_rounded,
              title: 'WebDAV 云存储服务',
              subtitle:
                  '用户: ${_config.username.isNotEmpty ? _config.username : "未设置"}',
              valueBadge: webdavStatus,
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
                  setState(() => _config = widget.config);
                });
              },
            ),
            const SizedBox(height: 14),
            _TvSettingCard(
              icon: Icons.video_file_rounded,
              title: '视频上传压缩阈值',
              subtitle: '当视频文件大于此大小自动轻量压缩以加快同步',
              valueBadge: thresholdStr,
              onTap: _editVideoCompressionThreshold,
            ),
          ],
        );

      case 2: // 跨设备同步
        return Column(
          children: [
            _TvSettingCard(
              icon: Icons.qr_code_2_rounded,
              title: '重新扫码接收手机配置',
              subtitle: '电视大屏展示局域网扫码窗口，手机扫码即可一键投送新配置',
              valueBadge: '重新配对',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SetupScreen(),
                  ),
                );
              },
            ),
          ],
        );

      case 3: // 应用与关于
      default:
        return Column(
          children: [
            _TvSettingCard(
              icon: Icons.settings_applications_rounded,
              title: '高级应用设置',
              subtitle: '本地缓存管理、缩略图清理与数据设置',
              valueBadge: '管理',
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
            const SizedBox(height: 14),
            const _TvSettingCard(
              icon: Icons.info_outline_rounded,
              title: '关于成长日记 TV版',
              subtitle: '专为客厅电视大屏打造的宝宝成长回忆相册',
              valueBadge: 'v1.0.0',
              onTap: null,
            ),
          ],
        );
    }
  }

  // ──────────────────────────────────────────
  // 手机 / 平板 原生设置布局
  // ──────────────────────────────────────────

  Widget _buildPhoneSettingsLayout(BuildContext context) {
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
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: DeviceType.maxContentWidth(context),
          ),
          child: ListView(
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
                      setState(() {
                        _config = widget.config;
                      });
                    });
                  },
                ),
              ]),
              _buildSection('跨设备同步'),
              _buildSettingsGroup([
                _buildSettingsTile(
                  icon: Icons.tv,
                  title: '投送配置到电视',
                  subtitle: '扫描电视屏幕上的配对二维码一键同步',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            QRScannerScreen(currentConfig: _config),
                      ),
                    );
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
        ),
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
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: children,
        ),
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
          color: Theme.of(context).primaryColor.withOpacity(0.1),
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

// ──────────────────────────────────────────
// TV 专用设置组件（左右分栏卡片与分类项）
// ──────────────────────────────────────────

class _TvSettingCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String valueBadge;
  final VoidCallback? onTap;

  const _TvSettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueBadge,
    this.onTap,
  });

  @override
  State<_TvSettingCard> createState() => _TvSettingCardState();
}

class _TvSettingCardState extends State<_TvSettingCard> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) {
        setState(() => _isFocused = _focusNode.hasFocus);
        if (_focusNode.hasFocus) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.onTap != null;

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: isClickable,
      onKeyEvent: (node, event) {
        if (isClickable &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: _isFocused
                  ? const Color(0xFF262933)
                  : const Color(0xFF1E2026),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused
                    ? Colors.pink.shade300
                    : Colors.white.withOpacity(0.06),
                width: _isFocused ? 2.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.3),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // 左侧图标容器
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isFocused
                        ? Colors.pink.shade500
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.icon,
                    color: _isFocused ? Colors.white : Colors.pink.shade200,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 18),
                // 标题与副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // 右侧值标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isFocused
                        ? Colors.pink.shade900.withOpacity(0.5)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isFocused
                          ? Colors.pink.shade400.withOpacity(0.6)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Text(
                    widget.valueBadge,
                    style: TextStyle(
                      color:
                          _isFocused ? Colors.pink.shade100 : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isClickable) ...[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _isFocused ? Colors.pink.shade300 : Colors.white30,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvCategoryRailItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool autofocus;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;

  const _TvCategoryRailItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    this.autofocus = false,
    required this.onFocusChange,
    required this.onTap,
  });

  @override
  State<_TvCategoryRailItem> createState() => _TvCategoryRailItemState();
}

class _TvCategoryRailItemState extends State<_TvCategoryRailItem> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) {
        setState(() => _isFocused = _focusNode.hasFocus);
        widget.onFocusChange(_focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Border border;

    if (_isFocused) {
      bg = const Color(0xFF2C2F3A);
      border = Border.all(color: Colors.pink.shade400, width: 2.0);
    } else if (widget.isSelected) {
      bg = const Color(0xFF232630);
      border = Border.all(color: Colors.white.withOpacity(0.08), width: 1.0);
    } else {
      bg = Colors.transparent;
      border = Border.all(color: Colors.transparent);
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: border,
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: Colors.pink.withOpacity(0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? Colors.pink.shade400
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  widget.icon,
                  size: 22,
                  color: widget.isSelected || _isFocused
                      ? Colors.pink.shade300
                      : Colors.white60,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: widget.isSelected || _isFocused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvBackButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TvBackButton({required this.onTap});

  @override
  State<_TvBackButton> createState() => _TvBackButtonState();
}

class _TvBackButtonState extends State<_TvBackButton> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isFocused
                ? Colors.pink.shade500
                : Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isFocused ? Colors.pink.shade300 : Colors.transparent,
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
