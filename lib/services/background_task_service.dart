import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/price_data.dart';
import 'notification_service.dart';
import 'price_cache_service.dart';
import 'widget_service.dart';
import 'geofence_service.dart';

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
      
      // After 13h: Check for tomorrow prices and schedule notifications once per day
      if (now.hour >= 13) {
        final lastNotificationDate = prefs.getString('last_notification_scheduled_date');
        final todayString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        
        if (lastNotificationDate != todayString) {
          debugPrint('[BackgroundTask] Checking for tomorrow prices (notifications not yet scheduled today)...');
          final prices = await priceCacheService.getPrices(); // Smart cache validation
          
          final tomorrow = now.add(const Duration(days: 1));
          final hasTomorrowPrices = prices.any((p) => 
            p.startTime.day == tomorrow.day && 
            p.startTime.month == tomorrow.month && 
            p.startTime.year == tomorrow.year
          );
          
          if (hasTomorrowPrices) {
            debugPrint('[BackgroundTask] ✓ Got tomorrow prices - scheduling notifications');
            final notificationService = NotificationService();
            await notificationService.scheduleNotifications();
            await prefs.setString('last_notification_scheduled_date', todayString);
          } else {
            debugPrint('[BackgroundTask] No tomorrow prices yet, will retry in 15 min');
          }
        } else {
          debugPrint('[BackgroundTask] Notifications already scheduled today');
        }
      }
      
      // Update widget with latest data
      await WidgetService.updateWidget();
      debugPrint('[BackgroundTask] Widget updated');
      
      
      // Check if we're close to the hour mark
      final currentMinute = now.minute;
      if (currentMinute >= 45 && currentMinute <= 59) {
        // We're in the last 15 minutes of an hour
        // Schedule an extra update for the top of the hour
        final nextHour = now.hour < 23 
          ? DateTime(now.year, now.month, now.day, now.hour + 1, 0)
          : DateTime(now.year, now.month, now.day + 1, 0, 0); // Handle midnight
        final delayToNextHour = nextHour.difference(now);
        
        debugPrint('[BackgroundTask] Near hour mark (${now.minute} min), scheduling extra update in ${delayToNextHour.inMinutes} minutes');
        
        // Schedule one-time task for the top of the hour
        if (Platform.isAndroid) {
          await Workmanager().registerOneOffTask(
            'hourly-update-${nextHour.hour}',
            'updatePricesAndNotifications',
            initialDelay: delayToNextHour,
            constraints: Constraints(
              networkType: NetworkType.connected,
            ),
          );
        }
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

