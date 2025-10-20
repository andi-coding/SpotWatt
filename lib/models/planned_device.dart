import 'package:flutter/material.dart';

/// Represents a device that the user wants to run at optimal times
/// This is for manual planning, NOT for smart home automation
class PlannedDevice {
  final String id;
  final String name;
  final String category; // 'washing_machine', 'dishwasher', 'ev', 'boiler', etc.
  final String presetId; // Link to DevicePreset (if created from preset)
  final IconData icon;
  final double durationHours;
  final double consumptionKwh;
  final bool isEnabled;

  // Optional time constraints (null = no constraint for max savings)
  final TimeOfDay? noStartBefore;  // e.g., "Don't start before 06:00"
  final DateTime? finishBy;        // e.g., "Must be finished by 18:00 today"

  PlannedDevice({
    required this.id,
    required this.name,
    required this.category,
    this.presetId = '',
    required this.icon,
    required this.durationHours,
    required this.consumptionKwh,
    this.isEnabled = true,
    this.noStartBefore,
    this.finishBy,
  });

  /// Check if a given start time violates any constraints
  /// Constraints define a daily repeating time window (e.g., 18:00-22:00 or 18:00-06:00 overnight)
  bool isTimeAllowed(DateTime startTime) {
    final endTime = startTime.add(Duration(hours: durationHours.ceil()));

    // If both constraints are set, we have a time window (e.g., 06:00-18:00 or 22:00-06:00)
    // We need to check if the device window fits INSIDE this allowed window
    if (noStartBefore != null && finishBy != null) {
      // Use simple TimeOfDay comparison (daily repeating window)
      final startTimeOfDay = TimeOfDay(hour: startTime.hour, minute: startTime.minute);
      final endTimeOfDay = TimeOfDay(hour: endTime.hour, minute: endTime.minute);

      // Check if it's an overnight constraint window (e.g., 22:00-06:00)
      final isOvernightConstraint =
        noStartBefore!.hour > finishBy!.hour ||
        (noStartBefore!.hour == finishBy!.hour && noStartBefore!.minute > finishBy!.minute);

      if (isOvernightConstraint) {
        // Overnight constraint (e.g., 22:00-06:00)
        // Device is allowed if it starts >= 22:00 OR ends <= 06:00
        final startsAfterConstraintStart =
          startTimeOfDay.hour > noStartBefore!.hour ||
          (startTimeOfDay.hour == noStartBefore!.hour && startTimeOfDay.minute >= noStartBefore!.minute);

        final endsBeforeConstraintEnd =
          endTimeOfDay.hour < finishBy!.hour ||
          (endTimeOfDay.hour == finishBy!.hour && endTimeOfDay.minute <= finishBy!.minute);

        if (!startsAfterConstraintStart && !endsBeforeConstraintEnd) {
          print('    [Constraint] Overnight window ${noStartBefore!.hour}:${noStartBefore!.minute.toString().padLeft(2, '0')}-${finishBy!.hour}:${finishBy!.minute.toString().padLeft(2, '0')} violated');
          print('    [Constraint] Device ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}-${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')} doesn\'t fit');
          return false;
        }
      } else {
        // Regular daytime constraint (e.g., 06:00-18:00)
        // Device must start >= 06:00 AND start <= 18:00 (within window)
        // Device must end >= 06:00 AND end <= 18:00 (within window)

        // Check if start time is outside the allowed window
        final startTooEarly =
          startTimeOfDay.hour < noStartBefore!.hour ||
          (startTimeOfDay.hour == noStartBefore!.hour && startTimeOfDay.minute < noStartBefore!.minute);

        final startTooLate =
          startTimeOfDay.hour > finishBy!.hour ||
          (startTimeOfDay.hour == finishBy!.hour && startTimeOfDay.minute > finishBy!.minute);

        // Check if end time is outside the allowed window
        final endTooEarly =
          endTimeOfDay.hour < noStartBefore!.hour ||
          (endTimeOfDay.hour == noStartBefore!.hour && endTimeOfDay.minute < noStartBefore!.minute);

        final endTooLate =
          endTimeOfDay.hour > finishBy!.hour ||
          (endTimeOfDay.hour == finishBy!.hour && endTimeOfDay.minute > finishBy!.minute);

        if (startTooEarly) {
          print('    [Constraint] Start ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')} is before allowed start ${noStartBefore!.hour}:${noStartBefore!.minute.toString().padLeft(2, '0')}');
          return false;
        }

        if (startTooLate) {
          print('    [Constraint] Start ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')} is after allowed end ${finishBy!.hour}:${finishBy!.minute.toString().padLeft(2, '0')}');
          return false;
        }

        if (endTooEarly) {
          print('    [Constraint] End ${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')} is before allowed start ${noStartBefore!.hour}:${noStartBefore!.minute.toString().padLeft(2, '0')}');
          return false;
        }

        if (endTooLate) {
          print('    [Constraint] End ${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')} is after allowed end ${finishBy!.hour}:${finishBy!.minute.toString().padLeft(2, '0')}');
          return false;
        }
      }

      return true;
    }

    // If only noStartBefore is set (no end constraint)
    if (noStartBefore != null) {
      // Build allowed start time for the same day as startTime
      DateTime allowedStart = DateTime(
        startTime.year,
        startTime.month,
        startTime.day,
        noStartBefore!.hour,
        noStartBefore!.minute,
      );

      // Simple check: Is the TIME of day before the allowed time?
      // We compare only the time component, not the date
      final startTimeOfDay = TimeOfDay(hour: startTime.hour, minute: startTime.minute);
      final isBeforeAllowed =
        startTimeOfDay.hour < noStartBefore!.hour ||
        (startTimeOfDay.hour == noStartBefore!.hour && startTimeOfDay.minute < noStartBefore!.minute);

      if (isBeforeAllowed) {
        print('    [Constraint] Start ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')} (${startTime.day}.${startTime.month}.) is before allowed ${noStartBefore!.hour}:${noStartBefore!.minute.toString().padLeft(2, '0')}');
        return false;
      }
    }

    // If only finishBy is set (no start constraint)
    if (finishBy != null) {
      // Build allowedEnd for the same day as endTime (not startTime!)
      // This ensures multi-hour devices check against the correct day
      DateTime allowedEnd = DateTime(
        endTime.year,
        endTime.month,
        endTime.day,
        finishBy!.hour,
        finishBy!.minute,
      );

      // Compare endTime with allowedEnd on the same day
      if (endTime.isAfter(allowedEnd)) {
        print('    [Constraint] End ${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')} (${endTime.day}.${endTime.month}.) is after allowed ${allowedEnd.hour}:${allowedEnd.minute.toString().padLeft(2, '0')} (${allowedEnd.day}.${allowedEnd.month}.)');
        return false;
      }
    }

    return true;
  }
  /// Get formatted constraint description for UI
  String? getConstraintDescription() {
    final constraints = <String>[];

    if (noStartBefore != null) {
      constraints.add('Frühestens ${noStartBefore!.hour}:${noStartBefore!.minute.toString().padLeft(2, '0')}');
    }
    if (finishBy != null) {
      constraints.add('Fertig bis ${finishBy!.hour}:${finishBy!.minute.toString().padLeft(2, '0')}');
    }

    return constraints.isEmpty ? null : constraints.join(' • ');
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'presetId': presetId,
      'icon': icon.codePoint,
      'durationHours': durationHours,
      'consumptionKwh': consumptionKwh,
      'isEnabled': isEnabled,
      'noStartBefore': noStartBefore != null
          ? '${noStartBefore!.hour}:${noStartBefore!.minute}'
          : null,
      'finishBy': finishBy?.toIso8601String(),
    };
  }

  /// Create from JSON
  factory PlannedDevice.fromJson(Map<String, dynamic> json) {
    return PlannedDevice(
      id: json['id'],
      name: json['name'],
      category: json['category'],
      presetId: json['presetId'] ?? '',
      icon: IconData(json['icon'], fontFamily: 'MaterialIcons'),
      durationHours: (json['durationHours'] as num).toDouble(),
      consumptionKwh: (json['consumptionKwh'] as num).toDouble(),
      isEnabled: json['isEnabled'] ?? true,
      noStartBefore: json['noStartBefore'] != null
          ? _parseTimeOfDay(json['noStartBefore'])
          : null,
      finishBy: json['finishBy'] != null
          ? DateTime.parse(json['finishBy'])
          : null,
    );
  }

  static TimeOfDay _parseTimeOfDay(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  /// Copy with updated fields
  PlannedDevice copyWith({
    String? id,
    String? name,
    String? category,
    String? presetId,
    IconData? icon,
    double? durationHours,
    double? consumptionKwh,
    bool? isEnabled,
    TimeOfDay? noStartBefore,
    DateTime? finishBy,
    bool clearNoStartBefore = false,
    bool clearFinishBy = false,
  }) {
    return PlannedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      presetId: presetId ?? this.presetId,
      icon: icon ?? this.icon,
      durationHours: durationHours ?? this.durationHours,
      consumptionKwh: consumptionKwh ?? this.consumptionKwh,
      isEnabled: isEnabled ?? this.isEnabled,
      noStartBefore: clearNoStartBefore ? null : (noStartBefore ?? this.noStartBefore),
      finishBy: clearFinishBy ? null : (finishBy ?? this.finishBy),
    );
  }
}

/// Device preset template (washing machine, dishwasher, etc.)
class DevicePreset {
  final String id;
  final String name;
  final String category;
  final IconData icon;
  final List<DeviceProfile> profiles;

  DevicePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.profiles,
  });
}

/// Specific profile for a device (e.g., "Eco 30°", "Normal 40°")
class DeviceProfile {
  final String name;
  final double durationHours;
  final double consumptionKwh;

  DeviceProfile({
    required this.name,
    required this.durationHours,
    required this.consumptionKwh,
  });
}
