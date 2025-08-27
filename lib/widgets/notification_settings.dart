import 'package:flutter/material.dart';
import '../utils/price_utils.dart';

class NotificationSettings extends StatelessWidget {
  final bool priceThresholdEnabled;
  final bool cheapestTimeEnabled;
  final bool dailySummaryEnabled;
  final bool highPriceWarningEnabled;
  final double notificationThreshold;
  final double highPriceThreshold;
  final int notificationMinutesBefore;
  final TimeOfDay dailySummaryTime;
  final int dailySummaryHours;
  final ValueChanged<bool> onPriceThresholdEnabledChanged;
  final ValueChanged<bool> onCheapestTimeEnabledChanged;
  final ValueChanged<bool> onDailySummaryEnabledChanged;
  final ValueChanged<bool> onHighPriceWarningEnabledChanged;
  final ValueChanged<double> onNotificationThresholdChanged;
  final ValueChanged<double> onHighPriceThresholdChanged;
  final ValueChanged<double> onNotificationMinutesBeforeChanged;
  final ValueChanged<TimeOfDay> onDailySummaryTimeChanged;
  final ValueChanged<int> onDailySummaryHoursChanged;

  const NotificationSettings({
    Key? key,
    required this.priceThresholdEnabled,
    required this.cheapestTimeEnabled,
    required this.dailySummaryEnabled,
    required this.highPriceWarningEnabled,
    required this.notificationThreshold,
    required this.highPriceThreshold,
    required this.notificationMinutesBefore,
    required this.dailySummaryTime,
    required this.dailySummaryHours,
    required this.onPriceThresholdEnabledChanged,
    required this.onCheapestTimeEnabledChanged,
    required this.onDailySummaryEnabledChanged,
    required this.onHighPriceWarningEnabledChanged,
    required this.onNotificationThresholdChanged,
    required this.onHighPriceThresholdChanged,
    required this.onNotificationMinutesBeforeChanged,
    required this.onDailySummaryTimeChanged,
    required this.onDailySummaryHoursChanged,
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
            const Divider(),
            SwitchListTile(
              title: const Text('Tägliche Zusammenfassung'),
              subtitle: Text('Übersicht der günstigsten Stunden + Warnung vor teuren Preisen'),
              value: dailySummaryEnabled,
              onChanged: onDailySummaryEnabledChanged,
            ),
            if (dailySummaryEnabled) 
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zeige $dailySummaryHours günstigste Stunden'),
                        Slider(
                          value: dailySummaryHours.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          label: dailySummaryHours.toString(),
                          onChanged: (value) => onDailySummaryHoursChanged(value.round()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Warnung vor teuren Preisen'),
                      subtitle: const Text('Zusätzlich Warnung wenn Preise über Schwelle'),
                      value: highPriceWarningEnabled,
                      onChanged: onHighPriceWarningEnabledChanged,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (highPriceWarningEnabled)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Warnschwelle: ${PriceUtils.formatPrice(highPriceThreshold)}'),
                          Slider(
                            value: highPriceThreshold,
                            min: 20,
                            max: 200,
                            divisions: 18,
                            label: PriceUtils.formatPrice(highPriceThreshold).replaceAll(' ct/kWh', ''),
                            onChanged: onHighPriceThresholdChanged,
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Benachrichtigungszeit'),
                      subtitle: Text(
                        '${dailySummaryTime.hour.toString().padLeft(2, '0')}:${dailySummaryTime.minute.toString().padLeft(2, '0')} Uhr',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: dailySummaryTime,
                        );
                        if (time != null) {
                          onDailySummaryTimeChanged(time);
                        }
                      },
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