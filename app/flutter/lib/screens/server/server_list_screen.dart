import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/server.dart';
import '../../providers/server_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import 'add_server_screen.dart';

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
    return NeumorphicTheme(
      theme: const NeumorphicThemeData(
        baseColor: Color(0xFFF0F0F0),
        lightSource: LightSource.topLeft,
        depth: 4,
        intensity: 0.6,
      ),
      child: Scaffold(
        backgroundColor: NeumorphicTheme.baseColor(context),
        appBar: NeumorphicAppBar(
          title: const Text(
            '服务器管理',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF171717),
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
          actions: [
            NeumorphicButton(
              onPressed: () => _showStatusHelp(context),
              style: const NeumorphicStyle(
                boxShape: NeumorphicBoxShape.circle(),
                depth: 3,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(Icons.help_outline, size: 20),
            ),
          ],
        ),
        body: Consumer<ServerProvider>(
          builder: (context, provider, child) {
            if (provider.servers.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: () => provider.checkAllServers(),
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
      ),
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
            const Text(
              '状态说明',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF171717),
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
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF171717),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NeumorphicButton(
        onPressed: status == ServerStatus.online && !isCurrent
            ? () => _switchServer(server)
            : null,
        style: NeumorphicStyle(
          depth: isCurrent ? -4 : 4,
          intensity: 0.6,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF171717),
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
        ),
      ),
    );
  }

  /// 状态指示灯
  Widget _buildStatusIndicator(Color color, ServerStatus status) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
          ),
        ),
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: status == ServerStatus.checking
                ? []
                : [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
          ),
        ),
      ],
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '还没有添加服务器',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮添加服务器',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
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
      child: const Icon(
        Icons.add,
        size: 32,
        color: Color(0xFF171717),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                server.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF171717),
                ),
              ),
            ),
            const Divider(),
            // 重命名（暂未实现）
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF737373)),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoonDialog();
              },
            ),
            // 更新 API Key（暂未实现）
            ListTile(
              leading: const Icon(Icons.vpn_key, color: Color(0xFF737373)),
              title: const Text('更新 API Key'),
              onTap: () {
                Navigator.pop(context);
                _showComingSoonDialog();
              },
            ),
            // 删除
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteServer(server);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 功能即将推出提示
  void _showComingSoonDialog() {
    NeumorphicDialog.showInfo(
      context: context,
      title: '即将推出',
      content: '此功能即将在未来版本中推出',
    );
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
