import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/source_folder_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/server.dart';
import '../../models/source_folder.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/common/neumorphic_dialog.dart';
import '../../widgets/common/neumorphic_toast.dart';
import '../../widgets/settings/source_folder_dropdown.dart';
import '../server/server_list_screen.dart';
import '../source_folder/source_folder_list_screen.dart';

/// 设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSourceFolderDropdownOpen = false;
  double _dropdownTop = 0;
  String _version = '';
  String? _githubUrl;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    // 延迟到 build 完成后再加载数据，避免在 build 期间调用 notifyListeners()
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
      _loadAppConfig();
    });
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = 'v${packageInfo.version}';
        });
      }
    } catch (e) {
      print('加载版本号失败: $e');
      if (mounted) {
        setState(() {
          _version = '?';
        });
      }
    }
  }

  /// 加载初始数据：服务器状态和源文件夹列表
  Future<void> _loadInitialData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final serverProvider = Provider.of<ServerProvider>(context, listen: false);
    final sourceFolderProvider = Provider.of<SourceFolderProvider>(context, listen: false);

    // 重新初始化 AuthProvider 以获取最新的服务器信息
    await authProvider.initialize();

    // 检查当前服务器状态
    if (authProvider.currentServer != null) {
      await serverProvider.checkServerStatus(authProvider.currentServer!);
    }

    // 加载源文件夹列表
    if (authProvider.apiService != null) {
      await sourceFolderProvider.loadSourceFolders(authProvider.apiService!);
    }
  }

  /// 下拉刷新：重新加载所有数据
  Future<void> _handleRefresh() async {
    await _loadInitialData();
    await _loadAppConfig();
  }

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

  /// 加载 App 配置（获取 GitHub URL）
  Future<void> _loadAppConfig() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentServer != null) {
      final config = await ApiService.getAppConfig(authProvider.currentServer!.baseUrl);
      if (config != null && mounted) {
        setState(() {
          _githubUrl = config['github_url'];
        });
      }
    }
  }

  /// 打开 GitHub 页面
  Future<void> _openGitHub() async {
    if (_githubUrl == null || _githubUrl!.isEmpty) {
      NeumorphicToast.showError(context, '无法获取 GitHub 链接');
      return;
    }

    final url = Uri.parse(_githubUrl!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      NeumorphicToast.showError(context, '无法打开链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: SafeArea(
          child: Stack(
            children: [
              // 主内容
              Column(
                children: [
              // 标题
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: ThemeColors.text(context),
                      ),
                    ),
                  ],
                ),
              ),

              // 设置项列表
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: ThemeColors.text(context),
                  backgroundColor: NeumorphicTheme.baseColor(context),
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

                    const SizedBox(height: 24),

                    // 源文件夹标签
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Row(
                        children: [
                          Text(
                            '源文件夹',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 源文件夹选择器 - 下拉式设计
                    Consumer<SourceFolderProvider>(
                      builder: (context, folderProvider, child) {
                        return _buildSourceFolderSelector(context, folderProvider.currentSourceFolder);
                      },
                    ),

                    const SizedBox(height: 32),

                    // 语言选择 - 简约平放设计
                    _buildLanguageSelector(context),

                    const SizedBox(height: 24),

                    // 主题切换 - 简约平放设计
                    _buildThemeSelector(context),

                    const SizedBox(height: 32),

                    // GitHub 按钮
                    if (_githubUrl != null)
                      NeumorphicButton(
                        onPressed: _openGitHub,
                        style: NeumorphicStyle(
                          depth: 4,
                          intensity: 0.8,
                          boxShape: NeumorphicBoxShape.roundRect(
                            BorderRadius.circular(12),
                          ),
                          color: Theme.of(context).brightness == Brightness.light
                              ? Colors.black
                              : Colors.white,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/external_icon/github-mark.svg',
                              width: 20,
                              height: 20,
                              colorFilter: ColorFilter.mode(
                                Theme.of(context).brightness == Brightness.light
                                    ? Colors.white
                                    : Colors.black,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'GitHub',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness == Brightness.light
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_githubUrl != null) const SizedBox(height: 16),

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
                      child: Center(
                        child: Text(
                          '断开连接',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ThemeColors.text(context),
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
                            _version,
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
              ),
                ],
              ),

              // 遮罩层（点击关闭下拉菜单）
              if (_isSourceFolderDropdownOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _isSourceFolderDropdownOpen = false),
                    child: Container(color: Colors.black.withOpacity(0.3)),
                  ),
                ),

              // 源文件夹下拉菜单
              if (_isSourceFolderDropdownOpen)
                Positioned(
                  top: _dropdownTop,
                  left: 20,
                  right: 20,
                  child: SourceFolderDropdown(
                    onFolderChanged: () {
                      setState(() => _isSourceFolderDropdownOpen = false);
                    },
                  ),
                ),
            ],
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ThemeColors.text(context),
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
        Icon(Icons.language, size: 22, color: ThemeColors.textSecondary(context)),
        const SizedBox(width: 12),
        Text(
          '语言',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: ThemeColors.text(context),
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

  /// 简约主题选择器 - 平放设计
  Widget _buildThemeSelector(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Row(
          children: [
            Icon(Icons.brightness_6, size: 22, color: ThemeColors.textSecondary(context)),
            const SizedBox(width: 12),
            Text(
              '主题',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ThemeColors.text(context),
              ),
            ),
            const Spacer(),
            // 主题切换 Radio 组
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildThemeRadioIcon(context, ThemeMode.light, Icons.light_mode, themeProvider),
                const SizedBox(width: 12),
                _buildThemeRadioIcon(context, ThemeMode.dark, Icons.dark_mode, themeProvider),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 语言选择 Radio 按钮
  Widget _buildLanguageRadio(BuildContext context, String langCode, String label) {
    final isActive = context.locale.languageCode == langCode;

    return SizedBox(
      width: 56,
      child: NeumorphicButton(
        onPressed: () {
          context.setLocale(Locale(langCode));
        },
        style: NeumorphicStyle(
          depth: isActive ? -3 : 2,
          intensity: 0.7,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? ThemeColors.text(context) : ThemeColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }

  /// 主题选择 Radio 按钮（图标版）
  Widget _buildThemeRadioIcon(BuildContext context, ThemeMode mode, IconData icon, ThemeProvider themeProvider) {
    final isActive = themeProvider.themeMode == mode;

    return SizedBox(
      width: 56,
      child: NeumorphicButton(
        onPressed: () {
          themeProvider.setThemeMode(mode);
        },
        style: NeumorphicStyle(
          depth: isActive ? -3 : 2,
          intensity: 0.7,
          boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(8)),
        ),
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: isActive ? ThemeColors.text(context) : ThemeColors.textSecondary(context),
          ),
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

    // 返回后刷新服务器状态和源文件夹列表
    if (context.mounted) {
      await _loadInitialData();
    }
  }

  /// 源文件夹选择器 - 下拉式设计
  Widget _buildSourceFolderSelector(BuildContext context, SourceFolder? folder) {
    final folderName = folder?.displayName ?? '未配置';

    return NeumorphicButton(
      onPressed: () async {
        // 先加载源文件夹列表
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final apiService = ApiService(authProvider.currentServer!);
        final folderProvider = Provider.of<SourceFolderProvider>(context, listen: false);
        await folderProvider.loadSourceFolders(apiService);

        // 计算下拉菜单位置
        // 标题 padding: 20, 服务器卡片大约: 68, 间距: 24, 标签: 20, 按钮: 44
        const double headerPadding = 20;
        const double titleHeight = 28;
        const double titlePaddingBottom = 20;
        const double serverCardHeight = 68;
        const double spacing1 = 24;
        const double labelHeight = 20;
        const double buttonHeight = 44;

        final dropdownTop = headerPadding + titleHeight + titlePaddingBottom +
                           serverCardHeight + spacing1 + labelHeight + buttonHeight - 4; // 减去 4px 微调

        // 切换下拉菜单状态并更新位置
        setState(() {
          _dropdownTop = dropdownTop;
          _isSourceFolderDropdownOpen = !_isSourceFolderDropdownOpen;
        });
      },
      style: NeumorphicStyle(
        depth: _isSourceFolderDropdownOpen ? -2 : 2,
        intensity: 0.6,
        boxShape: NeumorphicBoxShape.roundRect(
          BorderRadius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 20,
            color: ThemeColors.text(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              folderName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ThemeColors.text(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            _isSourceFolderDropdownOpen ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: ThemeColors.textSecondary(context),
          ),
        ],
      ),
    );
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
