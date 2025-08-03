import 'package:flutter/material.dart';
import '../models/smart_device.dart';

class DeviceCard extends StatelessWidget {
  final SmartDevice device;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const DeviceCard({
    Key? key,
    required this.device,
    required this.onTap,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: device.isAutomated ? Colors.green : Colors.grey,
          child: Icon(
            device.getIcon(),
            color: Colors.white,
          ),
        ),
        title: Text(device.name),
        subtitle: Text(
          device.isAutomated 
            ? 'Automatisch bei < ${device.targetPrice.toStringAsFixed(2)} ct/kWh'
            : 'Manuell',
        ),
        trailing: Switch(
          value: device.isAutomated,
          onChanged: onToggle,
        ),
        onTap: onTap,
      ),
    );
  }
}