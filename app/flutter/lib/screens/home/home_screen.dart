import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import '../../utils/constants.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = Constants.tabGallery; // 默认显示画廊

  // 4个主要页面
  final List<Widget> _pages = const [
    GalleryScreen(),        // 0: 画廊
    ClassifierScreen(),     // 1: 分类器
    DownloaderScreen(),     // 3: 下载器
    SettingsScreen(),       // 4: 设置
  ];

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
    return NeumorphicTheme(
      theme: const NeumorphicThemeData(
        baseColor: Color(0xFFF0F0F0),
        lightSource: LightSource.topLeft,
        depth: 4,
        intensity: 0.6,
      ),
      child: Scaffold(
        body: IndexedStack(
          index: _pageIndex,
          children: _pages,
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: Constants.tabGallery,
                icon: Icons.photo_library_outlined,
                activeIcon: Icons.photo_library,
                label: '画廊',
              ),
              _buildNavItem(
                index: Constants.tabClassifier,
                icon: Icons.category_outlined,
                activeIcon: Icons.category,
                label: '分类器',
              ),
              _buildNavItem(
                index: Constants.tabDownloader,
                icon: Icons.download_outlined,
                activeIcon: Icons.download,
                label: '下载器',
              ),
              _buildNavItem(
                index: Constants.tabSettings,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isActive
              ? NeumorphicTheme.baseColor(context)
              : Colors.transparent,
        ),
        child: isActive
            ? Neumorphic(
                style: NeumorphicStyle(
                  depth: -2,
                  intensity: 0.6,
                  boxShape: NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      activeIcon,
                      size: 24,
                      color: const Color(0xFF171717),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF171717),
                      ),
                    ),
                  ],
                ),
              )
            : Icon(
                icon,
                size: 24,
                color: const Color(0xFF737373),
              ),
      ),
    );
  }
}
