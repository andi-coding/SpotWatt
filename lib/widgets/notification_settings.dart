import 'package:flutter/material.dart';
import '../utils/price_utils.dart';

class NotificationSettings extends StatefulWidget {
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
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  late double _tempNotificationThreshold;
  late double _tempHighPriceThreshold;
  late int _tempNotificationMinutesBefore;
  late int _tempDailySummaryHours;

  @override
  void initState() {
    super.initState();
    _tempNotificationThreshold = widget.notificationThreshold;
    _tempHighPriceThreshold = widget.highPriceThreshold;
    _tempNotificationMinutesBefore = widget.notificationMinutesBefore;
    _tempDailySummaryHours = widget.dailySummaryHours;
  }

  @override
  void didUpdateWidget(NotificationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notificationThreshold != widget.notificationThreshold) {
      _tempNotificationThreshold = widget.notificationThreshold;
    }
    if (oldWidget.highPriceThreshold != widget.highPriceThreshold) {
      _tempHighPriceThreshold = widget.highPriceThreshold;
    }
    if (oldWidget.notificationMinutesBefore != widget.notificationMinutesBefore) {
      _tempNotificationMinutesBefore = widget.notificationMinutesBefore;
    }
    if (oldWidget.dailySummaryHours != widget.dailySummaryHours) {
      _tempDailySummaryHours = widget.dailySummaryHours;
    }
  }

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
                Expanded(
                  child: Text(
                    'Benachrichtigungen',
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 1. Tägliche Zusammenfassung (erste Position)
            SwitchListTile(
              title: const Text('Tägliche Zusammenfassung'),
              subtitle: Text('Übersicht der günstigsten Stunden + Warnung vor teuren Preisen'),
              value: widget.dailySummaryEnabled,
              onChanged: widget.onDailySummaryEnabledChanged,
            ),
            if (widget.dailySummaryEnabled) 
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zeige $_tempDailySummaryHours günstigste Stunden'),
                        Slider(
                          value: _tempDailySummaryHours.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          label: _tempDailySummaryHours.toString(),
                          onChanged: (value) {
                            setState(() {
                              _tempDailySummaryHours = value.round();
                            });
                          },
                          onChangeEnd: (value) {
                            widget.onDailySummaryHoursChanged(value.round());
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Hohe Preis Warnschwelle (nur Slider, kein Switch)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tempHighPriceThreshold < 200 
                            ? 'Warnung bei Preisen > ${PriceUtils.formatPrice(_tempHighPriceThreshold)}'
                            : 'Warnung vor teuren Preisen deaktiviert',
                          style: TextStyle(
                            color: _tempHighPriceThreshold < 200 
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Slider(
                          value: _tempHighPriceThreshold,
                          min: 20,
                          max: 200,
                          divisions: 18,
                          label: _tempHighPriceThreshold < 200 
                            ? PriceUtils.formatPrice(_tempHighPriceThreshold).replaceAll(' ct/kWh', '')
                            : 'Aus',
                          onChanged: (value) {
                            setState(() {
                              _tempHighPriceThreshold = value;
                            });
                          },
                          onChangeEnd: (value) {
                            widget.onHighPriceThresholdChanged(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Benachrichtigungszeit'),
                      subtitle: Text(
                        '${widget.dailySummaryTime.hour.toString().padLeft(2, '0')}:${widget.dailySummaryTime.minute.toString().padLeft(2, '0')} Uhr',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: widget.dailySummaryTime,
                        );
                        if (time != null) {
                          widget.onDailySummaryTimeChanged(time);
                        }
                      },
                    ),
                  ],
                ),
              ),
            
            const Divider(),
            
            // 2. Günstigste Zeit des Tages (zweite Position)
            SwitchListTile(
              title: const Text('Günstigste Zeit des Tages'),
              subtitle: const Text('Benachrichtigung vor dem günstigsten Zeitpunkt des Tages'),
              value: widget.cheapestTimeEnabled,
              onChanged: widget.onCheapestTimeEnabledChanged,
            ),
            if (widget.cheapestTimeEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vorlaufzeit: $_tempNotificationMinutesBefore Minuten'),
                    Slider(
                      value: _tempNotificationMinutesBefore.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '$_tempNotificationMinutesBefore Min.',
                      onChanged: (value) {
                        setState(() {
                          _tempNotificationMinutesBefore = value.toInt();
                        });
                      },
                      onChangeEnd: (value) {
                        widget.onNotificationMinutesBeforeChanged(value);
                      },
                    ),
                  ],
                ),
              ),
            
            const Divider(),
            
            // 3. Preis-Schwellwert (dritte Position)
            SwitchListTile(
              title: const Text('Günstige Preise'),
              subtitle: Text(
                widget.priceThresholdEnabled
                  ? 'Benachrichtigung wenn Preis unterhalb von ${PriceUtils.formatPrice(_tempNotificationThreshold)} liegt'
                  : 'Benachrichtigung wenn Preis unterhalb von ... ct/kWh liegt'
              ),
              value: widget.priceThresholdEnabled,
              onChanged: widget.onPriceThresholdEnabledChanged,
            ),
            if (widget.priceThresholdEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    //Text('Schwellwert: ${PriceUtils.formatPrice(notificationThreshold)}'),
                    Slider(
                      value: _tempNotificationThreshold,
                      min: -10,
                      max: 30,
                      divisions: 40,
                      label: PriceUtils.formatPrice(_tempNotificationThreshold).replaceAll(' ct/kWh', ''),
                      onChanged: (value) {
                        setState(() {
                          _tempNotificationThreshold = value;
                        });
                      },
                      onChangeEnd: (value) {
                        widget.onNotificationThresholdChanged(value);
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