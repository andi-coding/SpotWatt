import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../models/price_data.dart';
import '../utils/price_utils.dart';
import 'price_cache_service.dart';
import 'geofence_service.dart';
import 'window_reminder_service.dart';
import 'firebase_notification_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
  int _notificationId = 1; // Global notification ID counter

  // Callback for handling notification clicks
  static Function(int)? _onNotificationTap;

  static void setNotificationTapCallback(Function(int) callback) {
    _onNotificationTap = callback;
  }

  Future<void> initialize(BuildContext context) async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification_small');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked: ${response.payload}');

        // Determine which tab to navigate to based on notification type
        // Window reminder notifications have IDs >= 2000
        if (response.id != null && response.id! >= 2000) {
          // Navigate to Spartipps tab (index 1)
          _onNotificationTap?.call(1);
        } else {
          // Navigate to Preise tab (index 0) for price notifications
          _onNotificationTap?.call(0);
        }
      },
    );

    // Don't request permissions on initialize - only when user enables notifications
    // Permissions are requested in notification_settings_page.dart when user toggles a notification
  }

  Future<void> rescheduleNotifications() async {
    debugPrint('[NotificationService] Rescheduling notifications due to settings change');
    await notifications.cancelAll();
    await scheduleNotifications();
  }

  Future<void> scheduleNotifications() async {
    // ✅ Firebase now handles: Price Threshold, Cheapest Time, Daily Summary
    // ✅ Local notifications ONLY for: Window Reminders (user-specific, instant)

    debugPrint('[NotificationService] Scheduling local notifications (Window Reminders only)');

    // Cancel all local notifications to avoid duplicates
    await notifications.cancelAll();

    // Reset notification ID counter
    _notificationId = 1;

    // Reschedule window reminder notifications (user-set reminders for specific time windows)
    // These are NOT handled by Firebase because they're user-specific and instant
    await _rescheduleWindowReminders();

    debugPrint('[NotificationService] Scheduled ${_notificationId - 1} local notifications (window reminders)');
  }

  // ❌ REMOVED: Now handled by Firebase
  // Price threshold and cheapest time notifications are scheduled server-side
  // This prevents iOS force-quit issues and scales better

  /* DEPRECATED - Kept for reference
  Future<void> _schedulePriceNotification(PriceData price) async {
    // ... (moved to Firebase Functions)
  }

  Future<void> _scheduleCheapestTimeNotification(PriceData price, int minutesBefore) async {
    // ... (moved to Firebase Functions)
  }
  */

  bool _isInQuietTime(DateTime time, SharedPreferences prefs) {
    // Check if quiet time is enabled
    final quietTimeEnabled = prefs.getBool('quiet_time_enabled') ?? false;
    if (!quietTimeEnabled) return false;
    
    // Standard-Ruhezeiten falls nicht gesetzt
    final startHour = prefs.getInt('quiet_time_start_hour') ?? 22;
    final startMinute = prefs.getInt('quiet_time_start_minute') ?? 0;
    final endHour = prefs.getInt('quiet_time_end_hour') ?? 6;
    final endMinute = prefs.getInt('quiet_time_end_minute') ?? 0;
    
    final timeOfDay = TimeOfDay.fromDateTime(time);
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;
    final currentMinutes = timeOfDay.hour * 60 + timeOfDay.minute;
    
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  Future<void> cancelAllNotifications() async {
    await notifications.cancelAll();
  }
  
  
  // ❌ REMOVED: Daily summary now handled by Firebase
  /* DEPRECATED - Kept for reference
  List<PriceData> findCheapestHours(List<PriceData> prices, int count) {
    // ... (moved to Firebase Functions)
  }

  Future<void> _scheduleDailySummary(List<PriceData> prices, SharedPreferences prefs) async {
    // ... (moved to Firebase Functions)
  }
  */

  /// Reschedule user-set window reminders after cancelAll()
  /// This is called after all notifications are cancelled (e.g., at 14:00 when new prices arrive)
  Future<void> _rescheduleWindowReminders() async {
    final windowReminderService = WindowReminderService();

    // Get all active reminders (expired ones are automatically filtered out)
    final activeReminders = await windowReminderService.cleanupAndGetActiveReminders();

    if (activeReminders.isEmpty) {
      debugPrint('[NotificationService] No active window reminders to reschedule');
      return;
    }

    debugPrint('[NotificationService] Rescheduling ${activeReminders.length} window reminders');

    for (final reminder in activeReminders) {
      await scheduleWindowReminder(reminder);
    }
  }

  /// Generate stable notification ID from window reminder key
  /// This ensures each time window has a unique, consistent ID
  int _getWindowReminderId(String reminderKey) {
    // Use hash code to generate consistent ID
    // Start from 2000 to avoid conflicts with system notifications (1-1999)
    return 2000 + reminderKey.hashCode.abs() % 100000;
  }

  /// Schedule a notification for a specific time window reminder
  Future<void> scheduleWindowReminder(WindowReminder reminder) async {
    final notificationTime = WindowReminderService().getNotificationTime(reminder.startTime);
    final now = DateTime.now();

    // Skip if notification time has already passed
    if (notificationTime.isBefore(now)) {
      debugPrint('[NotificationService] Skipping window reminder for ${reminder.deviceName} - notification time already passed');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Check quiet time
    if (_isInQuietTime(notificationTime, prefs)) {
      debugPrint('[NotificationService] Skipping window reminder for ${reminder.deviceName} - in quiet time');
      return;
    }

    // Format time
    final startHour = reminder.startTime.hour.toString().padLeft(2, '0');
    final startMinute = reminder.startTime.minute.toString().padLeft(2, '0');
    final endHour = reminder.endTime.hour.toString().padLeft(2, '0');
    final endMinute = reminder.endTime.minute.toString().padLeft(2, '0');

    // Format savings
    final savingsEuro = (reminder.savingsCents / 100).toStringAsFixed(2);

    // Use stable notification ID based on reminder key
    final notificationId = _getWindowReminderId(reminder.key);

    // Schedule locally (fallback for immediate notifications)
    await notifications.zonedSchedule(
      notificationId,
      '⚡ ${reminder.deviceName} jetzt einschalten!',
      'Optimales Zeitfenster: $startHour:$startMinute - $endHour:$endMinute Uhr • Spare ${savingsEuro}€',
      tz.TZDateTime.from(notificationTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'window_reminders',
          'Zeitfenster-Erinnerungen',
          channelDescription: 'Erinnerungen für optimale Zeitfenster',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification_small',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    debugPrint('[NotificationService] Scheduled window reminder for ${reminder.deviceName} at $notificationTime (ID: $notificationId)');

    // Also schedule in Firebase (for reliability across app restarts)
    try {
      await FirebaseNotificationService().scheduleWindowReminder(
        deviceName: reminder.deviceName,
        startTime: reminder.startTime,
        endTime: reminder.endTime,
        savingsCents: reminder.savingsCents.round(),
      );
    } catch (e) {
      debugPrint('[NotificationService] Failed to schedule window reminder in Firebase: $e');
      // Don't fail the whole operation if Firebase fails - local notification is already scheduled
    }
  }

  /// Cancel a specific window reminder notification
  Future<void> cancelWindowReminder(String reminderKey) async {
    // Cancel local notification
    final notificationId = _getWindowReminderId(reminderKey);
    await notifications.cancel(notificationId);
    debugPrint('[NotificationService] Cancelled local window reminder (ID: $notificationId)');

    // Also cancel in Firebase (by looking up the reminder to get device name and start time)
    try {
      final windowReminderService = WindowReminderService();
      final reminders = await windowReminderService.loadReminders();

      // Find the reminder with matching key
      final reminder = reminders.where((r) => r.key == reminderKey).firstOrNull;

      if (reminder != null) {
        await FirebaseNotificationService().cancelWindowReminder(
          deviceName: reminder.deviceName,
          startTime: reminder.startTime,
        );
      } else {
        debugPrint('[NotificationService] Reminder not found in storage, skipping Firebase cancel');
      }
    } catch (e) {
      debugPrint('[NotificationService] Failed to cancel window reminder in Firebase: $e');
      // Don't fail the whole operation if Firebase fails - local notification is already cancelled
    }
  }
}