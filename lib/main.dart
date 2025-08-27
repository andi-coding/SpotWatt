import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'screens/home_screen.dart';
import 'services/background_task_service.dart';
import 'services/geofence_service.dart';
import 'services/location_permission_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final String timeZoneName = 'Europe/Vienna';
  tz.setLocalLocation(tz.getLocation(timeZoneName));
  
  // Background Tasks initialisieren (Workmanager für Android)
  // Läuft immer - egal ob App offen oder geschlossen
  await BackgroundTaskService.initialize();
  
  // Geofence Service beim App-Start initialisieren
  await GeofenceService().initialize();
  
  // Location Permissions werden beim ersten Screen-Load angefragt (mit Context)
  
  runApp(const WattWiseApp());
}

class WattWiseApp extends StatelessWidget {
  const WattWiseApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WattWise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(  // Hier geändert!
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(  // Hier geändert!
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}