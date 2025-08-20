import 'package:flutter/material.dart';

class QuietTimeSettings extends StatefulWidget {
  final bool quietTimeEnabled;
  final TimeOfDay weekdayQuietStart;
  final TimeOfDay weekdayQuietEnd;
  final TimeOfDay weekendQuietStart;
  final TimeOfDay weekendQuietEnd;
  final ValueChanged<bool> onQuietTimeEnabledChanged;
  final ValueChanged<TimeOfDay> onWeekdayQuietStartChanged;
  final ValueChanged<TimeOfDay> onWeekdayQuietEndChanged;
  final ValueChanged<TimeOfDay> onWeekendQuietStartChanged;
  final ValueChanged<TimeOfDay> onWeekendQuietEndChanged;

  const QuietTimeSettings({
    Key? key,
    required this.quietTimeEnabled,
    required this.weekdayQuietStart,
    required this.weekdayQuietEnd,
    required this.weekendQuietStart,
    required this.weekendQuietEnd,
    required this.onQuietTimeEnabledChanged,
    required this.onWeekdayQuietStartChanged,
    required this.onWeekdayQuietEndChanged,
    required this.onWeekendQuietStartChanged,
    required this.onWeekendQuietEndChanged,
  }) : super(key: key);

  @override
  State<QuietTimeSettings> createState() => _QuietTimeSettingsState();
}

class _QuietTimeSettingsState extends State<QuietTimeSettings> {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.do_not_disturb, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Benachrichtigungssteuerung',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Ruhezeiten
            SwitchListTile(
              title: const Text('Ruhezeiten'),
              subtitle: const Text('Keine Benachrichtigungen während definierter Zeiten'),
              value: widget.quietTimeEnabled,
              onChanged: widget.onQuietTimeEnabledChanged,
            ),
            
            if (widget.quietTimeEnabled) ...[
              const SizedBox(height: 8),
              
              // Toggle für Wochentag/Wochenende
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Von', style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                          _formatTimeOfDay(
                            _showWeekendSettings 
                              ? widget.weekendQuietStart 
                              : widget.weekdayQuietStart
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        onTap: () => _selectTime(
                          context,
                          _showWeekendSettings 
                            ? widget.weekendQuietStart 
                            : widget.weekdayQuietStart,
                          _showWeekendSettings 
                            ? widget.onWeekendQuietStartChanged 
                            : widget.onWeekdayQuietStartChanged,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 20),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bis', style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                          _formatTimeOfDay(
                            _showWeekendSettings 
                              ? widget.weekendQuietEnd 
                              : widget.weekdayQuietEnd
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        onTap: () => _selectTime(
                          context,
                          _showWeekendSettings 
                            ? widget.weekendQuietEnd 
                            : widget.weekdayQuietEnd,
                          _showWeekendSettings 
                            ? widget.onWeekendQuietEndChanged 
                            : widget.onWeekdayQuietEndChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}