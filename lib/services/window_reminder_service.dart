import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Represents a user-set reminder for a specific time window
class WindowReminder {
  final String deviceId;
  final String deviceName;
  final DateTime startTime;
  final DateTime endTime;
  final double savingsCents; // Savings in cents

  WindowReminder({
    required this.deviceId,
    required this.deviceName,
    required this.startTime,
    required this.endTime,
    required this.savingsCents,
  });

  /// Unique key for this reminder
  String get key {
    return '${deviceId}_${startTime.toIso8601String()}';
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'savingsCents': savingsCents,
    };
  }

  /// Create from JSON
  factory WindowReminder.fromJson(Map<String, dynamic> json) {
    return WindowReminder(
      deviceId: json['deviceId'],
      deviceName: json['deviceName'],
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      savingsCents: (json['savingsCents'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Check if this reminder is still relevant (not expired)
  bool get isRelevant {
    return DateTime.now().isBefore(endTime);
  }
}

/// Service for managing user-set time window reminders
class WindowReminderService {
  static const String _storageKey = 'window_reminders';
  static const int _reminderMinutesBefore = 5;

  /// Load all saved reminders
  Future<List<WindowReminder>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);

    if (json == null) return [];

    try {
      final List<dynamic> data = jsonDecode(json);
      return data.map((item) => WindowReminder.fromJson(item)).toList();
    } catch (e) {
      debugPrint('[WindowReminder] Failed to load reminders: $e');
      return [];
    }
  }

  /// Save reminders to storage
  Future<void> _saveReminders(List<WindowReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(reminders.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }

  /// Add a reminder for a time window
  Future<void> addReminder(WindowReminder reminder) async {
    final reminders = await loadReminders();

    // Check if already exists
    if (reminders.any((r) => r.key == reminder.key)) {
      debugPrint('[WindowReminder] Reminder already exists for ${reminder.deviceName}');
      return;
    }

    reminders.add(reminder);
    await _saveReminders(reminders);

    debugPrint('[WindowReminder] Added reminder for ${reminder.deviceName} at ${reminder.startTime}');
  }

  /// Remove a reminder
  Future<void> removeReminder(String key) async {
    final reminders = await loadReminders();
    reminders.removeWhere((r) => r.key == key);
    await _saveReminders(reminders);

    debugPrint('[WindowReminder] Removed reminder: $key');
  }

  /// Check if a reminder exists for a specific window
  Future<bool> hasReminder(String deviceId, DateTime startTime) async {
    final reminders = await loadReminders();
    final key = '${deviceId}_${startTime.toIso8601String()}';
    return reminders.any((r) => r.key == key);
  }

  /// Clean up expired reminders and reschedule valid ones
  /// Called after cancelAll() at 14:00
  Future<List<WindowReminder>> cleanupAndGetActiveReminders() async {
    final reminders = await loadReminders();
    final now = DateTime.now();

    // Filter out expired reminders
    final activeReminders = reminders.where((r) {
      // Remove if window has already started or ended
      return r.startTime.isAfter(now);
    }).toList();

    // Save cleaned list
    await _saveReminders(activeReminders);

    debugPrint('[WindowReminder] Cleaned up reminders: ${reminders.length} -> ${activeReminders.length}');
    return activeReminders;
  }

  /// Get notification time (5 minutes before window starts)
  DateTime getNotificationTime(DateTime windowStart) {
    return windowStart.subtract(Duration(minutes: _reminderMinutesBefore));
  }

  /// Get reminder minutes before
  int get reminderMinutesBefore => _reminderMinutesBefore;
}
