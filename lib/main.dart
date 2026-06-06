import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'database/database.dart';
import 'providers/house_provider.dart';
import 'providers/item_provider.dart';
import 'providers/space_provider.dart';
import 'providers/category_provider.dart';
import 'providers/tag_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/attribute_provider.dart';
import 'providers/notification_provider.dart';
import 'pages/home_page.dart';
import 'pages/home/expired_items_page.dart';
import 'pages/notification/notification_page.dart';
import 'utils/app_info.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SplashScreen());
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      locale: Locale('zh', 'CN'),
      home: _SimpleLoadingScreen(),
    );
  }
}

class _SimpleLoadingScreen extends StatefulWidget {
  const _SimpleLoadingScreen();

  @override
  State<_SimpleLoadingScreen> createState() => _SimpleLoadingScreenState();
}

class _SimpleLoadingScreenState extends State<_SimpleLoadingScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      
      final db = AppDatabase();
      final houseProvider = HouseProvider(db);
      final attributeProvider = AttributeProvider(db);
      final itemProvider = ItemProvider(db);
      final spaceProvider = SpaceProvider(db);
      final categoryProvider = CategoryProvider(db);
      final tagProvider = TagProvider(db);
      final settingsProvider = SettingsProvider();
      final notificationProvider = NotificationProvider(db);

      await Future.wait([
        houseProvider.init().timeout(const Duration(seconds: 10)),
        settingsProvider.init().timeout(const Duration(seconds: 5)),
        AppInfo.init().timeout(const Duration(seconds: 5)),
        NotificationService().init().timeout(const Duration(seconds: 5)),
        Future.delayed(const Duration(milliseconds: 500)),
      ]);

      if (houseProvider.currentHouse != null) {
        final houseId = houseProvider.currentHouse!.id;
        await Future.wait([
          attributeProvider.loadAttributes().timeout(const Duration(seconds: 10)),
          spaceProvider.loadSpaces(houseId).timeout(const Duration(seconds: 10)),
          itemProvider.loadItems(houseId).timeout(const Duration(seconds: 10)),
          categoryProvider.loadCategories().timeout(const Duration(seconds: 10)),
          tagProvider.loadTags().timeout(const Duration(seconds: 10)),
          notificationProvider.loadNotifications().timeout(const Duration(seconds: 5)),
        ]);
      }

      try {
        NotificationService().onNotificationSent = (title, body, type, itemId) {
          notificationProvider.addNotification(
            title: title,
            body: body,
            type: type,
            itemId: itemId,
          );
        };
        await NotificationService().checkAndSendImmediateReminders(db, settingsProvider);
        await NotificationService().checkAndScheduleExpireReminders(db, settingsProvider);
      } catch (e) {
        debugPrint('Notification initialization error: $e');
      }

      if (!mounted) return;

      runApp(NestBackApp(
        db: db,
        houseProvider: houseProvider,
        attributeProvider: attributeProvider,
        itemProvider: itemProvider,
        spaceProvider: spaceProvider,
        categoryProvider: categoryProvider,
        tagProvider: tagProvider,
        settingsProvider: settingsProvider,
        notificationProvider: notificationProvider,
      ));
    } catch (e) {
      debugPrint('Error initializing app: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '启动失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                  _initializeAndNavigate();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image(
              image: AssetImage('assets/logo.png'),
              width: 120,
              height: 120,
            ),
            SizedBox(height: 32),
            Text(
              '物有归巢，心有所安。',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NestBackApp extends StatelessWidget {
  final AppDatabase db;
  final HouseProvider houseProvider;
  final AttributeProvider attributeProvider;
  final ItemProvider itemProvider;
  final SpaceProvider spaceProvider;
  final CategoryProvider categoryProvider;
  final TagProvider tagProvider;
  final SettingsProvider settingsProvider;
  final NotificationProvider notificationProvider;

  const NestBackApp({
    super.key,
    required this.db,
    required this.houseProvider,
    required this.attributeProvider,
    required this.itemProvider,
    required this.spaceProvider,
    required this.categoryProvider,
    required this.tagProvider,
    required this.settingsProvider,
    required this.notificationProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider.value(value: houseProvider),
        ChangeNotifierProvider.value(value: itemProvider),
        ChangeNotifierProvider.value(value: spaceProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: attributeProvider),
        ChangeNotifierProvider.value(value: categoryProvider),
        ChangeNotifierProvider.value(value: tagProvider),
        ChangeNotifierProvider.value(value: notificationProvider),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: '归巢-收纳提醒',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          if (settings.name == '/expired') {
            final isExpiring = settings.arguments as bool? ?? true;
            return MaterialPageRoute(
              builder: (context) => ExpiredItemsPage(isExpiring: isExpiring),
            );
          }
          if (settings.name == '/notifications') {
            return MaterialPageRoute(
              builder: (context) => const NotificationPage(),
            );
          }
          return null;
        },
        routes: {
          '/': (context) => const HomePage(),
        },
      ),
    );
  }
}
