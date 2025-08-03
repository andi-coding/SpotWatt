import 'package:flutter/material.dart';
import '../models/smart_device.dart';
import '../models/shelly_device.dart';
import '../services/shelly_service.dart';
import '../widgets/device_card.dart';
import '../widgets/shelly_device_card.dart';
import 'settings_page.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({Key? key}) : super(key: key);

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<SmartDevice> devices = [];
  List<ShellyDevice> shellyDevices = [];
  bool isLoadingShelly = false;
  final shellyService = ShellyService();

  @override
  void initState() {
    super.initState();
    loadDevices();
    _loadShellyDevices();
  }

  void loadDevices() {
    setState(() {
      devices = [
        SmartDevice(
          id: '1',
          name: 'Waschmaschine',
          type: DeviceType.washer,
          shellyId: '',
          isAutomated: true,
          targetPrice: 15.0,
        ),
        SmartDevice(
          id: '2',
          name: 'Geschirrspüler',
          type: DeviceType.dishwasher,
          shellyId: '',
          isAutomated: false,
          targetPrice: 12.0,
        ),
      ];
    });
  }

  Future<void> _loadShellyDevices() async {
    setState(() => isLoadingShelly = true);
    
    if (await shellyService.loadCredentials()) {
      try {
        final devices = await shellyService.getDevices();
        setState(() {
          shellyDevices = devices;
          isLoadingShelly = false;
        });
      } catch (e) {
        setState(() => isLoadingShelly = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Laden der Shelly-Geräte: $e')),
          );
        }
      }
    } else {
      setState(() => isLoadingShelly = false);
    }
  }

  void _showDeviceSettings(SmartDevice device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Shelly ID',
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: device.shellyId),
              ),
              const SizedBox(height: 16),
              Text('Zielpreis: ${device.targetPrice.toStringAsFixed(2)} ct/kWh'),
              Slider(
                value: device.targetPrice,
                min: 0,
                max: 50,
                divisions: 50,
                label: device.targetPrice.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() {
                    device.targetPrice = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addDevice() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neues Gerät hinzufügen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Gerätename',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Shelly ID',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Geräte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShellyDevices,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Automatisierte Geräte',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...devices.map((device) => DeviceCard(
            device: device,
            onTap: () => _showDeviceSettings(device),
            onToggle: (value) {
              setState(() {
                device.isAutomated = value;
              });
            },
          )).toList(),
          
          const SizedBox(height: 24),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Shelly Geräte',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (isLoadingShelly)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          
          if (shellyDevices.isEmpty && !isLoadingShelly)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.power_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('Keine Shelly-Geräte gefunden'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsPage(),
                          ),
                        );
                      },
                      child: const Text('Mit Shelly Cloud verbinden'),
                    ),
                  ],
                ),
              ),
            ),
          
          ...shellyDevices.map((device) => ShellyDeviceCard(
            device: device,
            shellyService: shellyService,
            onToggle: (value) async {
              setState(() {
                device.isOn = value;
              });
              
              final success = await shellyService.toggleDevice(device.id, value);
              if (!success && mounted) {
                setState(() {
                  device.isOn = !value;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fehler beim Schalten des Geräts')),
                );
              }
            },
          )).toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDevice,
        child: const Icon(Icons.add),
      ),
    );
  }
}