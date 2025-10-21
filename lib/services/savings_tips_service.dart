import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/planned_device.dart';
import '../models/price_data.dart';
import 'optimal_time_service.dart';
import 'planned_device_service.dart';
import 'price_cache_service.dart';

/// Combines OptimalWindow with device info for UI display
class DeviceWindow {
  final PlannedDevice device;
  final OptimalWindow window;
  final double savings; // Savings vs worst time (in cents)
  final double worstCost; // Cost at worst time (in cents)

  DeviceWindow({
    required this.device,
    required this.window,
    required this.savings,
    required this.worstCost,
  });

  /// Is this window currently running?
  bool get isRunning => window.isNow;

  /// Is this window today or tomorrow?
  bool get isToday {
    final now = DateTime.now();
    final start = window.startTime;
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }

  bool get isTomorrow {
    final tomorrow = DateTime.now().add(Duration(days: 1));
    final start = window.startTime;
    return start.year == tomorrow.year &&
        start.month == tomorrow.month &&
        start.day == tomorrow.day;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'deviceId': device.id,
      'startTime': window.startTime.toIso8601String(),
      'endTime': window.endTime.toIso8601String(),
      'averagePricePerKwh': window.averagePricePerKwh,
      'savings': savings,
      'worstCost': worstCost,
    };
  }

  /// Create from JSON (requires device lookup)
  static Future<DeviceWindow?> fromJson(Map<String, dynamic> json, PlannedDeviceService deviceService) async {
    try {
      final devices = await deviceService.getDevices();
      final device = devices.firstWhere((d) => d.id == json['deviceId']);

      final startTime = DateTime.parse(json['startTime']);
      final endTime = DateTime.parse(json['endTime']);
      final avgPrice = (json['averagePricePerKwh'] as num).toDouble();

      return DeviceWindow(
        device: device,
        window: OptimalWindow(
          startTime: startTime,
          endTime: endTime,
          priceSlots: [], // We don't store individual price slots, only aggregated data
          averagePricePerKwh: avgPrice,
          totalCost: avgPrice * device.durationHours,
        ),
        savings: (json['savings'] as num).toDouble(),
        worstCost: (json['worstCost'] as num).toDouble(),
      );
    } catch (e) {
      print('[DeviceWindow] Failed to deserialize: $e');
      return null;
    }
  }

  /// Time until window starts
  Duration get timeUntilStart => window.timeUntilStart;

  /// Format time range (e.g., "15:00 - 17:00")
  String get timeRangeFormatted {
    final startHour = window.startTime.hour.toString().padLeft(2, '0');
    final startMinute = window.startTime.minute.toString().padLeft(2, '0');
    final endHour = window.endTime.hour.toString().padLeft(2, '0');
    final endMinute = window.endTime.minute.toString().padLeft(2, '0');
    return '$startHour:$startMinute - $endHour:$endMinute';
  }

  /// Format date (Today, Tomorrow, or date)
  String get dateFormatted {
    if (isToday) return 'Heute';

    final tomorrow = DateTime.now().add(Duration(days: 1));
    final start = window.startTime;
    if (start.year == tomorrow.year &&
        start.month == tomorrow.month &&
        start.day == tomorrow.day) {
      return 'Morgen';
    }

    return '${start.day}.${start.month}.';
  }
}

/// UI-ready savings tip
class SavingsTip {
  final DeviceWindow deviceWindow;
  final bool confirmed;
  final DateTime? confirmedAt;

  SavingsTip({
    required this.deviceWindow,
    this.confirmed = false,
    this.confirmedAt,
  });

  /// Title for display (e.g., "E-Auto jetzt nutzen?")
  String get title {
    final name = deviceWindow.device.name;

    if (deviceWindow.isRunning) {
      return '$name jetzt nutzen?';
    }

    final timeUntil = deviceWindow.timeUntilStart;
    if (timeUntil.inHours == 0 && timeUntil.inMinutes > 0) {
      return '$name in ${timeUntil.inMinutes} min';
    } else if (timeUntil.inHours < 2) {
      final hours = timeUntil.inHours;
      final minutes = timeUntil.inMinutes % 60;
      return '$name in ${hours}h ${minutes}min';
    }

    return name;
  }

  /// Subtitle for display (e.g., "⚡ Jetzt bis 17:00 Uhr" or "Heute, 15:00 - 17:00 Uhr")
  String get subtitle {
    if (deviceWindow.isRunning) {
      final endHour = deviceWindow.window.endTime.hour.toString().padLeft(2, '0');
      final endMinute = deviceWindow.window.endTime.minute.toString().padLeft(2, '0');
      return '⚡ Jetzt bis $endHour:$endMinute Uhr';
    }

    final time = deviceWindow.timeRangeFormatted;
    final date = deviceWindow.dateFormatted;

    if (deviceWindow.isToday) {
      return 'Heute, $time Uhr';
    }

    return '$date, $time Uhr';
  }

  /// Formatted savings (e.g., "0.80€")
  String get savingsFormatted {
    final euros = deviceWindow.savings / 100; // Convert cents to euros
    return '${euros.toStringAsFixed(2)}€';
  }

  /// Formatted optimal cost (e.g., "0.70€")
  String get optimalCostFormatted {
    final optimalCost = deviceWindow.worstCost - deviceWindow.savings;
    final euros = optimalCost / 100; // Convert cents to euros
    return '${euros.toStringAsFixed(2)}€';
  }

  /// Formatted worst cost (e.g., "1.50€")
  String get worstCostFormatted {
    final euros = deviceWindow.worstCost / 100; // Convert cents to euros
    return '${euros.toStringAsFixed(2)}€';
  }

  /// Check if tip is still relevant (not expired)
  bool get isRelevant {
    return DateTime.now().isBefore(deviceWindow.window.endTime);
  }

  /// Create confirmed copy
  SavingsTip copyWithConfirmed(bool confirmed) {
    return SavingsTip(
      deviceWindow: deviceWindow,
      confirmed: confirmed,
      confirmedAt: confirmed ? DateTime.now() : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceWindow.device.id,
      'startTime': deviceWindow.window.startTime.toIso8601String(),
      'endTime': deviceWindow.window.endTime.toIso8601String(),
      'savings': deviceWindow.savings,
      'confirmed': confirmed,
      'confirmedAt': confirmedAt?.toIso8601String(),
    };
  }
}

/// Monthly savings summary
class MonthlySavings {
  final double totalSavings; // In cents
  final int confirmedCount;
  final DateTime month;

  MonthlySavings({
    required this.totalSavings,
    required this.confirmedCount,
    required this.month,
  });

  String get formattedTotal {
    final euros = totalSavings / 100;
    return '${euros.toStringAsFixed(2)}€';
  }

  Map<String, dynamic> toJson() {
    return {
      'totalSavings': totalSavings,
      'confirmedCount': confirmedCount,
      'month': month.toIso8601String(),
    };
  }

  factory MonthlySavings.fromJson(Map<String, dynamic> json) {
    return MonthlySavings(
      totalSavings: (json['totalSavings'] as num).toDouble(),
      confirmedCount: json['confirmedCount'] as int,
      month: DateTime.parse(json['month']),
    );
  }
}

/// Service for managing savings tips
class SavingsTipsService {
  final OptimalTimeService _optimalTimeService = OptimalTimeService();
  final PlannedDeviceService _deviceService = PlannedDeviceService();
  final PriceCacheService _priceService = PriceCacheService();

  static const String _confirmedTipsKey = 'confirmed_tips';
  static const String _dismissedTipsKey = 'dismissed_tips';
  static const String _monthlySavingsKey = 'monthly_savings';
  static const String _cachedTipsKey = 'cached_savings_tips';
  static const String _cachedTipsTimestampKey = 'cached_tips_timestamp';
  static const String _savingsGoalKey = 'monthly_savings_goal';
  static const String _yearlyStatsKey = 'yearly_savings_stats';

  /// Calculate savings tips for all enabled devices
  /// Uses cached tips if available and valid
  Future<List<SavingsTip>> calculateSavingsTips({bool forceRecalculate = false}) async {
    print('[SavingsTips] Calculating savings tips...');

    // Try to load cached tips first (unless forced to recalculate)
    if (!forceRecalculate) {
      final cachedTips = await _loadCachedTips();
      if (cachedTips != null && cachedTips.isNotEmpty) {
        print('[SavingsTips] Using ${cachedTips.length} cached tips');
        return cachedTips;
      }
    }

    // Get devices and prices
    final devices = await _deviceService.getDevices();
    final enabledDevices = devices.where((d) => d.isEnabled).toList();

    if (enabledDevices.isEmpty) {
      print('[SavingsTips] No enabled devices');
      return [];
    }

    final prices = await _priceService.getPrices();
    if (prices.isEmpty) {
      print('[SavingsTips] No prices available');
      return [];
    }

    print('[SavingsTips] Found ${enabledDevices.length} enabled devices');

    // Calculate optimal windows for each device
    List<DeviceWindow> deviceWindows = [];

    for (final device in enabledDevices) {
      final (searchStart, searchEnd) = _optimalTimeService.getSearchWindow();

      final optimalWindow = _optimalTimeService.findOptimalWindow(
        prices,
        device,
        searchStart: searchStart,
        searchEnd: searchEnd,
      );

      if (optimalWindow == null) {
        print('[SavingsTips] No optimal window for ${device.name}');
        continue;
      }

      // Calculate savings (optimal vs worst)
      final worstWindow = _optimalTimeService.findWorstWindow(
        prices,
        device,
        searchStart: searchStart,
        searchEnd: searchEnd,
      );

      double savings = 0;
      double worstCost = 0;
      if (worstWindow != null) {
        // Savings = (worst cost - optimal cost) in cents
        worstCost = worstWindow.averagePricePerKwh * device.consumptionKwh;
        final optimalCost = optimalWindow.averagePricePerKwh * device.consumptionKwh;
        savings = worstCost - optimalCost;
      }

      deviceWindows.add(DeviceWindow(
        device: device,
        window: optimalWindow,
        savings: savings,
        worstCost: worstCost,
      ));

      print('[SavingsTips] ${device.name}: ${optimalWindow.startTime.hour}:00-${optimalWindow.endTime.hour}:00, saves ${savings.toStringAsFixed(1)}ct');
    }

    if (deviceWindows.isEmpty) {
      print('[SavingsTips] No valid device windows');
      return [];
    }

    // Filter out expired windows (endTime has passed)
    final now = DateTime.now();
    deviceWindows = deviceWindows.where((dw) => dw.window.endTime.isAfter(now)).toList();

    if (deviceWindows.isEmpty) {
      print('[SavingsTips] No valid device windows after filtering expired ones');
      return [];
    }

    // Sort by priority:
    // 1. Time proximity (nearest window first)
    // 2. If same start time, highest savings
    deviceWindows.sort((a, b) {
      final aStart = a.window.startTime;
      final bStart = b.window.startTime;

      // Compare start times - earlier windows first
      final timeDiff = aStart.compareTo(bStart);
      if (timeDiff != 0) return timeDiff;

      // Same start time -> prioritize by savings
      return b.savings.compareTo(a.savings);
    });

    // Load confirmed and dismissed tips
    final confirmedTips = await _loadConfirmedTips();
    final dismissedTips = await _loadDismissedTips();

    // Convert to SavingsTip with confirmation/dismissed status, filter out dismissed
    final tips = deviceWindows.map((dw) {
      final key = _getTipKey(dw);
      final confirmed = confirmedTips.containsKey(key);
      final confirmedAt = confirmed ? confirmedTips[key] : null;

      return SavingsTip(
        deviceWindow: dw,
        confirmed: confirmed,
        confirmedAt: confirmedAt,
      );
    }).where((tip) {
      // Filter out dismissed tips (user doesn't want to see them)
      final key = _getTipKey(tip.deviceWindow);
      return !dismissedTips.contains(key);
    }).toList();

    print('[SavingsTips] Generated ${tips.length} tips (dismissed tips filtered out)');

    // Cache the calculated tips
    await _cacheTips(deviceWindows);

    return tips;
  }

  /// Recalculate only tomorrow's tips (called when new prices arrive)
  Future<void> recalculateTomorrowTips() async {
    print('[SavingsTips] Recalculating tomorrow tips after new prices...');

    // Load existing cached tips
    final existingWindows = await _loadCachedDeviceWindows();

    // Filter to keep only today's tips that haven't expired yet
    final now = DateTime.now();
    final todayWindows = existingWindows.where((dw) =>
      dw.isToday && dw.window.endTime.isAfter(now)
    ).toList();

    print('[SavingsTips] Keeping ${todayWindows.length} today tips (expired tips filtered out)');

    // Calculate new tips for tomorrow
    final devices = await _deviceService.getDevices();
    final enabledDevices = devices.where((d) => d.isEnabled).toList();

    if (enabledDevices.isEmpty) {
      print('[SavingsTips] No enabled devices - skipping tomorrow calculation');
      return;
    }

    final prices = await _priceService.getPrices();
    if (prices.isEmpty) {
      print('[SavingsTips] No prices available - skipping tomorrow calculation');
      return;
    }

    // Calculate tomorrow's windows
    final tomorrow = DateTime.now().add(Duration(days: 1));
    final tomorrowStart = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 0, 0);
    final tomorrowEnd = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59);

    List<DeviceWindow> tomorrowWindows = [];

    for (final device in enabledDevices) {
      final optimalWindow = _optimalTimeService.findOptimalWindow(
        prices,
        device,
        searchStart: tomorrowStart,
        searchEnd: tomorrowEnd,
      );

      if (optimalWindow == null) {
        print('[SavingsTips] No optimal window for ${device.name} tomorrow');
        continue;
      }

      // Calculate savings
      final worstWindow = _optimalTimeService.findWorstWindow(
        prices,
        device,
        searchStart: tomorrowStart,
        searchEnd: tomorrowEnd,
      );

      double savings = 0;
      double worstCost = 0;
      if (worstWindow != null) {
        worstCost = worstWindow.averagePricePerKwh * device.consumptionKwh;
        final optimalCost = optimalWindow.averagePricePerKwh * device.consumptionKwh;
        savings = worstCost - optimalCost;
      }

      tomorrowWindows.add(DeviceWindow(
        device: device,
        window: optimalWindow,
        savings: savings,
        worstCost: worstCost,
      ));

      print('[SavingsTips] ${device.name} tomorrow: ${optimalWindow.startTime.hour}:00-${optimalWindow.endTime.hour}:00, saves ${savings.toStringAsFixed(1)}ct');
    }

    print('[SavingsTips] Generated ${tomorrowWindows.length} new tomorrow tips');

    // Combine today + tomorrow tips
    final allWindows = [...todayWindows, ...tomorrowWindows];

    // Cache combined tips
    await _cacheTips(allWindows);

    print('[SavingsTips] ✅ Cached ${allWindows.length} total tips (${todayWindows.length} today + ${tomorrowWindows.length} tomorrow)');
  }

  /// Load cached tips
  Future<List<SavingsTip>?> _loadCachedTips() async {
    final deviceWindows = await _loadCachedDeviceWindows();
    if (deviceWindows.isEmpty) return null;

    print('[SavingsTips] Loaded ${deviceWindows.length} device windows from cache');

    // Debug: Print all loaded windows
    for (final dw in deviceWindows) {
      print('[SavingsTips] - ${dw.device.name}: ${dw.dateFormatted} ${dw.timeRangeFormatted}, endTime: ${dw.window.endTime}');
    }

    // Filter out expired windows
    final now = DateTime.now();
    print('[SavingsTips] Current time: $now');

    final validWindows = deviceWindows.where((dw) {
      final isValid = dw.window.endTime.isAfter(now);
      if (!isValid) {
        print('[SavingsTips] ❌ Filtered out expired: ${dw.device.name} (ended at ${dw.window.endTime})');
      }
      return isValid;
    }).toList();

    print('[SavingsTips] After filtering: ${validWindows.length} valid windows remaining');

    // If we filtered out any expired windows, update the cache
    if (validWindows.length < deviceWindows.length) {
      print('[SavingsTips] 🗑️ Removing ${deviceWindows.length - validWindows.length} expired windows from cache');
      await _cacheTips(validWindows);
    }

    // Load confirmed and dismissed tips
    final confirmedTips = await _loadConfirmedTips();
    final dismissedTips = await _loadDismissedTips();

    // Convert to SavingsTip with confirmation status, filter out dismissed
    final validTips = validWindows.map((dw) {
      final key = _getTipKey(dw);
      final confirmed = confirmedTips.containsKey(key);
      final confirmedAt = confirmed ? confirmedTips[key] : null;

      return SavingsTip(
        deviceWindow: dw,
        confirmed: confirmed,
        confirmedAt: confirmedAt,
      );
    }).where((tip) {
      // Filter out dismissed tips
      final key = _getTipKey(tip.deviceWindow);
      return !dismissedTips.contains(key);
    }).toList();

    return validTips;
  }

  /// Load cached device windows (without confirmation status)
  Future<List<DeviceWindow>> _loadCachedDeviceWindows() async {
    final prefs = await SharedPreferences.getInstance();
    // IMPORTANT: Reload from disk to get data written by background isolate or price update
    await prefs.reload();
    final json = prefs.getString(_cachedTipsKey);

    if (json == null) {
      print('[SavingsTips] No cached tips found');
      return [];
    }

    try {
      final List<dynamic> data = jsonDecode(json);
      final windows = <DeviceWindow>[];

      for (final item in data) {
        final window = await DeviceWindow.fromJson(item, _deviceService);
        if (window != null) {
          windows.add(window);
        }
      }

      print('[SavingsTips] Loaded ${windows.length} cached device windows');
      return windows;
    } catch (e) {
      print('[SavingsTips] Failed to load cached tips: $e');
      return [];
    }
  }

  /// Cache tips to SharedPreferences
  Future<void> _cacheTips(List<DeviceWindow> deviceWindows) async {
    final prefs = await SharedPreferences.getInstance();

    final json = jsonEncode(deviceWindows.map((dw) => dw.toJson()).toList());
    await prefs.setString(_cachedTipsKey, json);
    await prefs.setInt(_cachedTipsTimestampKey, DateTime.now().millisecondsSinceEpoch);

    print('[SavingsTips] Cached ${deviceWindows.length} device windows');
  }

  /// Confirm a tip (user activated device)
  Future<void> confirmTip(SavingsTip tip) async {
    final prefs = await SharedPreferences.getInstance();

    // Load existing confirmed tips
    final confirmedTips = await _loadConfirmedTips();

    // Add this tip
    final key = _getTipKey(tip.deviceWindow);
    confirmedTips[key] = DateTime.now();

    // Save
    final json = confirmedTips.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_confirmedTipsKey, jsonEncode(json));

    // Update monthly savings
    await _addToMonthlySavings(tip.deviceWindow.savings);

    print('[SavingsTips] Confirmed tip for ${tip.deviceWindow.device.name}, saved ${tip.savingsFormatted}');
  }

  /// Undo a confirmation (user clicked "Rückgängig")
  Future<void> undoConfirmTip(SavingsTip tip) async {
    final prefs = await SharedPreferences.getInstance();

    // Load existing confirmed tips
    final confirmedTips = await _loadConfirmedTips();

    // Remove this tip
    final key = _getTipKey(tip.deviceWindow);
    confirmedTips.remove(key);

    // Save
    final json = confirmedTips.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_confirmedTipsKey, jsonEncode(json));

    // Subtract from monthly savings
    await _subtractFromMonthlySavings(tip.deviceWindow.savings);

    print('[SavingsTips] Undone tip for ${tip.deviceWindow.device.name}, removed ${tip.savingsFormatted}');
  }

  /// Get monthly savings for current month
  Future<MonthlySavings> getMonthlySavings() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);

    final json = prefs.getString(_monthlySavingsKey);
    if (json == null) {
      return MonthlySavings(
        totalSavings: 0,
        confirmedCount: 0,
        month: currentMonth,
      );
    }

    final data = jsonDecode(json) as Map<String, dynamic>;
    final savings = MonthlySavings.fromJson(data);

    // Check if month changed - if yes, save old month to yearly stats
    if (savings.month.year != currentMonth.year ||
        savings.month.month != currentMonth.month) {

      // Save previous month's savings to yearly stats (if > 0)
      if (savings.totalSavings > 0) {
        final monthKey = '${savings.month.year}-${savings.month.month.toString().padLeft(2, '0')}';
        await _updateYearlyStats(monthKey, savings.totalSavings);
        print('[SavingsTips] 📊 Archived ${savings.formattedTotal} to yearly stats ($monthKey)');
      }

      // Return fresh monthly savings for new month
      return MonthlySavings(
        totalSavings: 0,
        confirmedCount: 0,
        month: currentMonth,
      );
    }

    return savings;
  }

  /// Add to monthly savings
  Future<void> _addToMonthlySavings(double savingsInCents) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getMonthlySavings();

    final updated = MonthlySavings(
      totalSavings: current.totalSavings + savingsInCents,
      confirmedCount: current.confirmedCount + 1,
      month: current.month,
    );

    await prefs.setString(_monthlySavingsKey, jsonEncode(updated.toJson()));
  }

  /// Subtract from monthly savings (undo)
  Future<void> _subtractFromMonthlySavings(double savingsInCents) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getMonthlySavings();

    // Don't go below 0
    final newTotal = (current.totalSavings - savingsInCents).clamp(0.0, double.infinity);
    final newCount = (current.confirmedCount - 1).clamp(0, 999999);

    final updated = MonthlySavings(
      totalSavings: newTotal,
      confirmedCount: newCount,
      month: current.month,
    );

    await prefs.setString(_monthlySavingsKey, jsonEncode(updated.toJson()));
  }

  /// Load confirmed tips from storage
  Future<Map<String, DateTime>> _loadConfirmedTips() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_confirmedTipsKey);

    if (json == null) return {};

    try {
      final Map<String, dynamic> data = jsonDecode(json);
      return data.map((key, value) => MapEntry(key, DateTime.parse(value)));
    } catch (e) {
      print('[SavingsTips] Failed to load confirmed tips: $e');
      return {};
    }
  }

  /// Load dismissed tips from storage
  Future<Set<String>> _loadDismissedTips() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_dismissedTipsKey);

    if (json == null) return {};

    try {
      final List<dynamic> data = jsonDecode(json);
      return data.map((e) => e.toString()).toSet();
    } catch (e) {
      print('[SavingsTips] Failed to load dismissed tips: $e');
      return {};
    }
  }

  /// Dismiss a tip (user doesn't want to see it)
  /// NOTE: This does NOT cancel reminders - user might still want the reminder
  Future<void> dismissTip(SavingsTip tip) async {
    final prefs = await SharedPreferences.getInstance();

    // Load existing dismissed tips
    final dismissedTips = await _loadDismissedTips();

    // Add this tip
    final key = _getTipKey(tip.deviceWindow);
    dismissedTips.add(key);

    // Save
    await prefs.setString(_dismissedTipsKey, jsonEncode(dismissedTips.toList()));

    print('[SavingsTips] Dismissed tip for ${tip.deviceWindow.device.name}');
  }

  /// Undo dismissal (bring back dismissed tip)
  Future<void> undoDismissTip(SavingsTip tip) async {
    final prefs = await SharedPreferences.getInstance();

    // Load existing dismissed tips
    final dismissedTips = await _loadDismissedTips();

    // Remove this tip
    final key = _getTipKey(tip.deviceWindow);
    dismissedTips.remove(key);

    // Save
    await prefs.setString(_dismissedTipsKey, jsonEncode(dismissedTips.toList()));

    print('[SavingsTips] Restored tip for ${tip.deviceWindow.device.name}');
  }

  /// Generate unique key for a tip (for tracking confirmations)
  String _getTipKey(DeviceWindow dw) {
    // Key format: deviceId_YYYYMMDD_HHmm
    final start = dw.window.startTime;
    return '${dw.device.id}_${start.year}${start.month.toString().padLeft(2, '0')}${start.day.toString().padLeft(2, '0')}_${start.hour.toString().padLeft(2, '0')}${start.minute.toString().padLeft(2, '0')}';
  }

  /// Clean up old confirmed and dismissed tips (older than 7 days)
  Future<void> cleanupOldTips() async {
    final prefs = await SharedPreferences.getInstance();
    final confirmedTips = await _loadConfirmedTips();

    final cutoff = DateTime.now().subtract(Duration(days: 7));

    // Remove old confirmed tips
    confirmedTips.removeWhere((key, confirmedAt) => confirmedAt.isBefore(cutoff));

    // Save cleaned confirmed tips
    final confirmedJson = confirmedTips.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_confirmedTipsKey, jsonEncode(confirmedJson));

    // Clear all dismissed tips (they expire daily anyway)
    await prefs.remove(_dismissedTipsKey);

    print('[SavingsTips] Cleaned up old tips');
  }

  /// Smart invalidate: Keeps locked windows (running or starting soon)
  /// and only recalculates tips for other devices
  /// This prevents tips from changing when user adds/edits devices
  Future<void> invalidateCache() async {
    print('[SavingsTips] Smart invalidate cache started');

    final now = DateTime.now();

    // 1. Load existing cached tips
    final existingWindows = await _loadCachedDeviceWindows();

    if (existingWindows.isEmpty) {
      // No existing tips, just clear cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedTipsKey);
      await prefs.remove(_cachedTipsTimestampKey);
      print('[SavingsTips] No existing tips - cache cleared');
      return;
    }

    // 2. Identify "locked" windows (running or starting within 1 hour)
    final lockedWindows = existingWindows.where((dw) {
      final isRunning = dw.window.startTime.isBefore(now) && dw.window.endTime.isAfter(now);
      final startsSoon = dw.window.startTime.isAfter(now) &&
                        dw.window.startTime.difference(now).inMinutes < 60;
      return isRunning || startsSoon;
    }).toList();

    print('[SavingsTips] Found ${lockedWindows.length} locked windows (running or starting < 1h)');
    for (final lw in lockedWindows) {
      print('[SavingsTips]   - Locked: ${lw.device.name} @ ${lw.window.startTime.hour}:${lw.window.startTime.minute.toString().padLeft(2, '0')}');
    }

    // 3. Get current enabled devices
    final devices = await _deviceService.getDevices();
    final enabledDevices = devices.where((d) => d.isEnabled).toList();

    // 4. Filter devices that need recalculation (not locked)
    final lockedDeviceIds = lockedWindows.map((lw) => lw.device.id).toSet();
    final devicesToRecalculate = enabledDevices.where((d) =>
      !lockedDeviceIds.contains(d.id)
    ).toList();

    print('[SavingsTips] Recalculating ${devicesToRecalculate.length} devices (not locked)');

    if (devicesToRecalculate.isEmpty) {
      // All devices are locked, keep existing cache
      print('[SavingsTips] All devices locked - keeping existing cache');
      return;
    }

    // 5. Recalculate tips for non-locked devices
    final prices = await _priceService.getPrices();
    if (prices.isEmpty) {
      print('[SavingsTips] No prices available - keeping locked windows only');
      await _cacheTips(lockedWindows);
      return;
    }

    final (searchStart, searchEnd) = _optimalTimeService.getSearchWindow();
    List<DeviceWindow> newWindows = [];

    for (final device in devicesToRecalculate) {
      final optimalWindow = _optimalTimeService.findOptimalWindow(
        prices,
        device,
        searchStart: searchStart,
        searchEnd: searchEnd,
      );

      if (optimalWindow == null) {
        print('[SavingsTips]   - No optimal window for ${device.name}');
        continue;
      }

      // Calculate savings
      final worstWindow = _optimalTimeService.findWorstWindow(
        prices,
        device,
        searchStart: searchStart,
        searchEnd: searchEnd,
      );

      double savings = 0;
      double worstCost = 0;
      if (worstWindow != null) {
        worstCost = worstWindow.averagePricePerKwh * device.consumptionKwh;
        final optimalCost = optimalWindow.averagePricePerKwh * device.consumptionKwh;
        savings = worstCost - optimalCost;
      }

      newWindows.add(DeviceWindow(
        device: device,
        window: optimalWindow,
        savings: savings,
        worstCost: worstCost,
      ));

      print('[SavingsTips]   - New: ${device.name} @ ${optimalWindow.startTime.hour}:${optimalWindow.startTime.minute.toString().padLeft(2, '0')}');
    }

    // 6. Combine locked + new windows
    final allWindows = [...lockedWindows, ...newWindows];

    // 7. Filter out expired windows
    final validWindows = allWindows.where((dw) => dw.window.endTime.isAfter(now)).toList();

    // 8. Sort by time proximity
    validWindows.sort((a, b) {
      final aStart = a.window.startTime;
      final bStart = b.window.startTime;
      final timeDiff = aStart.compareTo(bStart);
      if (timeDiff != 0) return timeDiff;
      return b.savings.compareTo(a.savings);
    });

    // 9. Cache combined tips
    await _cacheTips(validWindows);

    print('[SavingsTips] ✅ Smart invalidate complete: ${lockedWindows.length} locked + ${newWindows.length} new = ${validWindows.length} total');
  }

  /// Get monthly savings goal (in cents)
  Future<double> getSavingsGoal() async {
    final prefs = await SharedPreferences.getInstance();
    // Default: 5.00€ = 500 cents
    return prefs.getDouble(_savingsGoalKey) ?? 500.0;
  }

  /// Set monthly savings goal (in cents)
  Future<void> setSavingsGoal(double goalInCents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_savingsGoalKey, goalInCents);
    print('[SavingsTips] Savings goal set to ${goalInCents / 100}€');
  }

  /// Get yearly savings statistics
  Future<Map<String, double>> getYearlySavings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_yearlyStatsKey);

    if (json == null) return {};

    try {
      final Map<String, dynamic> data = jsonDecode(json);
      return data.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (e) {
      print('[SavingsTips] Failed to load yearly stats: $e');
      return {};
    }
  }

  /// Update yearly stats when month ends
  Future<void> _updateYearlyStats(String monthKey, double savings) async {
    final prefs = await SharedPreferences.getInstance();
    final yearlyStats = await getYearlySavings();

    yearlyStats[monthKey] = savings;

    await prefs.setString(_yearlyStatsKey, jsonEncode(yearlyStats));
    print('[SavingsTips] Updated yearly stats for $monthKey: ${savings / 100}€');
  }
}
