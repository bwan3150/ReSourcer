import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../models/server.dart';
import '../../providers/server_provider.dart';
import '../../providers/auth_provider.dart';
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
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: Consumer<ServerProvider>(
                  builder: (context, provider, child) {
                    if (provider.servers.isEmpty) {
                      return _buildEmptyState();
                    }

                    return RefreshIndicator(
                      onRefresh: () => provider.checkAllServers(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: provider.servers.length,
                        itemBuilder: (context, index) {
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
              ),
            ],
          ),
        ),
        floatingActionButton: _buildAddButton(),
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Text(
            '服务器管理',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF171717),
            ),
          ),
          const Spacer(),
          Consumer<ServerProvider>(
            builder: (context, provider, child) {
              return Text(
                '${provider.onlineServerCount}/${provider.servers.length} 在线',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 服务器卡片
  Widget _buildServerCard(Server server, ServerStatus status, bool isCurrent) {
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Neumorphic(
        style: NeumorphicStyle(
          depth: isCurrent ? -4 : 4,
          intensity: 0.6,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(16)),
        ),
        child: InkWell(
          onTap: status == ServerStatus.online ? () => _switchServer(server) : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 状态指示灯
                    _buildStatusIndicator(statusColor, status),
                    const SizedBox(width: 12),
                    // 服务器名称
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                server.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF171717),
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '当前',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                    // 删除按钮
                    NeumorphicButton(
                      onPressed: () => _deleteServer(server),
                      style: const NeumorphicStyle(
                        boxShape: NeumorphicBoxShape.circle(),
                        depth: 2,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 状态文本
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
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

  /// 获取状态文本
  String _getStatusText(ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return '● 在线 - 可用';
      case ServerStatus.authError:
        return '● API Key 无效 - 需要更新';
      case ServerStatus.offline:
        return '● 离线 - 服务器未运行';
      case ServerStatus.checking:
        return '● 检查中...';
    }
  }

  /// 切换服务器
  Future<void> _switchServer(Server server) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.switchToServer(server);

    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除服务器 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final serverProvider = Provider.of<ServerProvider>(context, listen: false);
      await serverProvider.deleteServer(server.id);
    }
  }
}
