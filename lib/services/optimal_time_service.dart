import '../models/price_data.dart';
import '../models/planned_device.dart';

/// Result of optimal time window search
class OptimalWindow {
  final DateTime startTime;
  final DateTime endTime;
  final List<PriceData> priceSlots;
  final double averagePricePerKwh;
  final double totalCost;

  OptimalWindow({
    required this.startTime,
    required this.endTime,
    required this.priceSlots,
    required this.averagePricePerKwh,
    required this.totalCost,
  });

  /// Duration in hours
  double get durationHours => endTime.difference(startTime).inMinutes / 60.0;

  /// Time until this window starts
  Duration get timeUntilStart {
    final now = DateTime.now();
    if (startTime.isBefore(now)) return Duration.zero;
    return startTime.difference(now);
  }

  /// Is this window currently active?
  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  /// Formatted countdown until start
  String getCountdown() {
    if (isNow) return 'JETZT';

    final duration = timeUntilStart;
    if (duration.inDays > 0) {
      return 'in ${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return 'in ${duration.inHours}h ${duration.inMinutes % 60}min';
    } else if (duration.inMinutes > 0) {
      return 'in ${duration.inMinutes}min';
    } else {
      return 'gleich';
    }
  }
}

/// Savings calculation comparing optimal vs current vs worst
class SavingsCalculation {
  final OptimalWindow optimalWindow;
  final OptimalWindow? currentWindow;  // What if started now
  final OptimalWindow? worstWindow;    // Most expensive possible window
  final double deviceConsumptionKwh;

  SavingsCalculation({
    required this.optimalWindow,
    this.currentWindow,
    this.worstWindow,
    required this.deviceConsumptionKwh,
  });

  /// Cost for optimal window (in cents)
  double get optimalCost => optimalWindow.averagePricePerKwh * deviceConsumptionKwh;

  /// Cost if started now (in cents)
  double? get currentCost => currentWindow != null
      ? currentWindow!.averagePricePerKwh * deviceConsumptionKwh
      : null;

  /// Cost for worst window (in cents)
  double? get worstCost => worstWindow != null
      ? worstWindow!.averagePricePerKwh * deviceConsumptionKwh
      : null;

  /// Savings vs starting now (in cents)
  double? get savingsVsNow => currentCost != null ? currentCost! - optimalCost : null;

  /// Savings vs worst time (in cents)
  double? get savingsVsWorst => worstCost != null ? worstCost! - optimalCost : null;

  /// Savings vs now in percent
  int? get percentVsNow => currentCost != null && currentCost! > 0
      ? ((savingsVsNow! / currentCost!) * 100).round()
      : null;

  /// Savings vs worst in percent
  int? get percentVsWorst => worstCost != null && worstCost! > 0
      ? ((savingsVsWorst! / worstCost!) * 100).round()
      : null;

  /// Format cost in cents, automatically converting to Euro if >= 100 cents
  String formatCost(double cents) {
    if (cents >= 100) {
      return '${(cents / 100).toStringAsFixed(2)} €';
    } else {
      return '${cents.toStringAsFixed(1)} ct';
    }
  }

  /// Format optimal cost
  String get formattedOptimalCost => formatCost(optimalCost);

  /// Format current cost
  String? get formattedCurrentCost => currentCost != null ? formatCost(currentCost!) : null;

  /// Format worst cost
  String? get formattedWorstCost => worstCost != null ? formatCost(worstCost!) : null;

  /// Format savings vs now
  String? get formattedSavingsVsNow => savingsVsNow != null ? formatCost(savingsVsNow!) : null;

  /// Format savings vs worst
  String? get formattedSavingsVsWorst => savingsVsWorst != null ? formatCost(savingsVsWorst!) : null;
}

/// Service to find optimal time windows for device operation
class OptimalTimeService {
  /// Find the cheapest consecutive time window for a device
  ///
  /// Algorithm: Sliding Window to find minimum cost window
  /// Complexity: O(n) where n = number of price slots
  OptimalWindow? findOptimalWindow(
    List<PriceData> prices,
    PlannedDevice device, {
    DateTime? searchStart,
    DateTime? searchEnd,
  }) {
    if (prices.isEmpty) {
      print('[OptimalTime] No prices available');
      return null;
    }

    final now = DateTime.now();
    final requiredSlots = device.durationHours.ceil();

    print('[OptimalTime] Finding optimal window for ${device.name}:');
    print('  - Required slots: $requiredSlots hours');
    print('  - noStartBefore: ${device.noStartBefore}');
    print('  - finishBy: ${device.finishBy}');
    print('  - Search window: ${searchStart?.toIso8601String() ?? "none"} to ${searchEnd?.toIso8601String() ?? "none"}');
    print('  - Current time: ${now.toIso8601String()}');
    print('  - Total prices before filtering: ${prices.length}');
    if (prices.isNotEmpty) {
      print('  - Price data range: ${prices.first.startTime.toIso8601String()} to ${prices.last.startTime.toIso8601String()}');
    }

    // Filter prices: include current hour + future slots within search window
    final availablePrices = prices.where((p) {
      // Include slots that are still running or in the future
      // Only exclude completely past slots
      if (p.endTime.isBefore(now)) return false;

      // Must respect search window
      if (searchStart != null && p.startTime.isBefore(searchStart)) return false;
      if (searchEnd != null && p.startTime.isAfter(searchEnd)) return false;

      return true;
    }).toList();

    print('  - Available price slots: ${availablePrices.length}');
    if (availablePrices.length < requiredSlots) {
      print('  - NOT ENOUGH SLOTS (need $requiredSlots, have ${availablePrices.length})');
      return null;
    }

    if (availablePrices.isNotEmpty) {
      print('  - First slot: ${availablePrices.first.startTime.toIso8601String()}');
      print('  - Last slot: ${availablePrices.last.startTime.toIso8601String()}');
    }

    // Sort by start time (should already be sorted, but ensure it)
    availablePrices.sort((a, b) => a.startTime.compareTo(b.startTime));

    double minCost = double.infinity;
    int bestStartIndex = -1;

    // Sliding window to find cheapest consecutive window
    int consecutiveCount = 0;
    int constraintFailedCount = 0;

    for (int i = 0; i <= availablePrices.length - requiredSlots; i++) {
      final window = availablePrices.sublist(i, i + requiredSlots);

      // Check if window is consecutive (no gaps)
      bool isConsecutive = true;
      for (int j = 0; j < window.length - 1; j++) {
        if (window[j].endTime != window[j + 1].startTime) {
          isConsecutive = false;
          break;
        }
      }
      if (!isConsecutive) continue;

      consecutiveCount++;

      // Check device time constraints
      final windowStart = window.first.startTime;
      if (!device.isTimeAllowed(windowStart)) {
        print('  - Window ${windowStart.hour}:00 - ${window.last.endTime.hour}:00 REJECTED by constraints');
        constraintFailedCount++;
        continue;
      }

      // Calculate total cost for this window
      final totalPrice = window.fold<double>(0, (sum, p) => sum + p.price);

      if (totalPrice < minCost) {
        minCost = totalPrice;
        bestStartIndex = i;
        print('  - Window ${windowStart.hour}:00 - ${window.last.endTime.hour}:00 is new best (cost: ${totalPrice.toStringAsFixed(2)})');
      }
    }

    print('  - Consecutive windows found: $consecutiveCount');
    print('  - Windows rejected by constraints: $constraintFailedCount');

    if (bestStartIndex == -1) {
      print('  - NO OPTIMAL WINDOW FOUND');
      return null;
    }

    final optimalSlots = availablePrices.sublist(bestStartIndex, bestStartIndex + requiredSlots);
    final avgPrice = minCost / requiredSlots;

    return OptimalWindow(
      startTime: optimalSlots.first.startTime,
      endTime: optimalSlots.last.endTime,
      priceSlots: optimalSlots,
      averagePricePerKwh: avgPrice,
      totalCost: minCost,
    );
  }

  /// Find the most expensive window (for savings comparison)
  OptimalWindow? findWorstWindow(
    List<PriceData> prices,
    PlannedDevice device, {
    DateTime? searchStart,
    DateTime? searchEnd,
  }) {
    if (prices.isEmpty) return null;

    final now = DateTime.now();
    final requiredSlots = device.durationHours.ceil();

    final availablePrices = prices.where((p) {
      // Include slots that are still running or in the future
      if (p.endTime.isBefore(now)) return false;
      if (searchStart != null && p.startTime.isBefore(searchStart)) return false;
      if (searchEnd != null && p.startTime.isAfter(searchEnd)) return false;
      return true;
    }).toList();

    if (availablePrices.length < requiredSlots) return null;

    availablePrices.sort((a, b) => a.startTime.compareTo(b.startTime));

    double maxCost = double.negativeInfinity;
    int worstStartIndex = -1;

    for (int i = 0; i <= availablePrices.length - requiredSlots; i++) {
      final window = availablePrices.sublist(i, i + requiredSlots);

      bool isConsecutive = true;
      for (int j = 0; j < window.length - 1; j++) {
        if (window[j].endTime != window[j + 1].startTime) {
          isConsecutive = false;
          break;
        }
      }
      if (!isConsecutive) continue;

      final totalPrice = window.fold<double>(0, (sum, p) => sum + p.price);

      if (totalPrice > maxCost) {
        maxCost = totalPrice;
        worstStartIndex = i;
      }
    }

    if (worstStartIndex == -1) return null;

    final worstSlots = availablePrices.sublist(worstStartIndex, worstStartIndex + requiredSlots);
    final avgPrice = maxCost / requiredSlots;

    return OptimalWindow(
      startTime: worstSlots.first.startTime,
      endTime: worstSlots.last.endTime,
      priceSlots: worstSlots,
      averagePricePerKwh: avgPrice,
      totalCost: maxCost,
    );
  }

  /// Find window if started now (for comparison)
  OptimalWindow? findCurrentWindow(
    List<PriceData> prices,
    PlannedDevice device,
  ) {
    if (prices.isEmpty) return null;

    final now = DateTime.now();
    final requiredSlots = device.durationHours.ceil();

    // Find current hour slot
    final currentSlots = prices.where((p) =>
      p.startTime.isBefore(now) && p.endTime.isAfter(now)
    ).toList();

    if (currentSlots.isEmpty) return null;
    final currentSlot = currentSlots.first;

    // Get consecutive slots starting from current
    final currentIndex = prices.indexOf(currentSlot);
    if (currentIndex == -1 || currentIndex + requiredSlots > prices.length) {
      return null;
    }

    final window = prices.sublist(currentIndex, currentIndex + requiredSlots);

    // Check if consecutive
    for (int j = 0; j < window.length - 1; j++) {
      if (window[j].endTime != window[j + 1].startTime) {
        return null;
      }
    }

    final totalPrice = window.fold<double>(0, (sum, p) => sum + p.price);
    final avgPrice = totalPrice / requiredSlots;

    return OptimalWindow(
      startTime: window.first.startTime,
      endTime: window.last.endTime,
      priceSlots: window,
      averagePricePerKwh: avgPrice,
      totalCost: totalPrice,
    );
  }

  /// Calculate savings for optimal window
  SavingsCalculation calculateSavings(
    List<PriceData> prices,
    PlannedDevice device,
    OptimalWindow optimalWindow, {
    DateTime? searchStart,
    DateTime? searchEnd,
  }) {
    final currentWindow = findCurrentWindow(prices, device);
    final worstWindow = findWorstWindow(
      prices,
      device,
      searchStart: searchStart,
      searchEnd: searchEnd,
    );

    return SavingsCalculation(
      optimalWindow: optimalWindow,
      currentWindow: currentWindow,
      worstWindow: worstWindow,
      deviceConsumptionKwh: device.consumptionKwh,
    );
  }

  /// Get smart search window (today + tomorrow after 17:00)
  (DateTime start, DateTime end) getSearchWindow() {
    final now = DateTime.now();

    if (now.hour >= 17) {
      // After 17:00: Search today + tomorrow
      return (
        now,
        DateTime(now.year, now.month, now.day + 1, 23, 59),
      );
    } else {
      // Before 17:00: Only search today
      return (
        now,
        DateTime(now.year, now.month, now.day, 23, 59),
      );
    }
  }
}
