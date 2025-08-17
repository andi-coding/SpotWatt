import 'package:flutter/material.dart';
import '../services/location_service.dart';

class LocationSettings extends StatefulWidget {
  final bool locationBasedNotifications;
  final ValueChanged<bool> onLocationBasedChanged;
  
  const LocationSettings({
    Key? key,
    required this.locationBasedNotifications,
    required this.onLocationBasedChanged,
  }) : super(key: key);

  @override
  State<LocationSettings> createState() => _LocationSettingsState();
}

class _LocationSettingsState extends State<LocationSettings> {
  final LocationService _locationService = LocationService();
  bool _hasHomeLocation = false;
  double _homeRadius = 100.0;
  bool _isLoading = false;
  String? _homeAddress;

  @override
  void initState() {
    super.initState();
    _checkHomeLocation();
  }

  Future<void> _checkHomeLocation() async {
    final homeLocation = await _locationService.getHomeLocation();
    final radius = await _locationService.getHomeRadius();
    String? address;
    
    if (homeLocation != null) {
      address = await _locationService.getAddressFromLocation(
        homeLocation['latitude']!, 
        homeLocation['longitude']!
      );
    }
    
    setState(() {
      _hasHomeLocation = homeLocation != null;
      // Ensure radius is at least 100m (minimum for the slider)
      _homeRadius = radius < 100 ? 100.0 : radius;
      _homeAddress = address;
    });
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
            backgroundColor: Colors.green,
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
        const SnackBar(
          content: Text('Zuhause-Standort gelöscht'),
        ),
      );
    }
  }

  Future<void> _updateHomeRadius(double radius) async {
    // Ensure radius is at least 100m
    final safeRadius = radius < 100 ? 100.0 : radius;
    await _locationService.setHomeRadius(safeRadius);
    setState(() => _homeRadius = safeRadius);
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
                Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Standortbasierte Benachrichtigungen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            SwitchListTile(
              title: const Text('Nur Zuhause benachrichtigen'),
              subtitle: const Text('Benachrichtigungen nur erhalten, wenn Sie sich in der Nähe Ihres Zuhauses befinden'),
              value: widget.locationBasedNotifications && _hasHomeLocation,
              onChanged: _hasHomeLocation ? widget.onLocationBasedChanged : null,
            ),
            
            if (widget.locationBasedNotifications || !_hasHomeLocation) ...[
              const Divider(height: 32),
              
              ListTile(
                title: const Text('Zuhause-Standort'),
                subtitle: Text(_hasHomeLocation 
                  ? _homeAddress != null 
                    ? '$_homeAddress\n(Radius: ${_homeRadius.toInt()}m)'
                    : 'Standort gespeichert (Radius: ${_homeRadius.toInt()}m)' 
                  : 'Kein Standort gesetzt'),
                trailing: _isLoading 
                  ? const CircularProgressIndicator()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hasHomeLocation)
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _clearHomeLocation,
                            tooltip: 'Standort löschen',
                          ),
                        ElevatedButton.icon(
                          onPressed: _setCurrentLocationAsHome,
                          icon: const Icon(Icons.my_location),
                          label: Text(_hasHomeLocation ? 'Aktualisieren' : 'Jetzt setzen'),
                        ),
                      ],
                    ),
              ),
              
              if (_hasHomeLocation && widget.locationBasedNotifications) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Radius: ${_homeRadius.toInt()} Meter'),
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
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Die Standort Einstellung im Smartphone muss aktiviert sein, um zu prüfen, ob Sie sich zuhause befinden.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}