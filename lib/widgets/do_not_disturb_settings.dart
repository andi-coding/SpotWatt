import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class DoNotDisturbSettings extends StatefulWidget {
  final bool locationBasedNotifications;
  final bool quietTimeEnabled;
  final TimeOfDay quietTimeStart;
  final TimeOfDay quietTimeEnd;
  final ValueChanged<bool> onLocationBasedChanged;
  final ValueChanged<bool> onQuietTimeEnabledChanged;
  final ValueChanged<TimeOfDay> onQuietTimeStartChanged;
  final ValueChanged<TimeOfDay> onQuietTimeEndChanged;

  const DoNotDisturbSettings({
    Key? key,
    required this.locationBasedNotifications,
    required this.quietTimeEnabled,
    required this.quietTimeStart,
    required this.quietTimeEnd,
    required this.onLocationBasedChanged,
    required this.onQuietTimeEnabledChanged,
    required this.onQuietTimeStartChanged,
    required this.onQuietTimeEndChanged,
  }) : super(key: key);

  @override
  State<DoNotDisturbSettings> createState() => _DoNotDisturbSettingsState();
}

class _DoNotDisturbSettingsState extends State<DoNotDisturbSettings> with WidgetsBindingObserver {
  final LocationService _locationService = LocationService();
  bool _hasHomeLocation = false;
  double _homeRadius = 100.0;
  bool _isLoading = false;
  String? _homeAddress;
  bool _isLocationServiceEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkHomeLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[DoNotDisturb] App lifecycle changed: $state');
    
    if (state == AppLifecycleState.resumed) {
      debugPrint('[DoNotDisturb] App resumed - refreshing location status');
      // User returned from background (e.g., from Android Settings)
      // Refresh location service status
      _checkHomeLocation();
    }
  }

  Future<void> _checkHomeLocation() async {
    final homeLocation = await _locationService.getHomeLocation();
    final radius = await _locationService.getHomeRadius();
    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    String? address;
    
    if (homeLocation != null) {
      address = await _locationService.getAddressFromLocation(
        homeLocation['latitude']!, 
        homeLocation['longitude']!
      );
    }
    
    if (mounted) {
      setState(() {
        _hasHomeLocation = homeLocation != null;
        _homeRadius = radius < 100 ? 100.0 : radius;
        _homeAddress = address;
        _isLocationServiceEnabled = locationServiceEnabled;
      });
    }
  }

  Future<void> _setCurrentLocationAsHome() async {
    setState(() => _isLoading = true);
    
    final success = await _locationService.saveHomeLocation();
    
    if (mounted) {
      setState(() => _isLoading = false);
      
      if (success) {
        await _checkHomeLocation();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Standort als Zuhause gespeichert'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Abrufen des Standorts. Bitte Berechtigungen prüfen.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearHomeLocation() async {
    await _locationService.clearHomeLocation();
    await _checkHomeLocation();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zuhause-Standort gelöscht')),
      );
    }
  }

  Future<void> _updateHomeRadius(double radius) async {
    final safeRadius = radius < 100 ? 100.0 : radius;
    await _locationService.setHomeRadius(safeRadius);
    setState(() => _homeRadius = safeRadius);
  }

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
                  'Nicht stören',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Standortbasierte Benachrichtigungen
            SwitchListTile(
              title: const Text('Standortbasierte Benachrichtigungen'),
              subtitle: const Text('Benachrichtigungen nur wenn du zu Hause bist'),
              value: widget.locationBasedNotifications,
              onChanged: widget.onLocationBasedChanged,
            ),
            
            if (widget.locationBasedNotifications) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zuhause-Standort',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        
                        // Standort-Info Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_hasHomeLocation) ...[
                                if (_homeAddress != null) ...[
                                  Row(
                                    children: [
                                      Icon(Icons.location_on, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _homeAddress!,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontSize: 13,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (widget.locationBasedNotifications) ...[
                                  Row(
                                    children: [
                                      Icon(Icons.radio_button_unchecked, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Radius: ${_homeRadius.toInt()} Meter',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Slider(
                                    value: _homeRadius,
                                    min: 100,
                                    max: 2000,
                                    divisions: 19,
                                    label: '${_homeRadius.toInt()}m',
                                    onChanged: (value) {
                                      setState(() => _homeRadius = value.roundToDouble());
                                    },
                                    onChangeEnd: _updateHomeRadius,
                                  ),
                                  Text(
                                    'Bestimmt den Bereich um Ihr Zuhause, in dem Sie Benachrichtigungen erhalten',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ] else ...[
                                Row(
                                  children: [
                                    Icon(Icons.location_off, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Kein Standort gesetzt',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Buttons
                        if (_isLoading)
                          const Center(
                            child: CircularProgressIndicator(),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _setCurrentLocationAsHome,
                                  icon: const Icon(Icons.my_location, size: 18),
                                  label: Text(_hasHomeLocation ? 'Standort neu setzen' : 'Standort setzen'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              if (_hasHomeLocation) ...[
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  onPressed: _clearHomeLocation,
                                  icon: const Icon(Icons.delete, size: 18),
                                  label: const Text('Löschen'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                    
                    // Dynamic info boxes based on status
                    if (widget.locationBasedNotifications) ...[
                      const SizedBox(height: 8),
                      
                      // Smartphone location disabled warning
                      if (!_isLocationServiceEnabled)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Colors.deepOrange.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Smartphone-Standort ist deaktiviert',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Bitte Standort in Smartphone-Einstellungen aktivieren. Ohne Standort werden alle Benachrichtigungen gesendet.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      
                      // Home location not set info
                      else if (!_hasHomeLocation)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Bitte Standort setzen wenn du zuhause bist. Ohne Standort werden alle Benachrichtigungen gesendet.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            ],
            
            const Divider(),
            
            // Ruhezeiten
            SwitchListTile(
              title: const Text('Ruhezeiten'),
              subtitle: const Text('Keine Benachrichtigungen während definierter Zeiten'),
              value: widget.quietTimeEnabled,
              onChanged: widget.onQuietTimeEnabledChanged,
            ),
            
            if (widget.quietTimeEnabled) 
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectTime(context, widget.quietTimeStart, widget.onQuietTimeStartChanged),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Von',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTimeOfDay(widget.quietTimeStart),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.arrow_forward, size: 20),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectTime(context, widget.quietTimeEnd, widget.onQuietTimeEndChanged),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bis',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTimeOfDay(widget.quietTimeEnd),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
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