import 'package:flutter/material.dart';
import '../utils/price_utils.dart';

class NotificationSettings extends StatelessWidget {
  final bool priceThresholdEnabled;
  final bool cheapestTimeEnabled;
  final double notificationThreshold;
  final int notificationMinutesBefore;
  final ValueChanged<bool> onPriceThresholdEnabledChanged;
  final ValueChanged<bool> onCheapestTimeEnabledChanged;
  final ValueChanged<double> onNotificationThresholdChanged;
  final ValueChanged<double> onNotificationMinutesBeforeChanged;

  const NotificationSettings({
    Key? key,
    required this.priceThresholdEnabled,
    required this.cheapestTimeEnabled,
    required this.notificationThreshold,
    required this.notificationMinutesBefore,
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
            Row(
              children: [
                Icon(Icons.notifications, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Benachrichtigungen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Preis-Schwellwert'),
              subtitle: const Text('Stündliche Benachrichtigung wenn Preis unterhalb von Schwellwert liegt'),
              value: priceThresholdEnabled,
              onChanged: onPriceThresholdEnabledChanged,
            ),
            if (priceThresholdEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schwellwert: ${PriceUtils.formatPrice(notificationThreshold)}'),
                    Slider(
                      value: notificationThreshold,
                      min: -10,
                      max: 30,
                      divisions: 80,
                      label: PriceUtils.formatPrice(notificationThreshold).replaceAll(' ct/kWh', ''),
                      onChanged: onNotificationThresholdChanged,
                    ),
                  ],
                ),
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('Günstigste Zeit des Tages'),
              subtitle: const Text('Benachrichtigung vor dem günstigsten Zeitpunkt des Tages'),
              value: cheapestTimeEnabled,
              onChanged: onCheapestTimeEnabledChanged,
            ),
            if (cheapestTimeEnabled)
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
                      onChanged: onNotificationMinutesBeforeChanged,
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