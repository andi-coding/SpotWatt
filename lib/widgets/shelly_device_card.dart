import 'package:flutter/material.dart';
import '../models/shelly_device.dart';
import '../services/shelly_service.dart';

class ShellyDeviceCard extends StatelessWidget {
  final ShellyDevice device;
  final ShellyService shellyService;
  final ValueChanged<bool> onToggle;

  const ShellyDeviceCard({
    Key? key,
    required this.device,
    required this.shellyService,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.isOnline 
            ? (device.isOn ? Colors.green : Colors.grey)
            : Colors.red,
          child: Icon(
            Icons.power,
            color: Colors.white,
          ),
        ),
        title: Text(device.name),
        subtitle: Text(
          device.isOnline 
            ? (device.isOn ? 'Eingeschaltet' : 'Ausgeschaltet')
            : 'Offline',
        ),
        trailing: Switch(
          value: device.isOn,
          onChanged: device.isOnline ? onToggle : null,
        ),
      ),
    );
  }
}