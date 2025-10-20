import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/planned_device.dart';
import '../models/device_presets.dart';

/// Service for managing user's planned devices
class PlannedDeviceService {
  static const String _storageKey = 'planned_devices';
  static final PlannedDeviceService _instance = PlannedDeviceService._internal();
  factory PlannedDeviceService() => _instance;
  PlannedDeviceService._internal();

  final _uuid = Uuid();

  /// Get all user's devices
  Future<List<PlannedDevice>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);

    if (json == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(json);
      return decoded.map((item) => PlannedDevice.fromJson(item)).toList();
    } catch (e) {
      print('[PlannedDeviceService] Error decoding devices: $e');
      return [];
    }
  }

  /// Get only enabled devices
  Future<List<PlannedDevice>> getEnabledDevices() async {
    final devices = await getDevices();
    return devices.where((d) => d.isEnabled).toList();
  }

  /// Save device list
  Future<void> _saveDevices(List<PlannedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(devices.map((d) => d.toJson()).toList());
    await prefs.setString(_storageKey, json);

    // Note: Window reminders are now managed per-tip in SpartippsPage
    // No need to reschedule here anymore
  }

  /// Add a new device
  Future<void> addDevice(PlannedDevice device) async {
    final devices = await getDevices();
    devices.add(device);
    await _saveDevices(devices);
  }

  /// Save a device (add new or update existing)
  Future<void> saveDevice(PlannedDevice device) async {
    final devices = await getDevices();
    final index = devices.indexWhere((d) => d.id == device.id);

    if (index != -1) {
      // Update existing device
      devices[index] = device;
    } else {
      // Add new device
      devices.add(device);
    }

    await _saveDevices(devices);
  }

  /// Update an existing device
  Future<void> updateDevice(PlannedDevice device) async {
    await saveDevice(device);
  }

  /// Delete a device
  Future<void> deleteDevice(String id) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.id == id);
    await _saveDevices(devices);
  }

  /// Toggle device enabled/disabled
  Future<void> toggleDevice(String id) async {
    final devices = await getDevices();
    final index = devices.indexWhere((d) => d.id == id);

    if (index != -1) {
      devices[index] = devices[index].copyWith(isEnabled: !devices[index].isEnabled);
      await _saveDevices(devices);
    }
  }

  /// Create device from preset profile
  PlannedDevice createFromPreset(
    DevicePreset preset,
    DeviceProfile profile, {
    String? customName,
  }) {
    final name = customName ?? '${preset.name} (${profile.name})';

    return PlannedDevice(
      id: _uuid.v4(),
      name: name,
      category: preset.category,
      presetId: preset.id,
      icon: preset.icon,
      durationHours: profile.durationHours,
      consumptionKwh: profile.consumptionKwh,
      isEnabled: true,
    );
  }

  /// Create custom device (not from preset)
  PlannedDevice createCustomDevice({
    required String name,
    required String category,
    required icon,
    required double durationHours,
    required double consumptionKwh,
  }) {
    return PlannedDevice(
      id: _uuid.v4(),
      name: name,
      category: category,
      icon: icon,
      durationHours: durationHours,
      consumptionKwh: consumptionKwh,
      isEnabled: true,
    );
  }

  /// Clear all devices (for testing)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
