import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/refresh_screen.dart';
import 'services/background_task_service.dart';
import 'services/geofence_service.dart';
import 'services/location_permission_helper.dart';
import 'services/settings_cache.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final String timeZoneName = 'Europe/Vienna';
  tz.setLocalLocation(tz.getLocation(timeZoneName));

  // Initialize Firebase (FCM for push notifications)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register FCM background message handler (MUST be before runApp!)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize settings cache
  await SettingsCache().init();

  // Background Tasks initialisieren (Workmanager für Android)
  // Läuft immer - egal ob App offen oder geschlossen
  await BackgroundTaskService.initialize();

  // Geofence Service beim App-Start initialisieren
  await GeofenceService().initialize();

  // Location Permissions werden beim ersten Screen-Load angefragt (mit Context)

  runApp(const WattWiseApp());
}

class WattWiseApp extends StatefulWidget {
  const WattWiseApp({Key? key}) : super(key: key);

  @override
  State<WattWiseApp> createState() => _WattWiseAppState();
}

class _WattWiseAppState extends State<WattWiseApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = true;
  bool _showOnboarding = false;
  bool _showTermsUpdate = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadThemeMode();
    await _checkOnboarding();

    // Initialize FCM (request permissions & register token)
    await FCMService().initialize();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('theme_mode') ?? 'system';
    setState(() {
      switch (themeModeString) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    });
  }

  Future<void> _checkOnboarding() async {
    final hasCompleted = await OnboardingScreen.hasCompletedOnboarding();
    final needsTerms = await OnboardingScreen.needsTermsAcceptance();

    setState(() {
      if (!hasCompleted) {
        _showOnboarding = true;
        _showTermsUpdate = false;
      } else if (needsTerms) {
        _showOnboarding = false;
        _showTermsUpdate = true;
      } else {
        _showOnboarding = false;
        _showTermsUpdate = false;
      }
    });
  }

  void setThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', themeMode.toString().split('.').last);
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              color: const Color(0xFF1e3a5f),
            ),
          ),
        ),
      );
    }

    return ThemeProvider(
      setThemeMode: setThemeMode,
      currentThemeMode: _themeMode,
      child: MaterialApp(
        title: 'WattWise',
        debugShowCheckedModeBanner: false,
        onGenerateRoute: (settings) {
          if (settings.name == 'refresh') {
            return MaterialPageRoute(builder: (context) => const RefreshScreen());
          }
          return null;
        },
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1e3a5f), // Blue from website (--primary-color)
            brightness: Brightness.light,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: const Color(0xFF1e3a5f),
            contentTextStyle: const TextStyle(color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1e3a5f), // Blue theme for dark mode too
            brightness: Brightness.dark,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: const Color(0xFF2d5a8a),
            contentTextStyle: const TextStyle(color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        ),
        themeMode: _themeMode,
        home: _showOnboarding
            ? const OnboardingScreen()
            : _showTermsUpdate
                ? const OnboardingScreen(termsOnly: true)
                : const HomeScreen(),
      ),
    );
  }
}

class ThemeProvider extends InheritedWidget {
  final Function(ThemeMode) setThemeMode;
  final ThemeMode currentThemeMode;

  const ThemeProvider({
    Key? key,
    required this.setThemeMode,
    required this.currentThemeMode,
    required Widget child,
  }) : super(key: key, child: child);

  static ThemeProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
  }

  @override
  bool updateShouldNotify(ThemeProvider oldWidget) {
    return currentThemeMode != oldWidget.currentThemeMode;
  }
}