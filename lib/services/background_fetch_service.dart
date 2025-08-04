import 'package:flutter/material.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'price_cache_service.dart';
import 'notification_service.dart';

/// Background Service mit flutter_background_fetch
/// Funktioniert auch wenn die App geschlossen ist
class BackgroundFetchService {
  static const String _lastFetchKey = 'last_background_fetch';
  
  /// Initialisiert den Background Fetch Service
  static Future<void> initialize() async {
    // Konfiguration für Background Fetch
    await BackgroundFetch.configure(
      BackgroundFetchConfig(
        minimumFetchInterval: 30, // Minimum alle 30 Minuten (Android Limit: 15 Min)
        stopOnTerminate: false, // Weiterlaufen auch wenn App beendet
        enableHeadless: true, // Läuft auch wenn App komplett geschlossen
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresStorageNotLow: false,
        requiresDeviceIdle: false,
        requiredNetworkType: NetworkType.ANY,
        startOnBoot: true, // Nach Geräteneustart automatisch starten
      ),
      _onBackgroundFetch,
      _onBackgroundFetchTimeout,
    );
    
    // Status prüfen
    final status = await BackgroundFetch.status;
    debugPrint('BackgroundFetch Status: $status');
    
    // Für Android Headless Mode registrieren
    BackgroundFetch.registerHeadlessTask(_backgroundFetchHeadlessTask);
  }
  
  /// Callback wenn Background Fetch ausgeführt wird
  static Future<void> _onBackgroundFetch(String taskId) async {
    debugPrint('[BackgroundFetch] Event received: $taskId');
    
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      
      // Speichern wann zuletzt ausgeführt
      await prefs.setString(_lastFetchKey, now.toIso8601String());
      
      // Prüfen ob Update nötig
      bool shouldUpdate = false;
      String reason = '';
      
      // 1. Zwischen 13:00 und 15:00 Uhr - neue Preise für morgen
      if (now.hour >= 13 && now.hour <= 15) {
        final lastFetch = prefs.getString(_lastFetchKey + '_afternoon');
        if (lastFetch == null || 
            DateTime.parse(lastFetch).day != now.day) {
          shouldUpdate = true;
          reason = 'Afternoon update for tomorrow prices';
          await prefs.setString(_lastFetchKey + '_afternoon', now.toIso8601String());
        }
      }
      
      // 2. Früh morgens - neue Tagespreise
      if (now.hour >= 0 && now.hour <= 2) {
        final lastFetch = prefs.getString(_lastFetchKey + '_morning');
        if (lastFetch == null || 
            DateTime.parse(lastFetch).day != now.day) {
          shouldUpdate = true;
          reason = 'Morning update for today prices';
          await prefs.setString(_lastFetchKey + '_morning', now.toIso8601String());
        }
      }
      
      // 3. Cache ist abgelaufen (älter als 6 Stunden)
      final priceCacheService = PriceCacheService();
      final cacheAge = await priceCacheService.getCacheAge();
      if (cacheAge == null || cacheAge.inHours >= 6) {
        shouldUpdate = true;
        reason = 'Cache expired';
      }
      
      if (shouldUpdate) {
        debugPrint('[BackgroundFetch] Updating prices: $reason');
        
        // Preise aktualisieren
        final prices = await priceCacheService.getPrices(forceRefresh: true);
        debugPrint('[BackgroundFetch] Updated ${prices.length} prices');
        
        // Notifications neu planen
        final notificationService = NotificationService();
        await notificationService.scheduleNotifications();
        debugPrint('[BackgroundFetch] Notifications scheduled');
      } else {
        debugPrint('[BackgroundFetch] No update needed');
      }
      
    } catch (e) {
      debugPrint('[BackgroundFetch] ERROR: $e');
    }
    
    // WICHTIG: Task als fertig markieren
    BackgroundFetch.finish(taskId);
  }
  
  /// Timeout Handler
  static void _onBackgroundFetchTimeout(String taskId) {
    debugPrint('[BackgroundFetch] TIMEOUT: $taskId');
    BackgroundFetch.finish(taskId);
  }
  
  /// Manuell einen Background Fetch auslösen (für Tests)
  static Future<void> scheduleBackgroundFetch() async {
    await BackgroundFetch.scheduleTask(TaskConfig(
      taskId: 'com.spottwatt.fetch',
      delay: 5000, // 5 Sekunden Delay
      periodic: false,
      forceAlarmManager: false,
      stopOnTerminate: false,
      enableHeadless: true,
    ));
  }
  
  /// Background Fetch stoppen
  static Future<void> stop() async {
    await BackgroundFetch.stop();
  }
}

/// Headless Task für Android
/// Wird ausgeführt auch wenn App komplett geschlossen ist
@pragma('vm:entry-point')
void _backgroundFetchHeadlessTask(HeadlessTask task) {
  final taskId = task.taskId;
  final isTimeout = task.timeout;
  
  if (isTimeout) {
    debugPrint('[BackgroundFetch] Headless TIMEOUT: $taskId');
    BackgroundFetch.finish(taskId);
    return;
  }
  
  debugPrint('[BackgroundFetch] Headless event: $taskId');
  
  // Den normalen Handler aufrufen
  BackgroundFetchService._onBackgroundFetch(taskId);
}