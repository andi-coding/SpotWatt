import 'package:flutter/material.dart';

class DailySummarySettings extends StatefulWidget {
  final bool dailySummaryEnabled;
  final TimeOfDay weekdaySummaryTime;
  final TimeOfDay weekendSummaryTime;
  final int dailySummaryHours;
  final ValueChanged<bool> onDailySummaryEnabledChanged;
  final ValueChanged<TimeOfDay> onWeekdaySummaryTimeChanged;
  final ValueChanged<TimeOfDay> onWeekendSummaryTimeChanged;
  final ValueChanged<int> onDailySummaryHoursChanged;

  const DailySummarySettings({
    Key? key,
    required this.dailySummaryEnabled,
    required this.weekdaySummaryTime,
    required this.weekendSummaryTime,
    required this.dailySummaryHours,
    required this.onDailySummaryEnabledChanged,
    required this.onWeekdaySummaryTimeChanged,
    required this.onWeekendSummaryTimeChanged,
    required this.onDailySummaryHoursChanged,
  }) : super(key: key);

  @override
  State<DailySummarySettings> createState() => _DailySummarySettingsState();
}

class _DailySummarySettingsState extends State<DailySummarySettings> {
  bool _showWeekendSettings = false;

  Future<void> _selectTime(BuildContext context, TimeOfDay initialTime, ValueChanged<TimeOfDay> onChanged) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked != null && picked != initialTime) {
      onChanged(picked);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(),
        SwitchListTile(
          title: const Text('Tägliche Zusammenfassung'),
          subtitle: Text('Übersicht der ${widget.dailySummaryHours} günstigsten Stunden'),
          value: widget.dailySummaryEnabled,
          onChanged: widget.onDailySummaryEnabledChanged,
        ),
        
        if (widget.dailySummaryEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Toggle für Wochentag/Wochenende
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _showWeekendSettings = false),
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !_showWeekendSettings 
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                            ),
                            child: Center(
                              child: Text(
                                'Mo-Fr',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: !_showWeekendSettings 
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _showWeekendSettings = true),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _showWeekendSettings 
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                            ),
                            child: Center(
                              child: Text(
                                'Sa-So',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _showWeekendSettings 
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Benachrichtigungszeit'),
                  subtitle: Text(
                    _formatTimeOfDay(
                      _showWeekendSettings 
                        ? widget.weekendSummaryTime 
                        : widget.weekdaySummaryTime
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: () => _selectTime(
                    context,
                    _showWeekendSettings 
                      ? widget.weekendSummaryTime 
                      : widget.weekdaySummaryTime,
                    _showWeekendSettings 
                      ? widget.onWeekendSummaryTimeChanged 
                      : widget.onWeekdaySummaryTimeChanged,
                  ),
                ),
                
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Anzahl günstigste Stunden: ${widget.dailySummaryHours}'),
                    Slider(
                      value: widget.dailySummaryHours.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: widget.dailySummaryHours.toString(),
                      onChanged: (value) => widget.onDailySummaryHoursChanged(value.round()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}