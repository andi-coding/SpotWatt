import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/price_data.dart';
import 'notification_service.dart';
import 'price_cache_service.dart';

/// Unified Background Task Service
/// Handles background tasks for both Android and iOS (future)
class BackgroundTaskService {
  static const String _taskName = 'com.spottwatt.price_update';
  
  /// Initialize background tasks based on platform
  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      await _initializeAndroid();
    } else if (Platform.isIOS) {
      // TODO: Implement iOS background tasks when needed
      // Options:
      // 1. BGTaskScheduler (very limited, iOS decides when to run)
      // 2. Silent push notifications (requires server)
      // 3. Background fetch (unreliable on iOS)
      debugPrint('[BackgroundTask] iOS not yet supported');
    }
  }
  
  /// Initialize Android background tasks with Workmanager
  static Future<void> _initializeAndroid() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    
    // Register periodic task - runs every 15 minutes
    await Workmanager().registerPeriodicTask(
      _taskName,
      'updatePricesAndNotifications',
      frequency: const Duration(minutes: 15), // Android minimum
      initialDelay: const Duration(seconds: 10), // Startet 10 Sekunden nach App-Start
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    
    debugPrint('[BackgroundTask] Android Workmanager initialized');
    debugPrint('[BackgroundTask] First run in 10 seconds, then every 15 minutes');
  }
  
  /// Cancel all background tasks
  static Future<void> cancelAll() async {
    if (Platform.isAndroid) {
      await Workmanager().cancelAll();
    }
    // iOS implementation would go here
  }
  
  /// Force a one-time background task execution (for testing)
  static Future<void> runOnce() async {
    if (Platform.isAndroid) {
      await Workmanager().registerOneOffTask(
        'one-time-update',
        'updatePricesAndNotifications',
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
    }
  }
}

/// Workmanager callback dispatcher (Android only)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundTask] Task started: $task at ${DateTime.now()}');
    
    try {
      // Initialize timezone
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
      
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final priceCacheService = PriceCacheService();
      
      // Einfache Logik: Zwischen 13-15 Uhr versuchen neue Preise zu holen
      // Nur als "erledigt" markieren wenn Morgen-Daten da sind
      if (now.hour >= 13 && now.hour <= 15) {
        final gotTomorrowPrices = prefs.getBool('got_tomorrow_prices_${now.day}') ?? false;
        
        if (!gotTomorrowPrices) {
          debugPrint('[BackgroundTask] Checking for tomorrow prices...');
          final prices = await priceCacheService.getPrices(forceRefresh: true);
          
          // Einfacher Check: Gibt es Preise für morgen?
          final tomorrow = now.add(const Duration(days: 1));
          final hasTomorrowPrices = prices.any((p) => p.startTime.day == tomorrow.day);
          
          if (hasTomorrowPrices) {
            await prefs.setBool('got_tomorrow_prices_${now.day}', true);
            debugPrint('[BackgroundTask] ✓ Got tomorrow prices');
            
            //if tomorrow prices fetched, schedule notifications
            final notificationService = NotificationService();
            await notificationService.scheduleNotifications();
          } else {
            debugPrint('[BackgroundTask] No tomorrow prices yet, retry in 15 min');
          }
        }
      }
      
      // Cache älter als 24h? Sicherheits-Update
      final cacheAge = await priceCacheService.getCacheAge();
      if (cacheAge == null || cacheAge.inHours >= 24) {
        //if tomorrow prices fetched, schedule notifications
        debugPrint('[BackgroundTask] Cache expired, updating...');
        await priceCacheService.getPrices(forceRefresh: true);
        //schedule notifications if new prices are there
        final notificationService = NotificationService();
        await notificationService.scheduleNotifications();
      }
      
      // Always reschedule notifications
      //final notificationService = NotificationService();
      //await notificationService.scheduleNotifications();
      debugPrint('[BackgroundTask] Notifications scheduled');
      
      debugPrint('[BackgroundTask] Task completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('[BackgroundTask] Task failed: $e');
      return Future.value(false);
    }
  });
}