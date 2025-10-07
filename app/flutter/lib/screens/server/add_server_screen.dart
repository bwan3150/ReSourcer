import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/server.dart';
import '../../providers/server_provider.dart';
import '../../services/api_service.dart';

/// 添加服务器界面
class AddServerScreen extends StatefulWidget {
  const AddServerScreen({Key? key}) : super(key: key);

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicTheme(
      theme: const NeumorphicThemeData(
        baseColor: Color(0xFFF0F0F0),
        lightSource: LightSource.topLeft,
        depth: 4,
        intensity: 0.6,
      ),
      child: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(
                        controller: _nameController,
                        label: '服务器名称',
                        hint: '例如：我的电脑',
                        icon: Icons.label_outline,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _urlController,
                        label: '服务器地址',
                        hint: 'http://192.168.1.100:1234',
                        icon: Icons.link,
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _keyController,
                        label: 'API Key',
                        hint: '粘贴 API Key',
                        icon: Icons.key,
                        obscureText: true,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      _buildAddButton(),
                      const SizedBox(height: 16),
                      _buildQRScanButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题栏
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          NeumorphicButton(
            onPressed: () => Navigator.of(context).pop(),
            style: const NeumorphicStyle(
              boxShape: NeumorphicBoxShape.circle(),
              depth: 3,
            ),
            padding: const EdgeInsets.all(12),
            child: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: 16),
          const Text(
            '添加服务器',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF171717),
            ),
          ),
        ],
      ),
    );
  }

  /// 输入框
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF171717),
          ),
        ),
        const SizedBox(height: 8),
        Neumorphic(
          style: NeumorphicStyle(
            depth: -4,
            intensity: 0.8,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ],
    );
  }

  /// 添加按钮
  Widget _buildAddButton() {
    return NeumorphicButton(
      onPressed: _isVerifying ? null : _addServer,
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
        color: _isVerifying ? Colors.grey[300] : const Color(0xFF4CAF50),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: _isVerifying
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text(
              '添加服务器',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
    );
  }

  /// 扫码按钮
  Widget _buildQRScanButton() {
    return NeumorphicButton(
      onPressed: _scanQRCode,
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.qr_code_scanner, size: 20),
          SizedBox(width: 8),
          Text(
            '扫描二维码',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 添加服务器
  Future<void> _addServer() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();

    // 验证输入
    if (name.isEmpty || url.isEmpty || key.isEmpty) {
      setState(() {
        _errorMessage = '请填写所有字段';
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

      // 创建服务器对象
      final server = Server(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        baseUrl: url,
        apiKey: key,
        addedAt: DateTime.now(),
      );

      // 添加到列表
      if (mounted) {
        final serverProvider = Provider.of<ServerProvider>(context, listen: false);
        await serverProvider.addServer(server);

        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '添加失败：$e';
        _isVerifying = false;
      });
    }
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
          _urlController.text = baseUrl;
          _keyController.text = key;
        } else {
          setState(() {
            _errorMessage = '二维码格式无效';
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = '无法解析二维码：$e';
        });
      }
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.of(context).pop(barcode.rawValue);
              return;
            }
          }
        },
      ),
    );
  }
}
