import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper class for managing SCHEDULE_EXACT_ALARM permission (Android 12+)
class ExactAlarmPermissionHelper {

  /// Check if exact alarm permission is required
  /// Only needed on Android 14+ (API 34+)
  static Future<bool> isExactAlarmPermissionRequired() async {
    if (!Platform.isAndroid) return false;

    // Only required on Android 14+ (SDK 34+)
    // Android 12-13 grants it automatically
    try {
      // This will return true on Android 14+ if permission is needed
      return await Permission.scheduleExactAlarm.isDenied ||
             await Permission.scheduleExactAlarm.isPermanentlyDenied;
    } catch (e) {
      debugPrint('[ExactAlarm] Error checking permission: $e');
      return false; // Assume not required if check fails
    }
  }

  /// Check if exact alarm permission is granted
  static Future<bool> isExactAlarmPermissionGranted() async {
    if (!Platform.isAndroid) return true; // iOS doesn't need this

    try {
      return await Permission.scheduleExactAlarm.isGranted;
    } catch (e) {
      debugPrint('[ExactAlarm] Error checking permission: $e');
      return true; // Assume granted if check fails (Android < 14)
    }
  }

  /// Request exact alarm permission by opening system settings
  /// Returns true if user granted permission, false otherwise
  static Future<bool> requestExactAlarmPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Check if already granted
    if (await isExactAlarmPermissionGranted()) {
      return true;
    }

    // Show explanation dialog
    final shouldProceed = await _showExactAlarmDialog(context);
    if (!shouldProceed) return false;

    // Open system settings
    try {
      await Permission.scheduleExactAlarm.request();

      // Check if granted after returning from settings
      final isGranted = await isExactAlarmPermissionGranted();

      if (!isGranted && context.mounted) {
        _showPermissionDeniedSnackbar(context);
      }

      return isGranted;
    } catch (e) {
      debugPrint('[ExactAlarm] Error requesting permission: $e');
      return false;
    }
  }

  /// Show explanation dialog before opening settings
  static Future<bool> _showExactAlarmDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exakte Benachrichtigungen erlauben'),
        content: const Text(
          'Für pünktliche Benachrichtigungen zu günstigen Strompreisen benötigt SpotWatt die Berechtigung für exakte Alarme.\n\n'
          'Bitte erlaube "Alarme & Erinnerungen" in den folgenden Einstellungen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zu Einstellungen'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Show snackbar when permission is denied
  static void _showPermissionDeniedSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ohne diese Berechtigung können Benachrichtigungen verzögert oder ungenau sein.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// Check and request permission if needed (convenience method)
  /// Returns true if permission is granted or not required
  static Future<bool> ensureExactAlarmPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Check if permission is required (Android 14+)
    final isRequired = await isExactAlarmPermissionRequired();
    if (!isRequired) {
      debugPrint('[ExactAlarm] Permission not required (Android < 14)');
      return true;
    }

    // Check if already granted
    final isGranted = await isExactAlarmPermissionGranted();
    if (isGranted) {
      debugPrint('[ExactAlarm] Permission already granted');
      return true;
    }

    // Request permission
    debugPrint('[ExactAlarm] Requesting permission...');
    return await requestExactAlarmPermission(context);
  }
}
