import 'package:flutter/material.dart';

enum DeviceType { washer, dishwasher, dryer, charger, heater, other }

class SmartDevice {
  final String id;
  final String name;
  final DeviceType type;
  final String shellyId;
  bool isAutomated;
  double targetPrice;

  SmartDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.shellyId,
    required this.isAutomated,
    required this.targetPrice,
  });

  IconData getIcon() {
    switch (type) {
      case DeviceType.washer:
        return Icons.local_laundry_service;
      case DeviceType.dishwasher:
        return Icons.kitchen;
      case DeviceType.dryer:
        return Icons.dry_cleaning;
      case DeviceType.charger:
        return Icons.ev_station;
      case DeviceType.heater:
        return Icons.thermostat;
      default:
        return Icons.power;
    }
  }
}