import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../utils/theme_colors.dart';
import '../gallery/gallery_screen.dart';
import '../classifier/classifier_screen.dart';
import '../downloader/downloader_screen.dart';
import '../settings/settings_screen.dart';

/// 主框架页面（带底部导航栏）
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = Constants.tabGallery; // 默认显示画廊

  // 4个主要页面
  final List<Widget> _pages = const [
    GalleryScreen(),        // 0: 画廊
    ClassifierScreen(),     // 1: 分类器
    DownloaderScreen(),     // 3: 下载器
    SettingsScreen(),       // 4: 设置
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用从后台回到前台时,检查认证状态
    if (state == AppLifecycleState.resumed) {
      _checkAuth();
    }
  }

  // 检查认证状态
  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.currentServer == null) {
      // 未登录,返回服务器列表
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/servers', (route) => false);
      }
      return;
    }

    // 检查服务器连接和认证
    final isHealthy = await ApiService.checkHealth(authProvider.currentServer!.baseUrl);
    if (!isHealthy) {
      // 服务器连接失败,返回服务器列表
      if (mounted) {
        await authProvider.logout();
        Navigator.of(context).pushNamedAndRemoveUntil('/servers', (route) => false);
      }
      return;
    }

    // 检查API Key是否有效
    final isAuthValid = await ApiService.checkAuth(
      authProvider.currentServer!.baseUrl,
      authProvider.currentServer!.apiKey,
    );
    if (!isAuthValid) {
      // API Key失效,返回服务器列表
      if (mounted) {
        await authProvider.logout();
        Navigator.of(context).pushNamedAndRemoveUntil('/servers', (route) => false);
      }
    }
  }

  // 对应的实际索引映射（因为索引2预留）
  final List<int> _indexMap = const [
    Constants.tabGallery,      // 0 -> 0
    Constants.tabClassifier,   // 1 -> 1
    Constants.tabDownloader,   // 2 -> 3
    Constants.tabSettings,     // 3 -> 4
  ];

  void _onTabTapped(int actualIndex) {
    // 找到对应的页面索引
    final pageIndex = _indexMap.indexOf(actualIndex);
    if (pageIndex != -1) {
      setState(() {
        _currentIndex = actualIndex;
      });
    }
  }

  int get _pageIndex => _indexMap.indexOf(_currentIndex);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor(context),
      body: Stack(
        children: [
          // 页面内容
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: Container(
              key: ValueKey<int>(_pageIndex),
              child: _pages[_pageIndex],
            ),
          ),
          // 底部导航栏（浮动）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNavigationBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: NeumorphicTheme.baseColor(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: NeumorphicToggle(
            height: 60,
            selectedIndex: _pageIndex,
            displayForegroundOnlyIfSelected: true,
          children: [
            // 画廊
            ToggleElement(
              background: Center(
                child: Icon(
                  Icons.photo_library_outlined,
                  size: 24,
                  color: ThemeColors.textSecondary(context),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library,
                      size: 24,
                      color: ThemeColors.text(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '画廊',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 分类器
            ToggleElement(
              background: Center(
                child: Icon(
                  Icons.category_outlined,
                  size: 24,
                  color: ThemeColors.textSecondary(context),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.category,
                      size: 24,
                      color: ThemeColors.text(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '分类',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 下载器
            ToggleElement(
              background: Center(
                child: Icon(
                  Icons.download_outlined,
                  size: 24,
                  color: ThemeColors.textSecondary(context),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.download,
                      size: 24,
                      color: ThemeColors.text(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '下载',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 设置
            ToggleElement(
              background: Center(
                child: Icon(
                  Icons.settings_outlined,
                  size: 24,
                  color: ThemeColors.textSecondary(context),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.settings,
                      size: 24,
                      color: ThemeColors.text(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeColors.text(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          thumb: Neumorphic(
            style: NeumorphicStyle(
              depth: -3,
              intensity: 0.6,
              boxShape: NeumorphicBoxShape.roundRect(
                BorderRadius.circular(12),
              ),
            ),
          ),
          onChanged: (index) {
            final actualIndex = _indexMap[index];
            _onTabTapped(actualIndex);
          },
            ),
          ),
        ),
      ),
    );
  }
}
