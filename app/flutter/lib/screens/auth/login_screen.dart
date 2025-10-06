import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

/// 登录页面
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 处理登录
  Future<void> _handleLogin() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      setState(() {
        _errorMessage = '请输入服务地址和 API Key';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.login(baseUrl, apiKey);

    if (mounted) {
      if (success) {
        Navigator.of(context).pushReplacementNamed(Constants.routeHome);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '登录失败，请检查服务地址和 API Key';
        });
      }
    }
  }

  /// 扫描二维码
  void _handleScanQR() {
    Navigator.of(context).pushNamed(Constants.routeQrScan);
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
          child: Stack(
            children: [
              // 语言切换按钮（右上角）
              Positioned(
                top: 20,
                right: 20,
                child: _buildLanguageSwitcher(),
              ),

              // 登录内容
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo 和标题
                      _buildHeader(),
                  const SizedBox(height: 48),

                  // 输入框区域
                  _buildInputCard(),
                  const SizedBox(height: 24),

                  // 错误提示
                  if (_errorMessage != null) _buildErrorMessage(),
                  if (_errorMessage != null) const SizedBox(height: 16),

                  // 登录按钮
                  _buildLoginButton(),
                  const SizedBox(height: 16),

                  // 扫描二维码按钮
                  _buildScanButton(),
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

  Widget _buildHeader() {
    return Column(
      children: [
        Neumorphic(
          style: NeumorphicStyle(
            shape: NeumorphicShape.concave,
            boxShape: const NeumorphicBoxShape.circle(),
            depth: 8,
            intensity: 0.8,
          ),
          child: Container(
            width: 100,
            height: 100,
            alignment: Alignment.center,
            child: const Icon(
              Icons.folder_open,
              size: 50,
              color: Color(0xFF404040),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'ReSourcer',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF171717),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '请先启动后端服务',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildInputCard() {
    return Neumorphic(
      style: NeumorphicStyle(
        depth: -4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 服务地址输入框
          _buildInputField(
            controller: _baseUrlController,
            label: '服务地址',
            hint: 'http://192.168.1.100:8080',
            icon: Icons.link,
          ),
          const SizedBox(height: 20),

          // API Key 输入框
          _buildInputField(
            controller: _apiKeyController,
            label: 'API Key',
            hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
            icon: Icons.vpn_key,
            obscure: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF525252),
          ),
        ),
        const SizedBox(height: 8),
        Neumorphic(
          style: NeumorphicStyle(
            depth: -2,
            intensity: 0.6,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, color: Colors.grey[400]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Neumorphic(
      style: NeumorphicStyle(
        depth: -2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.all(12),
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
    );
  }

  Widget _buildLoginButton() {
    return NeumorphicButton(
      onPressed: _isLoading ? null : _handleLogin,
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                '登录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF171717),
                ),
              ),
      ),
    );
  }

  Widget _buildScanButton() {
    return NeumorphicButton(
      onPressed: _isLoading ? null : _handleScanQR,
      style: NeumorphicStyle(
        depth: 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF525252)),
          SizedBox(width: 8),
          Text(
            '扫描二维码',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF525252),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSwitcher() {
    return Neumorphic(
      style: NeumorphicStyle(
        depth: 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLanguageButton('en', 'EN'),
          const SizedBox(width: 8),
          _buildLanguageButton('zh', '中文'),
        ],
      ),
    );
  }

  Widget _buildLanguageButton(String langCode, String label) {
    final isActive = context.locale.languageCode == langCode;

    return NeumorphicButton(
      onPressed: () {
        context.setLocale(Locale(langCode));
      },
      style: NeumorphicStyle(
        depth: isActive ? -2 : 1,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(6)),
        color: isActive ? const Color(0xFF171717) : Colors.transparent,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isActive ? Colors.white : const Color(0xFF525252),
        ),
      ),
    );
  }
}
