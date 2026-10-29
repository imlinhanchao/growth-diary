import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/app_config.dart';
import '../services/local_storage_service.dart';
import '../services/webdav_service.dart';
import '../services/qr_service.dart';
import '../services/tv_pairing_service.dart';
import '../utils/device_type.dart';
import 'home_screen.dart';
import 'webdav_config_screen.dart';
import 'qr_scanner_screen.dart';

class SetupScreen extends StatefulWidget {
  final LocalStorageService? localStorage;

  const SetupScreen({super.key, this.localStorage});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _childNameController = TextEditingController();
  DateTime? _childBirthDate;
  DateTime? _conceptionDate;
  bool _isLoading = false;
  bool _isPregnant = false; // false = 已出生, true = 怀孕中
  AppConfig? _webdavConfig;

  final WebDAVService _webdavService = WebDAVService();

  // 局域网配对服务
  final TvPairingServer _pairingServer = TvPairingServer();
  TvPairingInfo? _pairingInfo;
  bool _isStartingPairingServer = false;
  bool _showManualFormOnTv = false; // TV 模式下是否显示手动输入表单

  @override
  void initState() {
    super.initState();
    _startPairingServer();
  }

  @override
  void dispose() {
    _pairingServer.stop();
    _childNameController.dispose();
    super.dispose();
  }

  /// 启动电视局域网配对监听
  Future<void> _startPairingServer() async {
    setState(() {
      _isStartingPairingServer = true;
    });

    final info = await _pairingServer.start(
      onConfigReceived: (config) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 收到来自手机的配置【${config.babyName}】，正在登录...'),
            backgroundColor: Colors.green,
          ),
        );
        await _importAndNavigate(config);
      },
    );

    if (mounted) {
      setState(() {
        _pairingInfo = info;
        _isStartingPairingServer = false;
      });
    }
  }

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择宝宝生日',
    );
    if (picked != null) {
      setState(() {
        _childBirthDate = picked;
      });
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(),
      ),
    );

    if (!mounted) return;

    if (result != null && result is String) {
      // 尝试解码二维码数据
      final importedConfig = QRService.decodeEncryptedQRData(result);

      if (importedConfig != null) {
        // 显示确认对话框
        final shouldImport = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认导入配置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('宝宝昵称: ${importedConfig.babyName}'),
                Text(
                    '出生日期: ${importedConfig.babyBirthDate?.toString().split(' ')[0] ?? '未设置'}'),
                Text(
                    '受孕日期: ${importedConfig.conceptionDate?.toString().split(' ')[0] ?? '未设置'}'),
                Text('WebDAV服务器: ${importedConfig.webdavUrl}'),
                Text('用户名: ${importedConfig.username}'),
                const Text('密码: ***（已加密存储）'),
                const SizedBox(height: 10),
                const Text(
                  '导入后将使用此配置，确定继续吗？',
                  style: TextStyle(color: Colors.red, fontSize: 12),
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
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('导入'),
              ),
            ],
          ),
        );

        if (shouldImport == true) {
          // 导入配置并跳转到主界面
          await _importAndNavigate(importedConfig);
        }
      } else {
        // 无效的二维码
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无效的二维码数据')),
          );
        }
      }
    }
  }

  Future<void> _importAndNavigate(AppConfig importedConfig) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final webdavService = WebDAVService();
      final localStorage = widget.localStorage ?? LocalStorageService();

      // Initialize WebDAV with imported config
      await webdavService.initialize(importedConfig);

      // Save config to WebDAV
      await webdavService.saveConfig(importedConfig);

      // Save config locally
      await localStorage.saveConfig(importedConfig);
      await localStorage.setCurrentConfigId(importedConfig.id);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            configs: {importedConfig.id: importedConfig},
            currentConfigId: importedConfig.id,
            cloudService: webdavService,
            localStorage: localStorage,
            onConfigChanged: (config) {
              // SetupScreen创建的配置，不需要特殊处理
              localStorage.saveConfig(config);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  Future<void> _selectConceptionDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择受孕日期',
    );
    if (picked != null) {
      setState(() {
        _conceptionDate = picked;
      });
    }
  }

  Future<void> _configureWebDAV() async {
    final result = await Navigator.of(context).push<AppConfig>(
      MaterialPageRoute(
        builder: (context) => WebDAVConfigScreen(
          mode: WebDAVConfigMode.setup,
          config: _webdavConfig,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _webdavConfig = result;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isPregnant) {
      if (_conceptionDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择受孕日期')),
        );
        return;
      }
    } else {
      if (_childBirthDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择宝宝生日')),
        );
        return;
      }
    }

    if (_webdavConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置WebDAV')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final config = AppConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        webdavUrl: _webdavConfig!.webdavUrl,
        username: _webdavConfig!.username,
        password: _webdavConfig!.password,
        babyName: _childNameController.text.trim(),
        babyBirthDate: _isPregnant ? null : _childBirthDate,
        babyConceptionDate: _isPregnant ? _conceptionDate : null,
      );

      // Initialize WebDAV
      await _webdavService.initialize(config);

      // Save config to WebDAV
      await _webdavService.saveConfig(config);

      // Save config locally
      final localStorage = widget.localStorage ?? LocalStorageService();
      await localStorage.saveConfig(config);
      await localStorage.setCurrentConfigId(config.id);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            configs: {config.id: config},
            currentConfigId: config.id,
            cloudService: _webdavService,
            localStorage: localStorage,
            onConfigChanged: (config) {
              // SetupScreen创建的配置，不需要特殊处理
              localStorage.saveConfig(config);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('配置失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildStepRow(String stepNum, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.pink,
            shape: BoxShape.circle,
          ),
          child: Text(
            stepNum,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildTvPairingCard(BuildContext context) {
    if (_isStartingPairingServer) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.pink.shade100),
        ),
        child: const Column(
          children: [
            CircularProgressIndicator(color: Colors.pink),
            SizedBox(height: 16),
            Text('正在启动电视配对服务...'),
          ],
        ),
      );
    }

    if (_pairingInfo == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            const Text(
              '未能获取局域网 IP，请检查电视 Wi-Fi 或有线网络连接',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _startPairingServer,
              icon: const Icon(Icons.refresh),
              label: const Text('重试连接'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.pink.shade100, width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.tv, color: Colors.pink.shade600, size: 28),
              const SizedBox(width: 8),
              const Text(
                '手机扫码，一键同步到电视',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '电视当前 IP: ${_pairingInfo!.ip} (需与手机在同一 Wi-Fi)',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          // 二维码区域
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.pink.shade100, width: 2),
            ),
            child: QrImageView(
              data: _pairingInfo!.toQrString(),
              version: QrVersions.auto,
              size: 220,
              dataModuleStyle: const QrDataModuleStyle(color: Colors.pink),
              eyeStyle: const QrEyeStyle(color: Colors.pink),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepRow('1', '确保手机与电视连接在同一个家庭 Wi-Fi 网络'),
                const SizedBox(height: 6),
                _buildStepRow('2', '打开手机版《成长日记》APP'),
                const SizedBox(height: 6),
                _buildStepRow('3', '进入扫码界面，扫描上方二维码即可一键投送！'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTV = DeviceType.isTV(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('初始设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: DeviceType.maxContentWidth(context),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/foreground.png',
                    width: isTV ? 80 : 100,
                    height: isTV ? 80 : 100,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '欢迎使用成长日记',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '记录宝宝的每一个珍贵瞬间',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // ── Android TV 模式：优先展示扫码配对大卡片 ──
                  if (isTV) ...[
                    _buildTvPairingCard(context),
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showManualFormOnTv = !_showManualFormOnTv;
                          });
                        },
                        icon: Icon(
                          _showManualFormOnTv
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                        label: Text(
                          _showManualFormOnTv
                              ? '隐藏遥控器手动输入'
                              : '使用遥控器手动录入配置',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ),
                    if (!_showManualFormOnTv) const SizedBox(height: 40),
                  ],

                  // ── 手机/平板模式 或 TV展开手动录入 ──
                  if (!isTV || _showManualFormOnTv) ...[
                    if (!isTV) ...[
                      // 手机/平板下的导入配置按钮
                      OutlinedButton.icon(
                        onPressed: _scanQRCode,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('导入配置 (扫码)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.pink,
                          side: const BorderSide(color: Colors.pink),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 也可以在手机展开电视配对二维码（互传）
                      ExpansionTile(
                        title: const Text('作为接收端（显示局域网投送二维码）'),
                        leading: const Icon(Icons.cast, color: Colors.pink),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildTvPairingCard(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '或手动录入',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],

                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          // 已出生选项
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isPregnant = false;
                                  _conceptionDate = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: !_isPregnant
                                      ? Colors.pink.shade50
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cake,
                                      color: !_isPregnant
                                          ? Colors.pink
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '已出生',
                                      style: TextStyle(
                                        color: !_isPregnant
                                            ? Colors.pink
                                            : Colors.grey,
                                        fontWeight: !_isPregnant
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 怀孕中选项
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isPregnant = true;
                                  _childBirthDate = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: _isPregnant
                                      ? Colors.pink.shade50
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.pregnant_woman,
                                      color: _isPregnant
                                          ? Colors.pink
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '怀孕中',
                                      style: TextStyle(
                                        color: _isPregnant
                                            ? Colors.pink
                                            : Colors.grey,
                                        fontWeight: _isPregnant
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '宝宝信息',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: _childNameController,
                      decoration: const InputDecoration(
                        labelText: '宝宝昵称',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.baby_changing_station),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入宝宝昵称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    if (_isPregnant)
                      InkWell(
                        onTap: _selectConceptionDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '受孕日期',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.pregnant_woman),
                          ),
                          child: Text(
                            _conceptionDate != null
                                ? '${_conceptionDate!.year}-${_conceptionDate!.month.toString().padLeft(2, '0')}-${_conceptionDate!.day.toString().padLeft(2, '0')}'
                                : '点击选择日期',
                            style: TextStyle(
                              color: _conceptionDate != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: _selectBirthDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '宝宝生日',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.cake),
                          ),
                          child: Text(
                            _childBirthDate != null
                                ? '${_childBirthDate!.year}-${_childBirthDate!.month.toString().padLeft(2, '0')}-${_childBirthDate!.day.toString().padLeft(2, '0')}'
                                : '点击选择日期',
                            style: TextStyle(
                              color: _childBirthDate != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
                    const Text(
                      '云存储配置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud,
                            color: _webdavConfig != null
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _webdavConfig != null
                                  ? 'WebDAV 已配置 (${_webdavConfig!.webdavUrl})'
                                  : '未配置云存储',
                              style: TextStyle(
                                color: _webdavConfig != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _configureWebDAV,
                            child:
                                Text(_webdavConfig != null ? '修改配置' : '配置'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              '完成设置',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
