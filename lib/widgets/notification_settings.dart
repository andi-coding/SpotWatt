import 'package:flutter/material.dart';

class NotificationSettings extends StatelessWidget {
  final bool notificationsEnabled;
  final bool priceThresholdEnabled;
  final bool cheapestTimeEnabled;
  final double notificationThreshold;
  final int notificationMinutesBefore;
  final ValueChanged<bool> onNotificationsEnabledChanged;
  final ValueChanged<bool> onPriceThresholdEnabledChanged;
  final ValueChanged<bool> onCheapestTimeEnabledChanged;
  final ValueChanged<double> onNotificationThresholdChanged;
  final ValueChanged<double> onNotificationMinutesBeforeChanged;

  const NotificationSettings({
    Key? key,
    required this.notificationsEnabled,
    required this.priceThresholdEnabled,
    required this.cheapestTimeEnabled,
    required this.notificationThreshold,
    required this.notificationMinutesBefore,
    required this.onNotificationsEnabledChanged,
    required this.onPriceThresholdEnabledChanged,
    required this.onCheapestTimeEnabledChanged,
    required this.onNotificationThresholdChanged,
    required this.onNotificationMinutesBeforeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benachrichtigungen',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Push-Benachrichtigungen'),
              subtitle: const Text('Hauptschalter für alle Benachrichtigungen'),
              value: notificationsEnabled,
              onChanged: onNotificationsEnabledChanged,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Preis-Schwellwert'),
              subtitle: Text('Benachrichtigung wenn Preis unter ${notificationThreshold.toStringAsFixed(2)} ct/kWh'),
              value: priceThresholdEnabled && notificationsEnabled,
              onChanged: notificationsEnabled ? onPriceThresholdEnabledChanged : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Schwellwert: ${notificationThreshold.toStringAsFixed(2)} ct/kWh'),
                  Slider(
                    value: notificationThreshold,
                    min: 0,
                    max: 30,
                    divisions: 60,
                    label: notificationThreshold.toStringAsFixed(2),
                    onChanged: (notificationsEnabled && priceThresholdEnabled) 
                      ? onNotificationThresholdChanged 
                      : null,
                  ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Günstigste Zeit'),
              subtitle: Text('$notificationMinutesBefore Min. vor dem günstigsten Zeitpunkt'),
              value: cheapestTimeEnabled && notificationsEnabled,
              onChanged: notificationsEnabled ? onCheapestTimeEnabledChanged : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vorlaufzeit: $notificationMinutesBefore Minuten'),
                  Slider(
                    value: notificationMinutesBefore.toDouble(),
                    min: 5,
                    max: 60,
                    divisions: 11,
                    label: '$notificationMinutesBefore Min.',
                    onChanged: (notificationsEnabled && cheapestTimeEnabled) 
                      ? onNotificationMinutesBeforeChanged 
                      : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}