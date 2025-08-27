import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../services/shelly_service.dart';
import '../services/location_permission_helper.dart';
import '../utils/price_utils.dart';
import '../widgets/notification_settings.dart';
import '../widgets/shelly_login_dialog.dart';
import '../widgets/do_not_disturb_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final NotificationService _notificationService = NotificationService();
  final LocationService _locationService = LocationService();
  
  bool priceThresholdEnabled = false;
  bool cheapestTimeEnabled = true;
  bool locationBasedNotifications = false;
  bool dailySummaryEnabled = true;
  bool quietTimeEnabled = true;
  bool highPriceWarningEnabled = false;
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
      cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? true;
      locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
      dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? true;
      quietTimeEnabled = prefs.getBool('quiet_time_enabled') ?? true;
      highPriceWarningEnabled = prefs.getBool('high_price_warning_enabled') ?? false;
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
    await prefs.setBool('high_price_warning_enabled', highPriceWarningEnabled);
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
            highPriceWarningEnabled: highPriceWarningEnabled,
            notificationThreshold: notificationThreshold,
            highPriceThreshold: highPriceThreshold,
            notificationMinutesBefore: notificationMinutesBefore,
            dailySummaryTime: dailySummaryTime,
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
              setState(() {
                highPriceWarningEnabled = value;
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('High price warning changed to: $value');
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
                // First request location permissions when enabling
                debugPrint('Requesting location permissions for geofencing...');
                final granted = await LocationPermissionHelper.requestLocationPermissions(context);
                
                if (!granted) {
                  // If permission denied, don't enable the feature
                  debugPrint('Location permissions denied - cannot enable location-based notifications');
                  return;
                }
                
                debugPrint('Location permissions granted - enabling location-based notifications');
              }
              
              setState(() {
                locationBasedNotifications = value;
              });
              await _saveSettings();
              
              // Setup or remove geofencing based on the setting
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
                  // Hidden for now - keeping code for later
                  /*
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
                  */
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