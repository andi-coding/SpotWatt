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

  // ✅ Debouncing removed: onPreferencesUpdate trigger handles changes automatically

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

      // ✅ NEW: Firestore onWrite trigger handles rescheduling automatically
      // No need to manually trigger events anymore!

    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to sync preferences: $e');
      rethrow;
    }
  }

  /// DEPRECATED: No longer needed with Cloud Tasks and onPreferencesUpdate trigger
  /// The Firestore onWrite trigger automatically handles preference changes
  /*
  Future<void> _triggerSettingsChangedEvent(String fcmToken) async {
    // This function is no longer used.
    // The onPreferencesUpdate Cloud Function triggers automatically
    // when the notification_preferences document changes.
  }
  */

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

  /// DEPRECATED: No longer needed with Cloud Tasks
  /// The onPreferencesUpdate trigger fires immediately on any change
  Future<void> flushPendingEvents() async {
    // No-op: Firestore triggers handle changes automatically
    debugPrint('[FirebaseNotifications] flushPendingEvents() is deprecated - no action needed');
  }

  /// Schedule a window reminder notification via Cloud Tasks
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

      // Create unique reminder ID (fcmToken + deviceName + startTime)
      final reminderId = '${fcmToken.substring(0, 16)}_${deviceName.replaceAll(' ', '_')}_${startTime.millisecondsSinceEpoch}';

      final reminderData = {
        'fcm_token': fcmToken,
        'device_name': deviceName,
        'window_start': Timestamp.fromDate(startTime),
        'window_end': Timestamp.fromDate(endTime),
        'savings_cents': savingsCents,
        'send_at': Timestamp.fromDate(notificationTime),
        'title': '⚡ $deviceName jetzt einschalten!',
        'body': 'Optimales Zeitfenster: $startHour:$startMinute - $endHour:$endMinute Uhr • Spare ${savingsEuro}€',
        'created_at': FieldValue.serverTimestamp(),
        'status': 'pending', // pending, scheduled, sent, cancelled
      };

      // Store in Firestore (Firestore trigger will create Cloud Task)
      await _firestore
          .collection('window_reminders')
          .doc(reminderId)
          .set(reminderData);

      debugPrint('[FirebaseNotifications] ✅ Window reminder created for $deviceName at $notificationTime');
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

      // Construct reminder ID (same as in scheduleWindowReminder)
      final reminderId = '${fcmToken.substring(0, 16)}_${deviceName.replaceAll(' ', '_')}_${startTime.millisecondsSinceEpoch}';

      // Update status to 'cancelled' (Firestore trigger will delete Cloud Task)
      final docRef = _firestore.collection('window_reminders').doc(reminderId);
      final doc = await docRef.get();

      if (!doc.exists) {
        debugPrint('[FirebaseNotifications] No window reminder found with ID: $reminderId');
        return;
      }

      // Mark as cancelled (trigger will handle Cloud Task deletion)
      await docRef.update({'status': 'cancelled'});

      debugPrint('[FirebaseNotifications] ✅ Cancelled window reminder for $deviceName at $startTime');
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

      // Query all pending window reminders for this user
      final snapshot = await _firestore
          .collection('window_reminders')
          .where('fcm_token', isEqualTo: fcmToken)
          .where('status', whereIn: ['pending', 'scheduled'])
          .get();

      // Mark all as cancelled (triggers will handle Cloud Task deletion)
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'status': 'cancelled'});
      }
      await batch.commit();

      debugPrint('[FirebaseNotifications] ✅ Cancelled ${snapshot.docs.length} window reminders');
    } catch (e) {
      debugPrint('[FirebaseNotifications] ❌ Failed to cancel window reminders: $e');
    }
  }
}
