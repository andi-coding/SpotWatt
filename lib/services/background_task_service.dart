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

    // Schedule first hourly task
    await _scheduleNextHourlyUpdate();

    debugPrint('[BackgroundTask] Android Workmanager initialized');
    debugPrint('[BackgroundTask] Hourly updates scheduled');
  }

  /// Schedule next update at the top of the hour
  static Future<void> _scheduleNextHourlyUpdate() async {
    final now = DateTime.now();

    // Calculate next full hour
    final nextHour = now.hour < 23
        ? DateTime(now.year, now.month, now.day, now.hour + 1, 0, 0)
        : DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    final delay = nextHour.difference(now);

    await Workmanager().registerOneOffTask(
      _taskName,
      'updatePricesAndNotifications',
      initialDelay: delay,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      // Exponential backoff for quick recovery from short network outages
      // 30s → 1min → 2min → 4min → 8min → 16min (6 retries in ~30min)
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );

    debugPrint('[BackgroundTask] Next update scheduled for $nextHour (in ${delay.inMinutes} min)');
  }

  /// Reschedule background tasks (useful after OEM kills or app updates)
  static Future<void> reschedule() async {
    if (Platform.isAndroid) {
      await _scheduleNextHourlyUpdate();
      debugPrint('[BackgroundTask] Background tasks rescheduled');
    }
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

          try {
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
              debugPrint('[BackgroundTask] No tomorrow prices yet, will retry next hour');
            }
          } catch (e) {
            debugPrint('[BackgroundTask] Failed to get prices for notifications: $e');
            debugPrint('[BackgroundTask] Will retry in next cycle (offline or cache invalid)');
            // No crash - just skip notification scheduling this time
          }
        } else {
          debugPrint('[BackgroundTask] Notifications already scheduled today');
        }
      }
      
      // Update widget with latest data
      await WidgetService.updateWidget();
      debugPrint('[BackgroundTask] Widget updated');

      // Schedule next hourly update (chain pattern)
      await BackgroundTaskService._scheduleNextHourlyUpdate();

      debugPrint('[BackgroundTask] Task completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('[BackgroundTask] Task failed: $e');
      return Future.value(false);
    }
  });
}

