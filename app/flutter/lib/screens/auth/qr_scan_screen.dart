import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

/// 二维码扫描页面
class QRScanScreen extends StatefulWidget {
  const QRScanScreen({Key? key}) : super(key: key);

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 处理扫描结果
  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 解析二维码内容，格式: http://192.168.1.100:8080?key=xxx
      final url = Uri.parse(barcode.rawValue!);
      final baseUrl = '${url.scheme}://${url.host}:${url.port}';
      final apiKey = url.queryParameters['key'];

      if (apiKey == null || apiKey.isEmpty) {
        _showError('二维码格式错误');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // 登录
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(baseUrl, apiKey);

      if (mounted) {
        if (success) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            Constants.routeHome,
            (route) => false,
          );
        } else {
          _showError('登录失败，请检查服务是否可用');
          setState(() {
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      _showError('二维码解析失败: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicTheme(
      theme: const NeumorphicThemeData(
        baseColor: Color(0xFF171717),
        lightSource: LightSource.topLeft,
        depth: 4,
        intensity: 0.6,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: NeumorphicAppBar(
          title: const Text('扫描二维码'),
          leading: NeumorphicButton(
            onPressed: () => Navigator.of(context).pop(),
            style: const NeumorphicStyle(
              boxShape: NeumorphicBoxShape.circle(),
              depth: 2,
            ),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.arrow_back),
          ),
        ),
        body: Stack(
          children: [
            // 扫描区域
            MobileScanner(
              controller: _controller,
              onDetect: _handleBarcode,
            ),

            // 扫描框
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            // 提示文字
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Neumorphic(
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.8,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(12),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: const Text(
                      '将二维码放入框内扫描\n请确保后端服务已启动',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF171717),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 加载指示器
            if (_isProcessing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
