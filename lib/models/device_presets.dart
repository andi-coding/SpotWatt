import 'package:flutter/material.dart';
import 'planned_device.dart';

/// Library of preconfigured device presets
class DevicePresets {
  static final List<DevicePreset> all = [
    washingMachine,
    dishwasher,
    dryer,
    evCharger,
    waterBoiler,
  ];

  // Washing Machine
  static final washingMachine = DevicePreset(
    id: 'washing_machine',
    name: 'Waschmaschine',
    category: 'washing_machine',
    icon: Icons.local_laundry_service,
    profiles: [
      DeviceProfile(
        name: 'Eco 30°',
        durationHours: 2.5,
        consumptionKwh: 0.6,
      ),
      DeviceProfile(
        name: 'Normal 40°',
        durationHours: 2.0,
        consumptionKwh: 0.9,
      ),
      DeviceProfile(
        name: 'Intensiv 60°',
        durationHours: 3.0,
        consumptionKwh: 1.5,
      ),
    ],
  );

  // Dishwasher
  static final dishwasher = DevicePreset(
    id: 'dishwasher',
    name: 'Geschirrspüler',
    category: 'dishwasher',
    icon: Icons.kitchen,
    profiles: [
      DeviceProfile(
        name: 'Eco',
        durationHours: 3.5,
        consumptionKwh: 0.8,
      ),
      DeviceProfile(
        name: 'Normal',
        durationHours: 2.0,
        consumptionKwh: 1.1,
      ),
      DeviceProfile(
        name: 'Schnell',
        durationHours: 1.0,
        consumptionKwh: 1.3,
      ),
    ],
  );

  // Dryer
  static final dryer = DevicePreset(
    id: 'dryer',
    name: 'Wäschetrockner',
    category: 'dryer',
    icon: Icons.dry_cleaning,
    profiles: [
      DeviceProfile(
        name: 'Schonend',
        durationHours: 2.5,
        consumptionKwh: 1.5,
      ),
      DeviceProfile(
        name: 'Normal',
        durationHours: 2.0,
        consumptionKwh: 2.0,
      ),
      DeviceProfile(
        name: 'Intensiv',
        durationHours: 1.5,
        consumptionKwh: 2.5,
      ),
    ],
  );

  // EV Charger - Combined
  static final evCharger = DevicePreset(
    id: 'ev_charger',
    name: 'E-Auto',
    category: 'ev_charger',
    icon: Icons.ev_station,
    profiles: [
      // Schuko / Haushaltssteckdose (2.3 kW)
      DeviceProfile(
        name: 'Schuko 2.3kW (20% → 50%)',
        durationHours: 6,
        consumptionKwh: 13.8,
      ),
      DeviceProfile(
        name: 'Schuko 2.3kW (20% → 80%)',
        durationHours: 12,
        consumptionKwh: 27.6,
      ),
      DeviceProfile(
        name: 'Schuko 2.3kW (Nacht 8h)',
        durationHours: 8,
        consumptionKwh: 18.4,
      ),
      // 11 kW Wallbox
      DeviceProfile(
        name: 'Wallbox 11kW (20% → 50%)',
        durationHours: 1.5,
        consumptionKwh: 13.8,
      ),
      DeviceProfile(
        name: 'Wallbox 11kW (20% → 80%)',
        durationHours: 3,
        consumptionKwh: 27.6,
      ),
      DeviceProfile(
        name: 'Wallbox 11kW (20% → 100%)',
        durationHours: 4,
        consumptionKwh: 36.8,
      ),
      // 22 kW Wallbox
      DeviceProfile(
        name: 'Wallbox 22kW (20% → 50%)',
        durationHours: 1,
        consumptionKwh: 13.8,
      ),
      DeviceProfile(
        name: 'Wallbox 22kW (20% → 80%)',
        durationHours: 1.5,
        consumptionKwh: 27.6,
      ),
      DeviceProfile(
        name: 'Wallbox 22kW (20% → 100%)',
        durationHours: 2,
        consumptionKwh: 36.8,
      ),
    ],
  );

  // Water Boiler - Combined
  static final waterBoiler = DevicePreset(
    id: 'water_boiler',
    name: 'Warmwasser-Boiler',
    category: 'water_heater',
    icon: Icons.water_drop,
    profiles: [
      DeviceProfile(
        name: '80L (20° → 60°)',
        durationHours: 2,
        consumptionKwh: 2.5,
      ),
      DeviceProfile(
        name: '120L (20° → 60°)',
        durationHours: 3,
        consumptionKwh: 3.5,
      ),
      DeviceProfile(
        name: '200L (20° → 60°)',
        durationHours: 4,
        consumptionKwh: 5.0,
      ),
    ],
  );

  // Pool Pump
  static final poolPump = DevicePreset(
    id: 'pool_pump',
    name: 'Poolpumpe',
    category: 'pool_pump',
    icon: Icons.pool,
    profiles: [
      DeviceProfile(
        name: 'Standard (6h Laufzeit)',
        durationHours: 6,
        consumptionKwh: 7.2, // 1.2 kW continuous
      ),
      DeviceProfile(
        name: 'Kurz (4h Laufzeit)',
        durationHours: 4,
        consumptionKwh: 4.8,
      ),
      DeviceProfile(
        name: 'Lang (8h Laufzeit)',
        durationHours: 8,
        consumptionKwh: 9.6,
      ),
    ],
  );

  /// Get preset by ID
  static DevicePreset? getById(String id) {
    try {
      return all.firstWhere((preset) => preset.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get all presets in a category
  static List<DevicePreset> getByCategory(String category) {
    return all.where((preset) => preset.category == category).toList();
  }
}
