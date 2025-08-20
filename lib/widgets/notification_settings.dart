import 'package:flutter/material.dart';
import '../utils/price_utils.dart';
import 'daily_summary_settings.dart';

class NotificationSettings extends StatelessWidget {
  final bool priceThresholdEnabled;
  final bool cheapestTimeEnabled;
  final bool dailySummaryEnabled;
  final double notificationThreshold;
  final int notificationMinutesBefore;
  final TimeOfDay weekdaySummaryTime;
  final TimeOfDay weekendSummaryTime;
  final int dailySummaryHours;
  final ValueChanged<bool> onPriceThresholdEnabledChanged;
  final ValueChanged<bool> onCheapestTimeEnabledChanged;
  final ValueChanged<bool> onDailySummaryEnabledChanged;
  final ValueChanged<double> onNotificationThresholdChanged;
  final ValueChanged<double> onNotificationMinutesBeforeChanged;
  final ValueChanged<TimeOfDay> onWeekdaySummaryTimeChanged;
  final ValueChanged<TimeOfDay> onWeekendSummaryTimeChanged;
  final ValueChanged<int> onDailySummaryHoursChanged;

  const NotificationSettings({
    Key? key,
    required this.priceThresholdEnabled,
    required this.cheapestTimeEnabled,
    required this.dailySummaryEnabled,
    required this.notificationThreshold,
    required this.notificationMinutesBefore,
    required this.weekdaySummaryTime,
    required this.weekendSummaryTime,
    required this.dailySummaryHours,
    required this.onPriceThresholdEnabledChanged,
    required this.onCheapestTimeEnabledChanged,
    required this.onDailySummaryEnabledChanged,
    required this.onNotificationThresholdChanged,
    required this.onNotificationMinutesBeforeChanged,
    required this.onWeekdaySummaryTimeChanged,
    required this.onWeekendSummaryTimeChanged,
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
            DailySummarySettings(
              dailySummaryEnabled: dailySummaryEnabled,
              weekdaySummaryTime: weekdaySummaryTime,
              weekendSummaryTime: weekendSummaryTime,
              dailySummaryHours: dailySummaryHours,
              onDailySummaryEnabledChanged: onDailySummaryEnabledChanged,
              onWeekdaySummaryTimeChanged: onWeekdaySummaryTimeChanged,
              onWeekendSummaryTimeChanged: onWeekendSummaryTimeChanged,
              onDailySummaryHoursChanged: onDailySummaryHoursChanged,
            ),
          ],
        ),
      ),
    );
  }
}