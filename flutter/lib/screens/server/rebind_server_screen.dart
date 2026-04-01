import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/server.dart';
import '../../providers/server_provider.dart';
import '../../services/api_service.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_overlay_appbar.dart';

/// 重新绑定服务器界面
class RebindServerScreen extends StatefulWidget {
  final Server server;

  const RebindServerScreen({
    Key? key,
    required this.server,
  }) : super(key: key);

  @override
  State<RebindServerScreen> createState() => _RebindServerScreenState();
}

class _RebindServerScreenState extends State<RebindServerScreen> {
  late final TextEditingController _nameController;
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _isQRMode = true; // 默认二维码模式
  bool _qrScanned = false; // 是否已扫描二维码
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 初始化服务器名称（禁用编辑）
    _nameController = TextEditingController(text: widget.server.name);
    // 预填充服务器地址和 API Key
    _urlController.text = widget.server.baseUrl;
    _keyController.text = widget.server.apiKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      appBar: NeumorphicAppBar(
        title: Text(
          '重新绑定服务器',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: ThemeColors.text(context),
          ),
        ),
        leading: NeumorphicButton(
          onPressed: () => Navigator.of(context).pop(),
          style: const NeumorphicStyle(
            boxShape: NeumorphicBoxShape.circle(),
            depth: 3,
          ),
          padding: const EdgeInsets.all(12),
          child: const Icon(Icons.arrow_back, size: 20),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Neumorphic(
            style: NeumorphicStyle(
              depth: 4,
              intensity: 0.6,
              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // NeumorphicToggle 切换模式
                _buildModeToggle(),
                const SizedBox(height: 32),
                // 根据模式显示不同内容
                _isQRMode ? _buildQRMode() : _buildManualMode(),
                // 错误提示
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 模式切换 Toggle
  Widget _buildModeToggle() {
    return Center(
      child: SizedBox(
        width: 240,
        child: NeumorphicToggle(
          height: 40,
          selectedIndex: _isQRMode ? 0 : 1,
          displayForegroundOnlyIfSelected: true,
          children: [
            ToggleElement(
              background: Center(
                child: Text(
                  '二维码',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ThemeColors.textSecondary(context),
                  ),
                ),
              ),
              foreground: Center(
                child: Text(
                  '二维码',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ThemeColors.text(context),
                  ),
                ),
              ),
            ),
            ToggleElement(
              background: Center(
                child: Text(
                  '手动输入',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ThemeColors.textSecondary(context),
                  ),
                ),
              ),
              foreground: Center(
                child: Text(
                  '手动输入',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ThemeColors.text(context),
                  ),
                ),
              ),
            ),
          ],
          thumb: Neumorphic(
            style: NeumorphicStyle(
              depth: -3,
              intensity: 0.6,
              boxShape: NeumorphicBoxShape.roundRect(
                BorderRadius.circular(8),
              ),
            ),
          ),
          onChanged: (index) {
            setState(() {
              _isQRMode = index == 0;
              _errorMessage = null;
              // 切换模式时重置扫描状态
              if (_isQRMode) {
                _qrScanned = false;
              }
            });
          },
        ),
      ),
    );
  }

  /// 二维码模式
  Widget _buildQRMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 服务器名称输入框（禁用）
        _buildInputField(
          label: '服务器名称',
          controller: _nameController,
          enabled: false,
        ),
        const SizedBox(height: 32),
        // 扫码和确认按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // QR Code 扫描按钮 - 圆形
            NeumorphicButton(
              onPressed: _isVerifying ? null : _scanQRCode,
              style: const NeumorphicStyle(
                depth: 4,
                intensity: 0.7,
                boxShape: NeumorphicBoxShape.circle(),
              ),
              padding: const EdgeInsets.all(24),
              child: Icon(
                Icons.qr_code_scanner,
                size: 32,
                color: ThemeColors.text(context),
              ),
            ),
            // 确认按钮（始终显示，因为已有预填数据）
            const SizedBox(width: 24),
            NeumorphicButton(
              onPressed: _isVerifying ? null : _updateServer,
              style: const NeumorphicStyle(
                depth: 4,
                intensity: 0.7,
                boxShape: NeumorphicBoxShape.circle(),
              ),
              padding: const EdgeInsets.all(24),
              child: _isVerifying
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.check,
                      size: 32,
                      color: ThemeColors.text(context),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// 手动输入模式
  Widget _buildManualMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 服务器名称（禁用）
        _buildInputField(
          label: '服务器名称',
          controller: _nameController,
          enabled: false,
        ),
        const SizedBox(height: 20),
        // 服务器地址
        _buildInputField(
          label: '服务器地址',
          controller: _urlController,
        ),
        const SizedBox(height: 20),
        // API Key
        _buildInputField(
          label: 'API Key',
          controller: _keyController,
          obscureText: true,
        ),
        const SizedBox(height: 32),
        // 确认按钮 - 圆形
        Center(
          child: NeumorphicButton(
            onPressed: _isVerifying ? null : _updateServer,
            style: const NeumorphicStyle(
              depth: 4,
              intensity: 0.7,
              boxShape: NeumorphicBoxShape.circle(),
            ),
            padding: const EdgeInsets.all(24),
            child: _isVerifying
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.check,
                    size: 32,
                    color: ThemeColors.text(context),
                  ),
          ),
        ),
      ],
    );
  }

  /// 输入框 - Neumorphic 下陷风格 带上方小字标签
  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ThemeColors.text(context),
          ),
        ),
        const SizedBox(height: 8),
        Neumorphic(
          style: NeumorphicStyle(
            depth: -4,
            intensity: 0.6,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(25)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            enabled: enabled,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '',
            ),
            style: TextStyle(
              fontSize: 14,
              color: enabled ? ThemeColors.text(context) : ThemeColors.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  /// 扫描二维码
  Future<void> _scanQRCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const _QRScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      // 解析二维码 URL: http://192.168.1.100:1234/login.html?key=xxx
      try {
        final uri = Uri.parse(result);
        final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
        final key = uri.queryParameters['key'];

        if (key != null) {
          setState(() {
            _urlController.text = baseUrl;
            _keyController.text = key;
            _qrScanned = true;
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = '二维码格式无效';
            _qrScanned = false;
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = '无法解析二维码：$e';
          _qrScanned = false;
        });
      }
    }
  }

  /// 更新服务器
  Future<void> _updateServer() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();

    // 验证输入
    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _errorMessage = _isQRMode ? '请先扫描二维码或使用现有配置' : '请填写所有字段';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      // 验证服务器
      final isValid = await ApiService.verifyApiKey(url, key);

      if (!isValid) {
        setState(() {
          _errorMessage = '验证失败：API Key 无效或服务器无法访问';
          _isVerifying = false;
        });
        return;
      }

      // 创建更新后的服务器对象
      final updatedServer = Server(
        id: widget.server.id,
        name: widget.server.name, // 保持原名称
        baseUrl: url,
        apiKey: key,
        addedAt: widget.server.addedAt,
      );

      // 更新服务器
      if (mounted) {
        final serverProvider = Provider.of<ServerProvider>(context, listen: false);
        await serverProvider.updateServer(updatedServer);

        // 清除图片缓存，确保使用新服务器地址重新加载图片
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '更新失败：$e';
        _isVerifying = false;
      });
    }
  }
}

/// 二维码扫描界面
class _QRScannerScreen extends StatefulWidget {
  const _QRScannerScreen();

  @override
  State<_QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<_QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false; // 防止 onDetect 多次触发导致多次 pop

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 相机预览层
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              // 如果已经扫描过，直接返回，防止多次 pop
              if (_hasScanned) return;

              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _hasScanned = true; // 标记已扫描
                  Navigator.of(context).pop(barcode.rawValue);
                  return;
                }
              }
            },
          ),
          // 扫描框遮罩层
          _buildScannerOverlay(),
          // 顶部栏 - 使用封装的组件
          NeumorphicOverlayAppBar(
            title: '扫描二维码',
            leading: NeumorphicCircleButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icons.arrow_back,
            ),
          ),
        ],
      ),
    );
  }

  /// 扫描框遮罩
  Widget _buildScannerOverlay() {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white.withOpacity(0.6),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
