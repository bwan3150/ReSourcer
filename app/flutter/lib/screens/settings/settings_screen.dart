import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';
import '../../models/server.dart';
import '../../utils/constants.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../server/server_list_screen.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await NeumorphicDialog.showConfirm(
      context: context,
      title: '断开连接',
      content: '确定要断开当前服务器连接吗？',
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
                    // 服务器卡片 - 简约设计，只显示名字和状态灯
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        final server = authProvider.currentServer;
                        return Consumer<ServerProvider>(
                          builder: (context, serverProvider, child) {
                            final status = server != null
                                ? serverProvider.getServerStatus(server.id)
                                : ServerStatus.offline;
                            return _buildServerCard(context, server, status);
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // 语言选择 - 简约平放设计
                    _buildLanguageSelector(context),

                    const SizedBox(height: 32),

                    // 断开连接按钮
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
                          '断开连接',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF171717),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 版本号 - 简约显示
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'v1.0.0',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 简约服务器卡片 - 只显示名字和状态灯
  Widget _buildServerCard(BuildContext context, Server? server, ServerStatus status) {
    final statusColor = _getStatusColor(status);
    final serverName = server?.name ?? '未连接';

    return NeumorphicButton(
      onPressed: () => _navigateToServerManagement(context),
      style: NeumorphicStyle(
        depth: 4,
        intensity: 0.8,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // 动态涟漪状态灯
          _buildStatusIndicator(statusColor, status),
          const SizedBox(width: 16),
          // 服务器名字
          Expanded(
            child: Text(
              serverName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF171717),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 右箭头指示
          Icon(
            Icons.chevron_right,
            size: 24,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  /// 动态状态指示灯（带涟漪效果）
  Widget _buildStatusIndicator(Color color, ServerStatus status) {
    return _AnimatedStatusIndicator(color: color, status: status);
  }

  /// 获取状态颜色
  Color _getStatusColor(ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return Colors.green;
      case ServerStatus.authError:
        return Colors.orange;
      case ServerStatus.offline:
        return Colors.red;
      case ServerStatus.checking:
        return Colors.grey;
    }
  }

  /// 简约语言选择器 - 平放设计
  Widget _buildLanguageSelector(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.language, size: 22, color: Color(0xFF737373)),
        const SizedBox(width: 12),
        const Text(
          '语言',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFF171717),
          ),
        ),
        const Spacer(),
        // NeumorphicRadio 组
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageRadio(context, 'en', 'EN'),
            const SizedBox(width: 12),
            _buildLanguageRadio(context, 'zh', '中文'),
          ],
        ),
      ],
    );
  }

  /// 语言选择 Radio 按钮
  Widget _buildLanguageRadio(BuildContext context, String langCode, String label) {
    final isActive = context.locale.languageCode == langCode;

    return NeumorphicButton(
      onPressed: () {
        context.setLocale(Locale(langCode));
      },
      style: NeumorphicStyle(
        depth: isActive ? -3 : 2,
        intensity: 0.7,
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: isActive ? const Color(0xFF171717) : const Color(0xFF737373),
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

/// 带动画的状态指示灯
class _AnimatedStatusIndicator extends StatefulWidget {
  final Color color;
  final ServerStatus status;

  const _AnimatedStatusIndicator({
    required this.color,
    required this.status,
  });

  @override
  State<_AnimatedStatusIndicator> createState() => _AnimatedStatusIndicatorState();
}

class _AnimatedStatusIndicatorState extends State<_AnimatedStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // 外层涟漪 - 带呼吸动画
              Container(
                width: 24 * _animation.value,
                height: 24 * _animation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.2),
                ),
              ),
              // 内层光点
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: widget.status == ServerStatus.checking
                      ? []
                      : [
                          BoxShadow(
                            color: widget.color.withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
