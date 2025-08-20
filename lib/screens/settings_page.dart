import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/shelly_service.dart';
import '../utils/price_utils.dart';
import '../widgets/notification_settings.dart';
import '../widgets/shelly_login_dialog.dart';
import '../widgets/location_settings.dart';
import '../widgets/quiet_time_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final NotificationService _notificationService = NotificationService();
  
  bool priceThresholdEnabled = false;
  bool cheapestTimeEnabled = true;
  bool locationBasedNotifications = false;
  bool dailySummaryEnabled = true;
  bool quietTimeEnabled = true;
  double notificationThreshold = 5.0;
  int notificationMinutesBefore = 15;
  int dailySummaryHours = 3;
  // Wochentag-Einstellungen (Mo-Fr)
  TimeOfDay weekdayQuietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay weekdayQuietEnd = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay weekdaySummaryTime = const TimeOfDay(hour: 7, minute: 0);
  
  // Wochenend-Einstellungen (Sa-So)
  TimeOfDay weekendQuietStart = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay weekendQuietEnd = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay weekendSummaryTime = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      priceThresholdEnabled = prefs.getBool('price_threshold_enabled') ?? false;
      cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? true;
      locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
      dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? true;
      quietTimeEnabled = prefs.getBool('quiet_time_enabled') ?? true;
      notificationThreshold = prefs.getDouble('notification_threshold') ?? 5.0;
      notificationMinutesBefore = prefs.getInt('notification_minutes_before') ?? 15;
      dailySummaryHours = prefs.getInt('daily_summary_hours') ?? 3;
      
      // Wochentag-Zeiten laden
      final weekdayStartHour = prefs.getInt('weekday_quiet_start_hour') ?? 22;
      final weekdayStartMinute = prefs.getInt('weekday_quiet_start_minute') ?? 0;
      final weekdayEndHour = prefs.getInt('weekday_quiet_end_hour') ?? 7;
      final weekdayEndMinute = prefs.getInt('weekday_quiet_end_minute') ?? 0;
      final weekdaySummaryHour = prefs.getInt('weekday_summary_hour') ?? 7;
      final weekdaySummaryMinute = prefs.getInt('weekday_summary_minute') ?? 0;
      
      // Wochenend-Zeiten laden
      final weekendStartHour = prefs.getInt('weekend_quiet_start_hour') ?? 23;
      final weekendStartMinute = prefs.getInt('weekend_quiet_start_minute') ?? 0;
      final weekendEndHour = prefs.getInt('weekend_quiet_end_hour') ?? 9;
      final weekendEndMinute = prefs.getInt('weekend_quiet_end_minute') ?? 0;
      final weekendSummaryHour = prefs.getInt('weekend_summary_hour') ?? 9;
      final weekendSummaryMinute = prefs.getInt('weekend_summary_minute') ?? 0;
      
      weekdayQuietStart = TimeOfDay(hour: weekdayStartHour, minute: weekdayStartMinute);
      weekdayQuietEnd = TimeOfDay(hour: weekdayEndHour, minute: weekdayEndMinute);
      weekdaySummaryTime = TimeOfDay(hour: weekdaySummaryHour, minute: weekdaySummaryMinute);
      
      weekendQuietStart = TimeOfDay(hour: weekendStartHour, minute: weekendStartMinute);
      weekendQuietEnd = TimeOfDay(hour: weekendEndHour, minute: weekendEndMinute);
      weekendSummaryTime = TimeOfDay(hour: weekendSummaryHour, minute: weekendSummaryMinute);
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
    await prefs.setInt('notification_minutes_before', notificationMinutesBefore);
    // Wochentag-Zeiten speichern
    await prefs.setInt('weekday_quiet_start_hour', weekdayQuietStart.hour);
    await prefs.setInt('weekday_quiet_start_minute', weekdayQuietStart.minute);
    await prefs.setInt('weekday_quiet_end_hour', weekdayQuietEnd.hour);
    await prefs.setInt('weekday_quiet_end_minute', weekdayQuietEnd.minute);
    await prefs.setInt('weekday_summary_hour', weekdaySummaryTime.hour);
    await prefs.setInt('weekday_summary_minute', weekdaySummaryTime.minute);
    
    // Wochenend-Zeiten speichern
    await prefs.setInt('weekend_quiet_start_hour', weekendQuietStart.hour);
    await prefs.setInt('weekend_quiet_start_minute', weekendQuietStart.minute);
    await prefs.setInt('weekend_quiet_end_hour', weekendQuietEnd.hour);
    await prefs.setInt('weekend_quiet_end_minute', weekendQuietEnd.minute);
    await prefs.setInt('weekend_summary_hour', weekendSummaryTime.hour);
    await prefs.setInt('weekend_summary_minute', weekendSummaryTime.minute);
    await prefs.setInt('daily_summary_hours', dailySummaryHours);
  }

  Future<bool> _checkShellyAuth() async {
    final shellyService = ShellyService();
    return await shellyService.loadCredentials();
  }

  Future<String?> _getShellyEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('shelly_email');
  }

  void _showShellyLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShellyLoginDialog(
        onLoginSuccess: () {
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NotificationSettings(
            priceThresholdEnabled: priceThresholdEnabled,
            cheapestTimeEnabled: cheapestTimeEnabled,
            dailySummaryEnabled: dailySummaryEnabled,
            notificationThreshold: notificationThreshold,
            notificationMinutesBefore: notificationMinutesBefore,
            weekdaySummaryTime: weekdaySummaryTime,
            weekendSummaryTime: weekendSummaryTime,
            dailySummaryHours: dailySummaryHours,
            onPriceThresholdEnabledChanged: (value) async {
              setState(() {
                priceThresholdEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Price threshold changed to: $value');
            },
            onCheapestTimeEnabledChanged: (value) async {
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
              setState(() {
                dailySummaryEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onWeekdaySummaryTimeChanged: (value) async {
              setState(() {
                weekdaySummaryTime = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onWeekendSummaryTimeChanged: (value) async {
              setState(() {
                weekendSummaryTime = value;
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
          ),
          
          const SizedBox(height: 16),
          
          LocationSettings(
            locationBasedNotifications: locationBasedNotifications,
            onLocationBasedChanged: (value) async {
              setState(() {
                locationBasedNotifications = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Location based notifications changed to: $value');
            },
          ),
          
          const SizedBox(height: 16),
          
          QuietTimeSettings(
            quietTimeEnabled: quietTimeEnabled,
            weekdayQuietStart: weekdayQuietStart,
            weekdayQuietEnd: weekdayQuietEnd,
            weekendQuietStart: weekendQuietStart,
            weekendQuietEnd: weekendQuietEnd,
            onQuietTimeEnabledChanged: (value) async {
              setState(() {
                quietTimeEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onWeekdayQuietStartChanged: (value) async {
              setState(() {
                weekdayQuietStart = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onWeekdayQuietEndChanged: (value) async {
              setState(() {
                weekdayQuietEnd = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onWeekendQuietStartChanged: (value) async {
              setState(() {
                weekendQuietStart = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
            onWeekendQuietEndChanged: (value) async {
              setState(() {
                weekendQuietEnd = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
            },
          ),
          
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Einstellungen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('aWATTar API'),
                    subtitle: const Text('Verbunden'),
                    trailing: const Icon(Icons.check_circle, color: Colors.green),
                  ),
                  ListTile(
                    title: const Text('Shelly Cloud'),
                    subtitle: FutureBuilder<bool>(
                      future: _checkShellyAuth(),
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return FutureBuilder<String?>(
                            future: _getShellyEmail(),
                            builder: (context, emailSnapshot) {
                              return Text('Verbunden als ${emailSnapshot.data ?? '...'}');
                            },
                          );
                        }
                        return const Text('Nicht verbunden');
                      },
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _showShellyLoginDialog,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.update, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Background Updates',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Die App aktualisiert Strompreise automatisch im Hintergrund:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Funktioniert auch wenn die App geschlossen ist!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}