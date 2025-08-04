import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/shelly_service.dart';
import '../widgets/notification_settings.dart';
import '../widgets/shelly_login_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final NotificationService _notificationService = NotificationService();
  
  bool notificationsEnabled = true;
  bool priceThresholdEnabled = true;
  bool cheapestTimeEnabled = true;
  double notificationThreshold = 5.0;
  int notificationMinutesBefore = 15;
  TimeOfDay quietTimeStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay quietTimeEnd = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      priceThresholdEnabled = prefs.getBool('price_threshold_enabled') ?? true;
      cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? true;
      notificationThreshold = prefs.getDouble('notification_threshold') ?? 5.0;
      notificationMinutesBefore = prefs.getInt('notification_minutes_before') ?? 15;
      
      final startHour = prefs.getInt('quiet_time_start_hour') ?? 22;
      final startMinute = prefs.getInt('quiet_time_start_minute') ?? 0;
      final endHour = prefs.getInt('quiet_time_end_hour') ?? 7;
      final endMinute = prefs.getInt('quiet_time_end_minute') ?? 0;
      
      quietTimeStart = TimeOfDay(hour: startHour, minute: startMinute);
      quietTimeEnd = TimeOfDay(hour: endHour, minute: endMinute);
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', notificationsEnabled);
    await prefs.setBool('price_threshold_enabled', priceThresholdEnabled);
    await prefs.setBool('cheapest_time_enabled', cheapestTimeEnabled);
    await prefs.setDouble('notification_threshold', notificationThreshold);
    await prefs.setInt('notification_minutes_before', notificationMinutesBefore);
    await prefs.setInt('quiet_time_start_hour', quietTimeStart.hour);
    await prefs.setInt('quiet_time_start_minute', quietTimeStart.minute);
    await prefs.setInt('quiet_time_end_hour', quietTimeEnd.hour);
    await prefs.setInt('quiet_time_end_minute', quietTimeEnd.minute);
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
            notificationsEnabled: notificationsEnabled,
            priceThresholdEnabled: priceThresholdEnabled,
            cheapestTimeEnabled: cheapestTimeEnabled,
            notificationThreshold: notificationThreshold,
            notificationMinutesBefore: notificationMinutesBefore,
            onNotificationsEnabledChanged: (value) async {
              setState(() {
                notificationsEnabled = value;
              });
              await _saveSettings();
              
              if (value) {
                await _notificationService.scheduleNotifications();
                debugPrint('Notifications enabled and scheduled');
              } else {
                await _notificationService.cancelAllNotifications();
                debugPrint('All notifications cancelled');
              }
            },
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
              debugPrint('Notification threshold changed to: ${value.toStringAsFixed(2)} ct/kWh');
            },
            onNotificationMinutesBeforeChanged: (value) async {
              setState(() {
                notificationMinutesBefore = value.toInt();
              });
              await _saveSettings();
              await _notificationService.scheduleNotifications();
              debugPrint('Notification minutes before changed to: ${value.toInt()}');
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
                    'Ruhezeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keine Benachrichtigungen während der Ruhezeiten',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Ruhezeit Start'),
                    subtitle: Text('${quietTimeStart.hour}:${quietTimeStart.minute.toString().padLeft(2, '0')} Uhr'),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: quietTimeStart,
                      );
                      if (time != null) {
                        setState(() {
                          quietTimeStart = time;
                        });
                        await _saveSettings();
                        await _notificationService.scheduleNotifications();
                        debugPrint('Quiet time start changed to: ${time.format(context)}');
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Ruhezeit Ende'),
                    subtitle: Text('${quietTimeEnd.hour}:${quietTimeEnd.minute.toString().padLeft(2, '0')} Uhr'),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: quietTimeEnd,
                      );
                      if (time != null) {
                        setState(() {
                          quietTimeEnd = time;
                        });
                        await _saveSettings();
                        await _notificationService.scheduleNotifications();
                        debugPrint('Quiet time end changed to: ${time.format(context)}');
                      }
                    },
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
                  const SizedBox(height: 8),
                  const Text('• Täglich zwischen 13-15 Uhr für Morgen-Preise'),
                  const Text('• Nachts für neue Tagespreise'),
                  const Text('• Alle 6 Stunden als Backup'),
                  const SizedBox(height: 8),
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