import 'dart:io';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'widget_service.dart';

/// Unified Background Task Service
/// Handles widget updates via WorkManager (Android only)
/// Note: Price fetching and notifications are handled by FCM (see fcm_service.dart)
class BackgroundTaskService {
  static const String _taskName = 'com.spottwatt.widget_update';
  
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
/// Only updates widget with cached data - FCM handles price fetching
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundTask] Widget refresh task started: $task at ${DateTime.now()}');

    try {
      // Update widget with cached data (no network call)
      await WidgetService.updateWidget();
      debugPrint('[BackgroundTask] Widget updated with cached data');

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

