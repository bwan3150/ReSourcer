import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'providers/auth_provider.dart';
import 'providers/server_provider.dart';
import 'providers/gallery_provider.dart';
import 'providers/upload_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/source_folder_provider.dart';
import 'providers/classifier_provider.dart';
import 'screens/server/server_list_screen.dart';
import 'screens/home/home_screen.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // 初始化 media_kit
  MediaKit.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GalleryProvider()),
        ChangeNotifierProvider(create: (_) => UploadProvider()),
        ChangeNotifierProvider(create: (_) => SourceFolderProvider()),
        ChangeNotifierProvider(create: (_) => ClassifierProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return NeumorphicApp(
            title: 'app_name'.tr(),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            themeMode: themeProvider.themeMode,
            theme: const NeumorphicThemeData(
              baseColor: Color(0xFFF0F0F0),
              lightSource: LightSource.topLeft,
              depth: 4,
              intensity: 0.6,
            ),
            darkTheme: const NeumorphicThemeData(
              baseColor: Color(0xFF333333),
              lightSource: LightSource.topLeft,
              depth: 6,
              intensity: 0.4,
            ),
            home: const AppInitializer(),
            routes: {
              '/servers': (context) => const ServerListScreen(),
              '/home': (context) => const HomeScreen(),
            },
          );
        },
      ),
    );
  }
}

/// 应用初始化器 - 检查登录状态
class AppInitializer extends StatefulWidget {
  const AppInitializer({Key? key}) : super(key: key);

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initialize();

    if (mounted) {
      if (authProvider.isLoggedIn) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/servers');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF171717)),
        ),
      ),
    );
  }
}
