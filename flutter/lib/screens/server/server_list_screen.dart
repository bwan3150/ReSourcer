import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/server.dart';
import '../../providers/server_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../../widgets/common/neumorphic_option_sheet.dart';
import 'add_server_screen.dart';
import 'rebind_server_screen.dart';

/// 服务器列表管理界面
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({Key? key}) : super(key: key);

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  @override
  void initState() {
    super.initState();
    // 初始化服务器列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      serverProvider.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否已登录（有当前服务器）
    final authProvider = Provider.of<AuthProvider>(context);
    final hasCurrentServer = authProvider.currentServer != null;

    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      appBar: NeumorphicAppBar(
          title: Text(
            '服务器列表',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: ThemeColors.text(context),
            ),
          ),
          leading: hasCurrentServer
              ? NeumorphicButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: const NeumorphicStyle(
                    boxShape: NeumorphicBoxShape.circle(),
                    depth: 3,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.arrow_back, size: 20),
                )
              : null,
          actions: hasCurrentServer
              ? [
                  NeumorphicButton(
                    onPressed: () => _showStatusHelp(context),
                    style: const NeumorphicStyle(
                      boxShape: NeumorphicBoxShape.circle(),
                      depth: 3,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.help_outline, size: 20),
                  ),
                ]
              : null,
        ),
        body: Consumer<ServerProvider>(
          builder: (context, provider, child) {
            if (provider.servers.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: () => provider.checkAllServers(),
              backgroundColor: NeumorphicTheme.baseColor(context),
              color: ThemeColors.text(context),
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: provider.servers.length + 1, // +1 for footer
                itemBuilder: (context, index) {
                  // 最后一项显示在线统计
                  if (index == provider.servers.length) {
                    return _buildServerCountFooter(provider);
                  }

                  final server = provider.servers[index];
                  final status = provider.getServerStatus(server.id);
                  final isCurrent = Provider.of<AuthProvider>(context)
                      .currentServer?.id == server.id;

                  return _buildServerCard(
                    server,
                    status,
                    isCurrent,
                  );
                },
              ),
            );
          },
        ),
        floatingActionButton: _buildAddButton(),
      );
  }

  /// 显示状态帮助提示
  void _showStatusHelp(BuildContext context) {
    NeumorphicDialog.showCustom(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '状态说明',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ThemeColors.text(context),
              ),
            ),
            const SizedBox(height: 20),
            _buildStatusHelpItem(Colors.green, '在线 - 可用'),
            const SizedBox(height: 12),
            _buildStatusHelpItem(Colors.orange, '需要重新扫码或输入 API Key'),
            const SizedBox(height: 12),
            _buildStatusHelpItem(Colors.red, '服务不可用'),
            const SizedBox(height: 12),
            _buildStatusHelpItem(Colors.grey, '正在检查'),
            const SizedBox(height: 16),
            Text(
              '长按服务器卡片可进入编辑页面',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            // OK 按钮
            Center(
              child: NeumorphicButton(
                onPressed: () => Navigator.pop(context),
                style: NeumorphicStyle(
                  depth: 4,
                  intensity: 0.7,
                  boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(12)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ThemeColors.text(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHelpItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  /// 在线服务器统计 Footer
  Widget _buildServerCountFooter(ServerProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.link,
              size: 14,
              color: Colors.grey[500],
            ),
            const SizedBox(width: 6),
            Text(
              '${provider.onlineServerCount}/${provider.servers.length}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 服务器卡片 - 简约设计：状态灯+名字+地址
  Widget _buildServerCard(Server server, ServerStatus status, bool isCurrent) {
    final statusColor = _getStatusColor(status);

    // 服务器卡片内容
    final cardContent = GestureDetector(
      onLongPress: () => _editServer(server),
      child: Row(
        children: [
          // 状态指示灯
          _buildStatusIndicator(statusColor, status),
          const SizedBox(width: 16),
          // 服务器名称和地址
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: ThemeColors.text(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  server.baseUrl,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: isCurrent
          ? // 当前服务器 - 使用静态 Neumorphic 显示下陷状态
          Neumorphic(
              style: NeumorphicStyle(
                depth: -4,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
              ),
              padding: const EdgeInsets.all(20),
              child: cardContent,
            )
          : // 其他服务器 - 使用 NeumorphicButton 提供点击反馈
          NeumorphicButton(
              onPressed: status == ServerStatus.online
                  ? () => _switchServer(server)
                  : null,
              style: NeumorphicStyle(
                depth: 4,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
              ),
              padding: const EdgeInsets.all(20),
              child: cardContent,
            ),
    );
  }

  /// 状态指示灯
  Widget _buildStatusIndicator(Color color, ServerStatus status) {
    return _AnimatedStatusIndicator(color: color, status: status);
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Neumorphic(
              style: NeumorphicStyle(
                depth: -8,
                intensity: 0.8,
                boxShape: const NeumorphicBoxShape.circle(),
              ),
              padding: const EdgeInsets.all(20),
              child: NeumorphicIcon(
                Icons.dns_outlined,
                size: 80,
                style: NeumorphicStyle(
                  color: Colors.grey[400],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '点击下方按钮添加服务器',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 添加服务器按钮
  Widget _buildAddButton() {
    return NeumorphicFloatingActionButton(
      onPressed: _addServer,
      style: NeumorphicStyle(
        depth: 6,
        intensity: 0.8,
        boxShape: const NeumorphicBoxShape.circle(),
        color: NeumorphicTheme.baseColor(context),
      ),
      child: Icon(
        Icons.add,
        size: 32,
        color: ThemeColors.text(context),
      ),
    );
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

  /// 编辑服务器 - 长按后显示选项
  Future<void> _editServer(Server server) async {
    NeumorphicOptionSheet.show(
      context: context,
      title: server.name,
      options: [
        SheetOption(
          icon: Icons.edit,
          text: '重命名',
          onTap: () => _showRenameDialog(server),
        ),
        SheetOption(
          icon: Icons.refresh,
          text: '重新绑定服务器',
          onTap: () => _rebindServer(server),
        ),
        SheetOption(
          icon: Icons.delete_outline,
          text: '删除',
          textColor: ThemeColors.textSecondary(context),
          iconColor: ThemeColors.textSecondary(context),
          onTap: () => _deleteServer(server),
        ),
      ],
    );
  }

  /// 显示重命名对话框
  void _showRenameDialog(Server server) {
    final controller = TextEditingController(text: server.name);

    NeumorphicDialog.showCustom<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '重命名服务器',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ThemeColors.text(context),
              ),
            ),
            const SizedBox(height: 20),
            Neumorphic(
              style: NeumorphicStyle(
                depth: -2,
                intensity: 0.6,
                boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(10)),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  fontSize: 16,
                  color: ThemeColors.text(context),
                ),
                decoration: InputDecoration(
                  hintText: '输入新名称',
                  hintStyle: TextStyle(
                    color: ThemeColors.textSecondary(context),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context);
                    _renameServer(server, value.trim());
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NeumorphicButton(
                  onPressed: () => Navigator.pop(context),
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(10),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ThemeColors.textSecondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                NeumorphicButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context);
                      _renameServer(server, name);
                    }
                  },
                  style: NeumorphicStyle(
                    depth: 4,
                    intensity: 0.7,
                    boxShape: NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(10),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Text(
                    '确定',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ThemeColors.text(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 重命名服务器
  Future<void> _renameServer(Server server, String newName) async {
    final serverProvider = Provider.of<ServerProvider>(context, listen: false);
    await serverProvider.renameServer(server.id, newName);
  }

  /// 重新绑定服务器
  Future<void> _rebindServer(Server server) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RebindServerScreen(server: server),
      ),
    );

    // 刷新列表
    if (mounted) {
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      await serverProvider.initialize();
    }
  }

  /// 切换服务器
  Future<void> _switchServer(Server server) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // 先切换服务器（这会触发 Provider 通知，卡片会下陷）
    final success = await authProvider.switchToServer(server);

    if (success && mounted) {
      // 等待一小段时间让用户看到下陷反馈效果
      await Future.delayed(const Duration(milliseconds: 300));

      // 然后跳转到画廊页面
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  /// 添加服务器
  Future<void> _addServer() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddServerScreen(),
      ),
    );

    // 刷新列表
    if (mounted) {
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      await serverProvider.initialize();
    }
  }

  /// 删除服务器
  Future<void> _deleteServer(Server server) async {
    final confirm = await NeumorphicDialog.showConfirm(
      context: context,
      title: '确认删除',
      content: '确定要删除服务器 "${server.name}" 吗？',
      confirmText: '删除',
      confirmTextColor: Colors.red,
    );

    if (confirm == true && mounted) {
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      await serverProvider.deleteServer(server.id);
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
