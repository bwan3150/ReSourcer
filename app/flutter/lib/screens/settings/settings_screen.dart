import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.logout();

      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          Constants.routeLogin,
          (route) => false,
        );
      }
    }
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
              // 标题
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: const [
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF171717),
                      ),
                    ),
                  ],
                ),
              ),

              // 设置项列表
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildSection(
                      context,
                      title: '账号信息',
                      children: [
                        Consumer<AuthProvider>(
                          builder: (context, provider, child) {
                            return _buildInfoItem(
                              context,
                              icon: Icons.link,
                              title: '服务地址',
                              value: provider.baseUrl ?? '未连接',
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Consumer<AuthProvider>(
                          builder: (context, provider, child) {
                            return _buildInfoItem(
                              context,
                              icon: Icons.vpn_key,
                              title: 'API Key',
                              value: provider.apiKey != null
                                  ? '${provider.apiKey!.substring(0, 8)}...'
                                  : '未设置',
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    _buildSection(
                      context,
                      title: '偏好设置',
                      children: [
                        _buildLanguageSelector(context),
                      ],
                    ),

                    const SizedBox(height: 24),

                    _buildSection(
                      context,
                      title: '关于',
                      children: [
                        _buildInfoItem(
                          context,
                          icon: Icons.info_outline,
                          title: '版本',
                          value: 'v1.0.0',
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // 退出登录按钮
                    NeumorphicButton(
                      onPressed: () => _handleLogout(context),
                      style: NeumorphicStyle(
                        depth: 4,
                        intensity: 0.8,
                        boxShape: NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(12),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: const Center(
                        child: Text(
                          '退出登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF737373),
            ),
          ),
        ),
        Neumorphic(
          style: NeumorphicStyle(
            depth: -2,
            intensity: 0.6,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF737373)),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF171717),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF737373),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.language, size: 20, color: Color(0xFF737373)),
        const SizedBox(width: 12),
        const Text(
          '语言',
          style: TextStyle(
            fontSize: 15,
            color: Color(0xFF171717),
          ),
        ),
        const Spacer(),
        Neumorphic(
          style: NeumorphicStyle(
            depth: 2,
            intensity: 0.6,
            boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLanguageButton(context, 'en', 'EN'),
              const SizedBox(width: 8),
              _buildLanguageButton(context, 'zh', '中文'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageButton(BuildContext context, String langCode, String label) {
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
