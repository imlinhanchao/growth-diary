import 'package:flutter/material.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../models/app_config.dart';
import '../services/cloud_storage_service.dart';
import '../services/local_storage_service.dart';
import '../services/network_service.dart';

enum WebDAVConfigMode {
  setup, // 初始设置模式，返回配置结果
  settings, // 设置页面模式，通过回调更新
}

class WebDAVConfigScreen extends StatefulWidget {
  final WebDAVConfigMode mode;
  final AppConfig? config; // setup模式下可为null，settings模式下必填
  final CloudStorageService? webdavService; // settings模式下需要
  final Function(AppConfig)? onConfigChanged; // settings模式下的回调

  const WebDAVConfigScreen({
    super.key,
    required this.mode,
    this.config,
    this.webdavService,
    this.onConfigChanged,
  }) : assert(
            (mode == WebDAVConfigMode.setup) ||
                (mode == WebDAVConfigMode.settings &&
                    config != null &&
                    webdavService != null &&
                    onConfigChanged != null),
            'Invalid configuration for WebDAVConfigScreen');

  @override
  State<WebDAVConfigScreen> createState() => _WebDAVConfigScreenState();
}

class _WebDAVConfigScreenState extends State<WebDAVConfigScreen> {
  final LocalStorageService _localStorage = LocalStorageService();
  final _formKey = GlobalKey<FormState>();
  late AppConfig _config;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _newMirrorController = TextEditingController();
  final TextEditingController _newMirrorWifiController = TextEditingController();
  bool _isTestingConnection = false;
  String? _defaultWebdavUrl; // 从 local storage 读取的默认地址
  String? _currentWifiSsid; // 当前连接的 WiFi SSID
  bool _hasLocationPermission = true;
  bool _isLocationServiceEnabled = true;
  bool _isPermanentlyDenied = false;
  bool _isLoadingWifi = false;

  @override
  void initState() {
    super.initState();
    _config = widget.config ?? AppConfig();
    _urlController.text = _config.webdavUrl;
    _usernameController.text = _config.username;
    _passwordController.text = _config.password;
    _loadDefaultWebdavUrl();
    _loadCurrentWifi(requestPermission: true);
  }

  Future<void> _loadCurrentWifi({bool requestPermission = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingWifi = true;
    });
    final status = await NetworkService.getWifiStatus(
        requestPermission: requestPermission);
    if (mounted) {
      setState(() {
        _currentWifiSsid = status.ssid;
        _hasLocationPermission = status.hasPermission;
        _isLocationServiceEnabled = status.isLocationServiceEnabled;
        _isPermanentlyDenied = status.isPermanentlyDenied;
        _isLoadingWifi = false;
      });
    }
  }

  Future<void> _loadDefaultWebdavUrl() async {
    final defaultUrl =
        await _localStorage.getString('defaultWebdavUrl:${_config.webdavUrl}');
    setState(() {
      _defaultWebdavUrl = defaultUrl;
    });
  }

  Future<void> _saveDefaultWebdavUrl(String? url) async {
    if (url != null) {
      await _localStorage.saveString(
          'defaultWebdavUrl:${_config.webdavUrl}', url);
    } else {
      await _localStorage.remove('defaultWebdavUrl:${_config.webdavUrl}');
    }
    setState(() {
      _defaultWebdavUrl = url;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _newMirrorController.dispose();
    _newMirrorWifiController.dispose();
    super.dispose();
  }

  void _addMirror() {
    final url = _newMirrorController.text.trim();
    final wifi = _newMirrorWifiController.text.trim();
    if (url.isNotEmpty && !_config.webdavMirrors.any((m) => m.url == url)) {
      setState(() {
        _config.webdavMirrors.add(WebDavMirror(
          url: url,
          wifiSsid: wifi.isNotEmpty ? wifi : null,
        ));
        if (_defaultWebdavUrl == null && wifi.isEmpty) {
          _saveDefaultWebdavUrl(url);
        }
      });
      _newMirrorController.clear();
      _newMirrorWifiController.clear();
    }
  }

  void _removeMirror(WebDavMirror mirror) {
    setState(() {
      _config.webdavMirrors.remove(mirror);
      if (_defaultWebdavUrl == mirror.url) {
        final newDefault = _config.webdavMirrors.isNotEmpty
            ? _config.webdavMirrors.first.url
            : null;
        _saveDefaultWebdavUrl(newDefault);
      }
    });
  }

  void _setDefaultMirror(String url) {
    _saveDefaultWebdavUrl(url);
  }

  void _showEditMirrorWifiDialog(WebDavMirror mirror) {
    final wifiController = TextEditingController(text: mirror.wifiSsid ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('设置 WiFi 绑定'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '镜像地址: ${mirror.url}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: wifiController,
                  decoration: InputDecoration(
                    labelText: 'WiFi 名称 (SSID)',
                    hintText: '例如: Home-WiFi，留空表示通用',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: _currentWifiSsid != null
                        ? IconButton(
                            icon: const Icon(Icons.wifi_find),
                            tooltip: '填入当前 WiFi: $_currentWifiSsid',
                            onPressed: () {
                              wifiController.text = _currentWifiSsid!;
                              setDialogState(() {});
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '仅在手机连接该 WiFi 时使用此镜像。支持多个 WiFi，用逗号分隔（如 2.4G 与 5G）。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
            actions: [
              if (mirror.hasWifiBinding)
                TextButton(
                  onPressed: () {
                    final index = _config.webdavMirrors.indexOf(mirror);
                    if (index != -1) {
                      setState(() {
                        _config.webdavMirrors[index] =
                            mirror.copyWith(clearWifi: true);
                      });
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('解除绑定', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final newWifi = wifiController.text.trim();
                  final index = _config.webdavMirrors.indexOf(mirror);
                  if (index != -1) {
                    setState(() {
                      _config.webdavMirrors[index] = WebDavMirror(
                        url: mirror.url,
                        wifiSsid: newWifi.isNotEmpty ? newWifi : null,
                      );
                    });
                  }
                  Navigator.of(ctx).pop();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWifiStatusBanner() {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color subTextColor;
    final IconData iconData;
    final Color iconColor;
    final String title;
    final String subtitle;
    Widget? actionWidget;

    if (_currentWifiSsid != null) {
      bgColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
      textColor = Colors.blue.shade900;
      subTextColor = Colors.blue.shade700;
      iconData = Icons.wifi;
      iconColor = Colors.blue.shade700;
      title = '当前连接 WiFi: $_currentWifiSsid';
      subtitle = '连接匹配的 WiFi 自动使用专属镜像，否则使用通用默认配置';
    } else if (!_hasLocationPermission) {
      bgColor = Colors.amber.shade50;
      borderColor = Colors.amber.shade300;
      textColor = Colors.amber.shade900;
      subTextColor = Colors.amber.shade800;
      iconData = Icons.location_off_outlined;
      iconColor = Colors.amber.shade800;
      title = '未授权位置权限，无法识别 WiFi';
      subtitle = 'Android 系统规定获取 WiFi 名称需授权位置权限。';
      actionWidget = TextButton(
        onPressed: () {
          if (_isPermanentlyDenied) {
            NetworkService.openSettings();
          } else {
            _loadCurrentWifi(requestPermission: true);
          }
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          backgroundColor: Colors.amber.shade100,
          foregroundColor: Colors.amber.shade900,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        child: Text(_isPermanentlyDenied ? '去设置' : '授权定位'),
      );
    } else if (!_isLocationServiceEnabled) {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      textColor = Colors.orange.shade900;
      subTextColor = Colors.orange.shade800;
      iconData = Icons.gps_off;
      iconColor = Colors.orange.shade800;
      title = '系统位置信息 (GPS) 开关未开启';
      subtitle = 'Android 要求读取 WiFi 名称时手机 GPS 必须打开。请在下拉状态栏开启「位置信息」后刷新。';
    } else {
      bgColor = Colors.grey.shade100;
      borderColor = Colors.grey.shade300;
      textColor = Colors.grey.shade800;
      subTextColor = Colors.grey.shade600;
      iconData = Icons.wifi_off;
      iconColor = Colors.grey.shade600;
      title = '当前未连接或未能识别 WiFi';
      subtitle = '在移动数据或未识别 WiFi 下将使用通用默认镜像。也可在下方手动输入 WiFi 名称绑定。';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(iconData, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: subTextColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (actionWidget != null) ...[
            const SizedBox(width: 8),
            actionWidget,
          ],
          const SizedBox(width: 4),
          _isLoadingWifi
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '重新检测 WiFi',
                  color: iconColor,
                  onPressed: () => _loadCurrentWifi(requestPermission: true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
        ],
      ),
    );
  }

  Future<void> _testSpecificMirror(WebDavMirror mirror) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先输入用户名和密码以测试连接'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在测试连接到 ${mirror.url}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final client = webdav.newClient(
        mirror.url,
        user: username,
        password: password,
        debug: false,
      );
      client.setConnectTimeout(6000);
      client.setSendTimeout(6000);
      client.setReceiveTimeout(6000);

      await client.readDir('/');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('镜像 [${mirror.url}] 连接测试成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('镜像 [${mirror.url}] 连接测试失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testWebDAVConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTestingConnection = true;
    });

    try {
      final url = _urlController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      final client = webdav.newClient(
        url,
        user: username,
        password: password,
        debug: true,
      );
      client.setConnectTimeout(8000);
      client.setSendTimeout(8000);
      client.setReceiveTimeout(8000);

      // Test connection by listing directory
      await client.readDir('/');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接测试成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接测试失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final newConfig = _config.copyWith(
      webdavUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      webdavMirrors: _config.webdavMirrors,
    );

    if (widget.mode == WebDAVConfigMode.settings) {
      // Settings模式：保存到本地和服务，调用回调
      await _localStorage.saveConfig(newConfig);
      await widget.webdavService!.initialize(newConfig);
      await widget.webdavService!.saveConfig(newConfig);
      widget.onConfigChanged!(newConfig);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      // Setup模式：返回配置结果
      Navigator.of(context).pop(newConfig);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSetupMode = widget.mode == WebDAVConfigMode.setup;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(isSetupMode ? '配置云存储' : 'WebDAV 设置',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 00.03),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _buildTextField(
                      controller: _urlController,
                      label: '服务器地址 (URL)',
                      hint: 'https://example.com/webdav',
                      icon: Icons.link,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入 WebDAV URL';
                        }
                        if (!value.startsWith('http')) {
                          return '请输入有效的 URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _usernameController,
                      label: '用户名',
                      hint: '请输入用户名',
                      icon: Icons.person_outline,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入用户名';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _passwordController,
                      label: '密码',
                      hint: '请输入密码',
                      icon: Icons.lock_outline,
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入密码';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 镜像地址管理
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 00.03),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_sync,
                            color: Colors.blue.shade500, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          '镜像地址管理',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '配置多个 WebDAV 服务器地址作为数据镜像。参考 Immich，可将镜像绑定至指定 WiFi。连接该 WiFi 时自动切换至该镜像，其他网络自动使用通用默认配置。',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 当前网络状态横幅
                    _buildWifiStatusBanner(),

                    const SizedBox(height: 20),

                    // 添加新镜像表单
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '添加新镜像',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _newMirrorController,
                            decoration: InputDecoration(
                              hintText: '镜像地址 (如 http://192.168.1.100:5005)',
                              hintStyle: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 14),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newMirrorWifiController,
                                  decoration: InputDecoration(
                                    hintText: '绑定 WiFi (SSID, 可选留空为通用镜像)',
                                    hintStyle: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 13),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 14),
                                    suffixIcon: _currentWifiSsid != null
                                        ? TextButton.icon(
                                            onPressed: () {
                                              _newMirrorWifiController.text =
                                                  _currentWifiSsid!;
                                            },
                                            icon: const Icon(Icons.wifi_find,
                                                size: 16),
                                            label: const Text('填入当前',
                                                style: TextStyle(fontSize: 11)),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _addMirror,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('添加'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 镜像列表
                    Builder(builder: (context) {
                      // 解析当前网络下生效的镜像
                      WebDavMirror? activeMirror;
                      if (_currentWifiSsid != null) {
                        activeMirror =
                            _config.getMirrorForWifi(_currentWifiSsid);
                      }
                      if (activeMirror == null && _defaultWebdavUrl != null) {
                        activeMirror = _config.webdavMirrors
                            .cast<WebDavMirror?>()
                            .firstWhere(
                              (m) =>
                                  m != null &&
                                  m.url == _defaultWebdavUrl &&
                                  (!m.hasWifiBinding ||
                                      (_currentWifiSsid != null &&
                                          m.matchesWifi(_currentWifiSsid))),
                              orElse: () => null,
                            );
                      }
                      activeMirror ??= _config.defaultUnboundMirror;
                      activeMirror ??= (_config.webdavMirrors.isNotEmpty
                          ? _config.webdavMirrors.first
                          : null);

                      if (_config.webdavMirrors.isNotEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前镜像 (${_config.webdavMirrors.length})',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._config.webdavMirrors.map((mirror) {
                              final isActive = activeMirror != null &&
                                  activeMirror == mirror;
                              final isDefault =
                                  _defaultWebdavUrl == mirror.url;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.green.shade50.withValues(alpha: 0.4)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive
                                        ? Colors.green.shade400
                                        : (isDefault
                                            ? Colors.blue.shade300
                                            : Colors.grey.shade200),
                                    width: isActive ? 1.8 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            mirror.url,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade900,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: () => _removeMirror(mirror),
                                          icon: Icon(Icons.delete_outline,
                                              size: 20,
                                              color: Colors.red.shade400),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        // 状态徽标
                                        if (isActive) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.green.shade300),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check_circle,
                                                    size: 13,
                                                    color: Colors.green.shade700),
                                                const SizedBox(width: 4),
                                                Text(
                                                  mirror.hasWifiBinding
                                                      ? '生效中 (WiFi匹配)'
                                                      : '生效中 (通用默认)',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.green.shade800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (isDefault) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.blue.shade300),
                                            ),
                                            child: Text(
                                              '默认载入',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.blue.shade800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        // WiFi 绑定标签
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                _showEditMirrorWifiDialog(
                                                    mirror),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: mirror.hasWifiBinding
                                                    ? Colors.indigo.shade50
                                                    : Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: mirror.hasWifiBinding
                                                      ? Colors.indigo.shade200
                                                      : Colors.grey.shade300,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    mirror.hasWifiBinding
                                                        ? Icons.wifi
                                                        : Icons.wifi_off_outlined,
                                                    size: 13,
                                                    color: mirror.hasWifiBinding
                                                        ? Colors.indigo.shade700
                                                        : Colors.grey.shade600,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      mirror.hasWifiBinding
                                                          ? 'WiFi: ${mirror.wifiSsid}'
                                                          : '未绑定WiFi (点击绑定)',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: mirror
                                                                .hasWifiBinding
                                                            ? Colors
                                                                .indigo.shade800
                                                            : Colors
                                                                .grey.shade600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Icon(Icons.edit,
                                                      size: 11,
                                                      color: mirror.hasWifiBinding
                                                          ? Colors.indigo.shade400
                                                          : Colors.grey.shade400),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              _testSpecificMirror(mirror),
                                          icon: const Icon(
                                              Icons.network_check,
                                              size: 15),
                                          label: const Text('测试连接',
                                              style: TextStyle(fontSize: 12)),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (!isDefault)
                                          TextButton(
                                            onPressed: () =>
                                                _setDefaultMirror(mirror.url),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: Text(
                                              '设为默认',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blue.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      } else {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  size: 48,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '暂无镜像地址',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isTestingConnection ? null : _testWebDAVConnection,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.blue.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: Colors.blue.shade700,
                        backgroundColor: Colors.white,
                      ),
                      child: _isTestingConnection
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blue.shade700,
                              ),
                            )
                          : const Text('测试连接',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: Colors.blue.shade200,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('保存配置',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              if (!isSetupMode) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '注意：修改配置后，将会采用新的配置载入数据，数据需要手动迁移。',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        labelStyle: TextStyle(color: Colors.grey.shade600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue.shade300, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade200, width: 1),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 22),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
      validator: validator,
    );
  }
}
