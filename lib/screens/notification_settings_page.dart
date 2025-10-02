import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../services/location_permission_helper.dart';
import '../utils/price_utils.dart';
import '../widgets/notification_settings.dart';
import '../widgets/do_not_disturb_settings.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final NotificationService _notificationService = NotificationService();
  final LocationService _locationService = LocationService();
  
  bool priceThresholdEnabled = false;
  bool cheapestTimeEnabled = false;
  bool locationBasedNotifications = false;
  bool dailySummaryEnabled = false;
  bool quietTimeEnabled = false;
  double notificationThreshold = 5.0;
  double highPriceThreshold = 50.0;
  int notificationMinutesBefore = 15;
  int dailySummaryHours = 3;
  TimeOfDay quietTimeStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay quietTimeEnd = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay dailySummaryTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      priceThresholdEnabled = prefs.getBool('price_threshold_enabled') ?? false;
      cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? false;
      locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
      dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? false;
      quietTimeEnabled = prefs.getBool('quiet_time_enabled') ?? false;
      notificationThreshold = prefs.getDouble('notification_threshold') ?? 5.0;
      highPriceThreshold = prefs.getDouble('high_price_threshold') ?? 50.0;
      notificationMinutesBefore = prefs.getInt('notification_minutes_before') ?? 15;
      dailySummaryHours = prefs.getInt('daily_summary_hours') ?? 3;
      
      final startHour = prefs.getInt('quiet_time_start_hour') ?? 22;
      final startMinute = prefs.getInt('quiet_time_start_minute') ?? 0;
      final endHour = prefs.getInt('quiet_time_end_hour') ?? 6;
      final endMinute = prefs.getInt('quiet_time_end_minute') ?? 0;
      
      final summaryHour = prefs.getInt('daily_summary_hour') ?? 7;
      final summaryMinute = prefs.getInt('daily_summary_minute') ?? 0;
      
      quietTimeStart = TimeOfDay(hour: startHour, minute: startMinute);
      quietTimeEnd = TimeOfDay(hour: endHour, minute: endMinute);
      dailySummaryTime = TimeOfDay(hour: summaryHour, minute: summaryMinute);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('price_threshold_enabled', priceThresholdEnabled);
    await prefs.setBool('quiet_time_enabled', quietTimeEnabled);
    await prefs.setBool('cheapest_time_enabled', cheapestTimeEnabled);
    await prefs.setBool('location_based_notifications', locationBasedNotifications);
    await prefs.setBool('daily_summary_enabled', dailySummaryEnabled);
    await prefs.setDouble('notification_threshold', notificationThreshold);
    await prefs.setDouble('high_price_threshold', highPriceThreshold);
    await prefs.setInt('notification_minutes_before', notificationMinutesBefore);
    await prefs.setInt('quiet_time_start_hour', quietTimeStart.hour);
    await prefs.setInt('quiet_time_start_minute', quietTimeStart.minute);
    await prefs.setInt('quiet_time_end_hour', quietTimeEnd.hour);
    await prefs.setInt('quiet_time_end_minute', quietTimeEnd.minute);
    await prefs.setInt('daily_summary_hour', dailySummaryTime.hour);
    await prefs.setInt('daily_summary_minute', dailySummaryTime.minute);
    await prefs.setInt('daily_summary_hours', dailySummaryHours);
  }

  Future<bool> _checkNotificationPermission() async {
    final plugin = FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.areNotificationsEnabled() ?? false;
    }

    return true; // iOS prüft automatisch bei requestPermission
  }

  Future<bool> _requestNotificationPermission() async {
    final plugin = FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      final androidImpl = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.requestNotificationsPermission() ?? false;
    } else if (Platform.isIOS) {
      final iosImpl = plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      ) ?? false;
    }

    return false;
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Berechtigung erforderlich'),
        content: const Text(
          'Um Benachrichtigungen zu erhalten, musst du die Berechtigung in den App-Einstellungen aktivieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureNotificationPermission() async {
    final hasPermission = await _checkNotificationPermission();

    if (!hasPermission) {
      final granted = await _requestNotificationPermission();

      if (!granted) {
        _showPermissionDeniedDialog();
        return false;
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NotificationSettings(
            priceThresholdEnabled: priceThresholdEnabled,
            cheapestTimeEnabled: cheapestTimeEnabled,
            dailySummaryEnabled: dailySummaryEnabled,
            highPriceWarningEnabled: false,  // Not used anymore, controlled by slider value
            notificationThreshold: notificationThreshold,
            highPriceThreshold: highPriceThreshold,
            notificationMinutesBefore: notificationMinutesBefore,
            dailySummaryTime: dailySummaryTime,
            dailySummaryHours: dailySummaryHours,
            onPriceThresholdEnabledChanged: (value) async {
              if (value) {
                // User will Benachrichtigung aktivieren - Permission prüfen
                final hasPermission = await _ensureNotificationPermission();
                if (!hasPermission) {
                  return; // Permission verweigert
                }
              }

              setState(() {
                priceThresholdEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Price threshold changed to: $value');
            },
            onCheapestTimeEnabledChanged: (value) async {
              if (value) {
                final hasPermission = await _ensureNotificationPermission();
                if (!hasPermission) {
                  return;
                }
              }

              setState(() {
                cheapestTimeEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Cheapest time notifications changed to: $value');
            },
            onNotificationThresholdChanged: (value) async {
              setState(() {
                notificationThreshold = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Notification threshold changed to: ${PriceUtils.formatPrice(value)}');
            },
            onNotificationMinutesBeforeChanged: (value) async {
              setState(() {
                notificationMinutesBefore = value.toInt();
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Notification minutes before changed to: ${value.toInt()}');
            },
            onDailySummaryEnabledChanged: (value) async {
              if (value) {
                final hasPermission = await _ensureNotificationPermission();
                if (!hasPermission) {
                  return;
                }
              }

              setState(() {
                dailySummaryEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onDailySummaryTimeChanged: (value) async {
              setState(() {
                dailySummaryTime = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onDailySummaryHoursChanged: (value) async {
              setState(() {
                dailySummaryHours = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onHighPriceWarningEnabledChanged: (value) async {
              // Not used anymore, keeping for compatibility
            },
            onHighPriceThresholdChanged: (value) async {
              setState(() {
                highPriceThreshold = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('High price threshold changed to: ${PriceUtils.formatPrice(value)}');
            },
          ),
          
          const SizedBox(height: 16),
          
          DoNotDisturbSettings(
            locationBasedNotifications: locationBasedNotifications,
            quietTimeEnabled: quietTimeEnabled,
            quietTimeStart: quietTimeStart,
            quietTimeEnd: quietTimeEnd,
            onLocationBasedChanged: (value) async {
              if (value) {
                debugPrint('Requesting location permissions for geofencing...');
                final granted = await LocationPermissionHelper.requestLocationPermissions(context);
                
                if (!granted) {
                  debugPrint('Location permissions denied - cannot enable location-based notifications');
                  return;
                }
                
                debugPrint('Location permissions granted - enabling location-based notifications');
              }
              
              setState(() {
                locationBasedNotifications = value;
              });
              await _saveSettings();
              
              if (value) {
                debugPrint('Setting up geofence');
                await _locationService.enableLocationBasedNotifications();
              } else {
                debugPrint('Disabling location-based notifications - removing geofence');
                await _locationService.disableLocationBasedNotifications();
              }
              
              await _notificationService.scheduleNotifications();
            },
            onQuietTimeEnabledChanged: (value) async {
              setState(() {
                quietTimeEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onQuietTimeStartChanged: (value) async {
              setState(() {
                quietTimeStart = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onQuietTimeEndChanged: (value) async {
              setState(() {
                quietTimeEnd = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
          ),
        ],
      ),
    );
  }
}