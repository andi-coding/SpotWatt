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
  double notificationThreshold = 10.0;
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
      notificationThreshold = prefs.getDouble('notification_threshold') ?? 10.0;
      notificationMinutesBefore = prefs.getInt('notification_minutes_before') ?? 15;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', notificationsEnabled);
    await prefs.setBool('price_threshold_enabled', priceThresholdEnabled);
    await prefs.setBool('cheapest_time_enabled', cheapestTimeEnabled);
    await prefs.setDouble('notification_threshold', notificationThreshold);
    await prefs.setInt('notification_minutes_before', notificationMinutesBefore);
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
            onNotificationsEnabledChanged: (value) {
              setState(() {
                notificationsEnabled = value;
                if (value) {
                  _notificationService.scheduleNotifications();
                } else {
                  _notificationService.cancelAllNotifications();
                }
              });
              _saveSettings();
            },
            onPriceThresholdEnabledChanged: (value) {
              setState(() {
                priceThresholdEnabled = value;
                _notificationService.scheduleNotifications();
              });
              _saveSettings();
            },
            onCheapestTimeEnabledChanged: (value) {
              setState(() {
                cheapestTimeEnabled = value;
                _notificationService.scheduleNotifications();
              });
              _saveSettings();
            },
            onNotificationThresholdChanged: (value) {
              setState(() {
                notificationThreshold = value;
              });
              _saveSettings();
            },
            onNotificationMinutesBeforeChanged: (value) {
              setState(() {
                notificationMinutesBefore = value.toInt();
              });
              _saveSettings();
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
                          _notificationService.scheduleNotifications();
                        });
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
                          _notificationService.scheduleNotifications();
                        });
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
          
          ElevatedButton.icon(
            onPressed: () => _notificationService.scheduleNotifications(),
            icon: const Icon(Icons.refresh),
            label: const Text('Benachrichtigungen aktualisieren'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
}