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
        body: AnimatedSwitcher(
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
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return SafeArea(
      child: Container(
        color: NeumorphicTheme.baseColor(context),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: NeumorphicToggle(
          height: 50,
          selectedIndex: _pageIndex,
          displayForegroundOnlyIfSelected: true,
          children: [
            // 画廊
            ToggleElement(
              background: Center(
                child: Icon(
                  Icons.photo_library_outlined,
                  size: 24,
                  color: const Color(0xFF737373),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.photo_library,
                      size: 24,
                      color: Color(0xFF171717),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '画廊',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF171717),
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
                  color: const Color(0xFF737373),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.category,
                      size: 24,
                      color: Color(0xFF171717),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '分类',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF171717),
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
                  color: const Color(0xFF737373),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.download,
                      size: 24,
                      color: Color(0xFF171717),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '下载',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF171717),
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
                  color: const Color(0xFF737373),
                ),
              ),
              foreground: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.settings,
                      size: 24,
                      color: Color(0xFF171717),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF171717),
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
    );
  }
}
