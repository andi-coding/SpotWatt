import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/shelly_service.dart';
import '../utils/price_utils.dart';
import '../widgets/notification_settings.dart';
import '../widgets/shelly_login_dialog.dart';
import '../widgets/location_settings.dart';

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
  TimeOfDay quietTimeStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay quietTimeEnd = const TimeOfDay(hour: 7, minute: 0);
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
      notificationThreshold = prefs.getDouble('notification_threshold') ?? 5.0;
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
            notificationThreshold: notificationThreshold,
            notificationMinutesBefore: notificationMinutesBefore,
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
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.summarize, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Tägliche Zusammenfassung',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Tägliche Übersicht'),
                    subtitle: Text('Erhalte täglich eine Übersicht der $dailySummaryHours günstigsten Stunden'),
                    value: dailySummaryEnabled,
                    onChanged: (value) async {
                      setState(() {
                        dailySummaryEnabled = value;
                      });
                      await _saveSettings();
                      await _notificationService.scheduleNotifications();
                      debugPrint('Daily summary changed to: $value');
                    },
                  ),
                  if (dailySummaryEnabled) ...[
                    const Divider(),
                    ListTile(
                      title: const Text('Benachrichtigungszeit'),
                      subtitle: Text('${dailySummaryTime.hour}:${dailySummaryTime.minute.toString().padLeft(2, '0')} Uhr'),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: dailySummaryTime,
                        );
                        if (time != null) {
                          setState(() {
                            dailySummaryTime = time;
                          });
                          await _saveSettings();
                          await _notificationService.scheduleNotifications();
                          debugPrint('Daily summary time changed to: ${time.format(context)}');
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Anzahl Stunden: $dailySummaryHours'),
                          Slider(
                            value: dailySummaryHours.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '$dailySummaryHours',
                            onChanged: (value) {
                              setState(() {
                                dailySummaryHours = value.toInt();
                              });
                            },
                            onChangeEnd: (value) async {
                              await _saveSettings();
                              await _notificationService.scheduleNotifications();
                              debugPrint('Daily summary hours changed to: ${value.toInt()}');
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      Icon(Icons.nights_stay, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Ruhezeiten',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Ruhezeiten aktivieren'),
                    subtitle: const Text('Keine Benachrichtigungen während der Ruhezeiten'),
                    value: quietTimeEnabled,
                    onChanged: (value) async {
                      setState(() {
                        quietTimeEnabled = value;
                      });
                      await _saveSettings();
                      await _notificationService.scheduleNotifications();
                      debugPrint('Quiet time enabled changed to: $value');
                    },
                  ),
                  if (quietTimeEnabled) ...[
                    const Divider(),
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