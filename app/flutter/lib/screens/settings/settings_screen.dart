import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';
import '../../models/server.dart';
import '../../utils/constants.dart';
import '../server/server_list_screen.dart';

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
          '/servers',
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
                      title: '服务器',
                      children: [
                        // 当前服务器信息
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, child) {
                            final server = authProvider.currentServer;
                            if (server == null) {
                              return _buildInfoItem(
                                context,
                                icon: Icons.dns_outlined,
                                title: '当前服务器',
                                value: '未连接',
                              );
                            }

                            return Column(
                              children: [
                                _buildInfoItem(
                                  context,
                                  icon: Icons.dns,
                                  title: '当前服务器',
                                  value: server.name,
                                ),
                                const SizedBox(height: 12),
                                _buildInfoItem(
                                  context,
                                  icon: Icons.link,
                                  title: '服务地址',
                                  value: server.baseUrl,
                                ),
                                const SizedBox(height: 12),
                                Consumer<ServerProvider>(
                                  builder: (context, serverProvider, child) {
                                    final status = serverProvider.getServerStatus(server.id);
                                    return _buildServerStatusItem(context, status);
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFE0E0E0)),
                        const SizedBox(height: 12),
                        // 服务器管理按钮
                        _buildActionItem(
                          context,
                          icon: Icons.settings_outlined,
                          title: '服务器管理',
                          onTap: () => _navigateToServerManagement(context),
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

  /// 服务器状态显示项
  Widget _buildServerStatusItem(BuildContext context, ServerStatus status) {
    Color statusColor;
    String statusText;

    switch (status) {
      case ServerStatus.online:
        statusColor = Colors.green;
        statusText = '在线';
        break;
      case ServerStatus.authError:
        statusColor = Colors.orange;
        statusText = 'API Key 无效';
        break;
      case ServerStatus.offline:
        statusColor = Colors.red;
        statusText = '离线';
        break;
      case ServerStatus.checking:
        statusColor = Colors.grey;
        statusText = '检查中...';
        break;
    }

    return Row(
      children: [
        const Icon(Icons.circle, size: 20, color: Color(0xFF737373)),
        const SizedBox(width: 12),
        const Text(
          '服务器状态',
          style: TextStyle(
            fontSize: 15,
            color: Color(0xFF171717),
          ),
        ),
        const Spacer(),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor,
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 14,
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// 可点击的操作项
  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF737373)),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF171717),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: Color(0xFF737373),
            ),
          ],
        ),
      ),
    );
  }

  /// 跳转到服务器管理页面
  Future<void> _navigateToServerManagement(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ServerListScreen(),
      ),
    );

    // 返回后刷新服务器状态
    if (context.mounted) {
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      await serverProvider.checkAllServers();
    }
  }
}
