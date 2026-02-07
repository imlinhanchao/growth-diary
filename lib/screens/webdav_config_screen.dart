import 'package:flutter/material.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../models/app_config.dart';
import '../services/cloud_storage_service.dart';
import '../services/local_storage_service.dart';

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
  bool _isTestingConnection = false;
  String? _defaultWebdavUrl; // 从 local storage 读取的默认地址

  @override
  void initState() {
    super.initState();
    _config = widget.config ?? AppConfig();
    _urlController.text = _config.webdavUrl;
    _usernameController.text = _config.username;
    _passwordController.text = _config.password;
    _loadDefaultWebdavUrl();
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
    super.dispose();
  }

  void _addMirror() {
    final url = _newMirrorController.text.trim();
    if (url.isNotEmpty && !_config.webdavMirrors.contains(url)) {
      setState(() {
        _config.webdavMirrors.add(url);
        if (_defaultWebdavUrl == null) {
          _saveDefaultWebdavUrl(url);
        }
      });
      _newMirrorController.clear();
    }
  }

  void _removeMirror(String url) {
    setState(() {
      _config.webdavMirrors.remove(url);
      if (_defaultWebdavUrl == url) {
        final newDefault = _config.webdavMirrors.isNotEmpty
            ? _config.webdavMirrors.first
            : null;
        _saveDefaultWebdavUrl(newDefault);
      }
    });
  }

  void _setDefaultMirror(String url) {
    _saveDefaultWebdavUrl(url);
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
                      '配置多个 WebDAV 服务器地址作为数据镜像，提高数据可用性',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 添加新镜像
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newMirrorController,
                            decoration: InputDecoration(
                              hintText: '输入新的镜像地址',
                              hintStyle: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 14),
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
                                borderSide: BorderSide(
                                    color: Colors.blue.shade300, width: 1.5),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                            ),
                            onSubmitted: (_) => _addMirror(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _addMirror,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('添加'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 镜像列表
                    if (_config.webdavMirrors.isNotEmpty) ...[
                      Text(
                        '当前镜像 (${_config.webdavMirrors.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._config.webdavMirrors.map((url) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _defaultWebdavUrl == url
                                    ? Colors.blue.shade200
                                    : Colors.grey.shade200,
                                width: _defaultWebdavUrl == url ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        url,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade800,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (_defaultWebdavUrl == url) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '默认载入地址',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_defaultWebdavUrl != url)
                                  TextButton(
                                    onPressed: () => _setDefaultMirror(url),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                                IconButton(
                                  onPressed: () => _removeMirror(url),
                                  icon: Icon(Icons.delete_outline,
                                      size: 20, color: Colors.red.shade400),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          )),
                    ] else ...[
                      Center(
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
                      ),
                    ],
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
