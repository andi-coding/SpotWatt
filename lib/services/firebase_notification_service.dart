import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';

/// Firebase Notification Service
/// Syncs user notification preferences to Firestore
/// Firebase Functions handle the actual notification scheduling
class FirebaseNotificationService {
  static final FirebaseNotificationService _instance =
      FirebaseNotificationService._internal();
  factory FirebaseNotificationService() => _instance;
  FirebaseNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Debouncing für Settings-Events (90 Sekunden = 1.5 Minuten)
  // Gibt dem User Zeit, alle Settings anzupassen bevor Event getriggert wird
  static Timer? _debounceTimer;
  static const Duration _eventDebounceDelay = Duration(seconds: 90);

  /// Helper to get daily summary time as string from preferences
  String _getDailySummaryTimeString(SharedPreferences prefs) {
    final hour = prefs.getInt('daily_summary_hour') ?? 14;
    final minute = prefs.getInt('daily_summary_minute') ?? 0;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Sync user notification preferences to Firestore
  /// Called whenever user changes notification settings
  Future<void> syncPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fcmToken = await _messaging.getToken();

      if (fcmToken == null) {
        debugPrint('[FirebaseNotifications] No FCM token available');
        return;
      }

      // Calculate if user has ANY notification enabled
      final dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? false;
      final cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? false;
      final thresholdEnabled = prefs.getBool('price_threshold_enabled') ?? false;

      final hasAnyEnabled = dailySummaryEnabled || cheapestTimeEnabled || thresholdEnabled;

      final preferences = {
        'fcm_token': fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'market': prefs.getString('price_market') ?? 'AT',

        // Timezone für korrekte Zeitberechnung in Cloud Function
        'timezone': DateTime.now().timeZoneOffset.inMinutes, // Offset in Minuten (z.B. +60 für UTC+1)
        'timezone_name': DateTime.now().timeZoneName, // z.B. "CEST" oder "CET"

        // Flag for efficient querying (important!)
        'has_any_notification_enabled': hasAnyEnabled,

        // Daily Summary
        'daily_summary_enabled': dailySummaryEnabled,
        'daily_summary_time': _getDailySummaryTimeString(prefs),

        // Cheapest Hour
        'cheapest_time_enabled': cheapestTimeEnabled,
        'notification_minutes_before': prefs.getInt('notification_minutes_before') ?? 15,

        // Price Threshold
        'price_threshold_enabled': thresholdEnabled,
        'notification_threshold': prefs.getDouble('notification_threshold') ?? 10.0,

        // Full Cost Mode (for server-side calculation)
        'full_cost_mode': prefs.getBool('full_cost_mode') ?? false,
        'energy_provider_percentage': prefs.getDouble('energy_provider_percentage') ?? 0.0,
        'energy_provider_fixed_fee': prefs.getDouble('energy_provider_fixed_fee') ?? 0.0,
        'network_costs': prefs.getDouble('network_costs') ?? 0.0,
        'include_tax': prefs.getBool('include_tax') ?? true,
        'tax_rate': prefs.getDouble('tax_rate') ?? 20.0,

        // Quiet Time
        'quiet_time_enabled': prefs.getBool('quiet_time_enabled') ?? false,
        'quiet_time_start_hour': prefs.getInt('quiet_time_start_hour') ?? 22,
        'quiet_time_start_minute': prefs.getInt('quiet_time_start_minute') ?? 0,
        'quiet_time_end_hour': prefs.getInt('quiet_time_end_hour') ?? 6,
        'quiet_time_end_minute': prefs.getInt('quiet_time_end_minute') ?? 0,

        // Daily Summary Settings
        'daily_summary_hours': prefs.getInt('daily_summary_hours') ?? 3,
        'high_price_threshold': prefs.getDouble('high_price_threshold') ?? 50.0,

        'updated_at': FieldValue.serverTimestamp(),
      };

      // Store in Firestore (Firebase Functions will read this)
      await _firestore
          .collection('notification_preferences')
          .doc(fcmToken)
          .set(preferences, SetOptions(merge: true));

      debugPrint('[FirebaseNotifications] ✅ Preferences synced to Firestore');
      debugPrint('[FirebaseNotifications]   - Daily Summary: $dailySummaryEnabled');
      debugPrint('[FirebaseNotifications]   - Cheapest Time: $cheapestTimeEnabled');
      debugPrint('[FirebaseNotifications]   - Threshold: $thresholdEnabled');

      // Trigger event to reschedule notifications (with debouncing)
      await _triggerSettingsChangedEvent(fcmToken);

    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to sync preferences: $e');
      rethrow;
    }
  }

  /// Trigger a settings_changed event in Firestore (with debouncing)
  /// Uses trailing edge debouncing: Waits 90s after LAST change before triggering
  /// This allows user to change multiple settings and trigger only 1 event
  Future<void> _triggerSettingsChangedEvent(String fcmToken) async {
    try {
      // Cancel previous timer (if user changes settings again)
      _debounceTimer?.cancel();

      debugPrint('[FirebaseNotifications] ⏱️ Settings changed, waiting ${_eventDebounceDelay.inSeconds}s before triggering event...');

      // Start new timer - will trigger after 90s of inactivity
      _debounceTimer = Timer(_eventDebounceDelay, () async {
        try {
          final eventData = {
            'fcm_token': fcmToken,
            'event_type': 'settings_changed',
            'timestamp': FieldValue.serverTimestamp(),
            'processed': false,
          };

          await _firestore.collection('notification_events').add(eventData);

          debugPrint('[FirebaseNotifications] 📨 Event triggered: settings_changed (after ${_eventDebounceDelay.inSeconds}s delay)');
        } catch (e) {
          debugPrint('[FirebaseNotifications] ❌ Failed to trigger event: $e');
        }
      });

    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to setup debounce timer: $e');
      // Don't rethrow - event triggering is optional
    }
  }

  /// Register FCM token in Firestore (for silent push notifications)
  /// Called on app start and when token refreshes
  Future<void> registerFCMToken() async {
    try {
      final fcmToken = await _messaging.getToken();

      if (fcmToken == null) {
        debugPrint('[FirebaseNotifications] No FCM token available');
        return;
      }

      final tokenData = {
        'token': fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'active': true,
        'last_seen': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      };

      // Store token in fcm_tokens collection (for silent push)
      await _firestore
          .collection('fcm_tokens')
          .doc(fcmToken)
          .set(tokenData, SetOptions(merge: true));

      debugPrint('[FirebaseNotifications] ✅ FCM token registered');

    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to register FCM token: $e');
    }
  }

  /// Delete user preferences (when user disables all notifications)
  Future<void> deletePreferences() async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken != null) {
        await _firestore
            .collection('notification_preferences')
            .doc(fcmToken)
            .delete();
        debugPrint('[FirebaseNotifications] Preferences deleted');
      }
    } catch (e) {
      debugPrint('[FirebaseNotifications] Failed to delete preferences: $e');
    }
  }

  /// Deactivate FCM token (when user uninstalls or logs out)
  Future<void> deactivateFCMToken() async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken != null) {
        await _firestore
            .collection('fcm_tokens')
            .doc(fcmToken)
            .update({'active': false});
        debugPrint('[FirebaseNotifications] FCM token deactivated');
      }
    } catch (e) {
      debugPrint('[FirebaseNotifications] Failed to deactivate token: $e');
    }
  }

  /// Force trigger pending settings_changed event immediately
  /// Useful when user leaves settings page - no need to wait 90s
  Future<void> flushPendingEvents() async {
    try {
      if (_debounceTimer != null && _debounceTimer!.isActive) {
        debugPrint('[FirebaseNotifications] 🚀 Flushing pending event immediately');
        _debounceTimer!.cancel();

        final fcmToken = await _messaging.getToken();
        if (fcmToken != null) {
          final eventData = {
            'fcm_token': fcmToken,
            'event_type': 'settings_changed',
            'timestamp': FieldValue.serverTimestamp(),
            'processed': false,
          };

          await _firestore.collection('notification_events').add(eventData);
          debugPrint('[FirebaseNotifications] 📨 Event triggered immediately (flush)');
        }
      }
    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to flush events: $e');
    }
  }

  /// Schedule a window reminder notification via Firebase
  /// Called when user enables a reminder for a specific time window
  Future<void> scheduleWindowReminder({
    required String deviceName,
    required DateTime startTime,
    required DateTime endTime,
    required int savingsCents,
  }) async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) {
        debugPrint('[FirebaseNotifications] No FCM token - cannot schedule window reminder');
        return;
      }

      // Calculate notification time (5min before window start)
      final notificationTime = startTime.subtract(const Duration(minutes: 5));

      // Skip if notification time is in the past
      if (notificationTime.isBefore(DateTime.now())) {
        debugPrint('[FirebaseNotifications] Window reminder time is in the past, skipping');
        return;
      }

      // Format notification
      final savingsEuro = (savingsCents / 100).toStringAsFixed(2);
      final startHour = startTime.hour.toString().padLeft(2, '0');
      final startMinute = startTime.minute.toString().padLeft(2, '0');
      final endHour = endTime.hour.toString().padLeft(2, '0');
      final endMinute = endTime.minute.toString().padLeft(2, '0');

      final notificationData = {
        'fcm_token': fcmToken,
        'notification': {
          'title': '⚡ $deviceName jetzt einschalten!',
          'body': 'Optimales Zeitfenster: $startHour:$startMinute - $endHour:$endMinute Uhr • Spare ${savingsEuro}€',
          'type': 'window_reminder',
        },
        'send_at': Timestamp.fromDate(notificationTime),
        'created_at': FieldValue.serverTimestamp(),
        'sent': false,
        'device_name': deviceName,
        'window_start': Timestamp.fromDate(startTime),
        'window_end': Timestamp.fromDate(endTime),
      };

      // Store in Firestore (Firebase Cron will send it)
      await _firestore.collection('scheduled_notifications').add(notificationData);

      debugPrint('[FirebaseNotifications] ✅ Window reminder scheduled for $deviceName at $notificationTime');
    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to schedule window reminder: $e');
      rethrow;
    }
  }

  /// Cancel a specific window reminder for a device and time window
  /// Called when user toggles off a specific reminder
  Future<void> cancelWindowReminder({
    required String deviceName,
    required DateTime startTime,
  }) async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) {
        debugPrint('[FirebaseNotifications] No FCM token - cannot cancel window reminder');
        return;
      }

      // Query for this specific window reminder (unsent only)
      final snapshot = await _firestore
          .collection('scheduled_notifications')
          .where('fcm_token', isEqualTo: fcmToken)
          .where('device_name', isEqualTo: deviceName)
          .where('window_start', isEqualTo: Timestamp.fromDate(startTime))
          .where('sent', isEqualTo: false)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('[FirebaseNotifications] No matching window reminder found to cancel');
        return;
      }

      // Delete all matching documents (should be 1, but use batch for safety)
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      debugPrint('[FirebaseNotifications] ✅ Cancelled window reminder for $deviceName at $startTime (${snapshot.docs.length} documents)');
    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to cancel window reminder: $e');
    }
  }

  /// Cancel all window reminders for current user
  /// Called when user disables all reminders or clears them
  Future<void> cancelAllWindowReminders() async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) return;

      // Query all unsent window reminders for this user
      final snapshot = await _firestore
          .collection('scheduled_notifications')
          .where('fcm_token', isEqualTo: fcmToken)
          .where('notification.type', isEqualTo: 'window_reminder')
          .where('sent', isEqualTo: false)
          .get();

      // Delete all in batch
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      debugPrint('[FirebaseNotifications] ✅ Cancelled ${snapshot.docs.length} window reminders');
    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to cancel window reminders: $e');
    }
  }
}
