import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/price_data.dart';
import '../services/settings_cache.dart';

class PriceUtils {
  /// Calculate quartiles from a list of prices
  static Map<String, double> calculateQuartiles(List<PriceData> prices) {
    if (prices.isEmpty) return {'q1': 0, 'q2': 0, 'q3': 0};
    
    final sortedPrices = prices.map((p) => p.price).toList()..sort();
    final length = sortedPrices.length;
    
    final q1Index = (length * 0.25).floor();
    final q2Index = (length * 0.5).floor();
    final q3Index = (length * 0.75).floor();
    
    return {
      'q1': sortedPrices[q1Index],
      'q2': sortedPrices[q2Index],
      'q3': sortedPrices[q3Index],
    };
  }

  /// Median-based color calculation with symmetric ranges around median
  static Color getPriceColorMedian(double price, List<PriceData> prices, [Color? lastColor]) {
    if (prices.isEmpty) return Colors.green;

    // Get settings from cache
    final settings = SettingsCache();
    final fullCostMode = settings.fullCostMode;

    // Calculate median from original prices
    final sortedPrices = prices.map((p) => p.price).toList()..sort();
    final length = sortedPrices.length;
    final medianIndex = (length / 2).floor();
    double median = sortedPrices[medianIndex];

    // If in full cost mode, subtract fees from median and price for comparison
    double adjustedMedian = median;
    double adjustedPrice = price;

    if (fullCostMode) {
      final taxRate = (settings.priceMarket == 'AT') ? 1.20 : 1.19;

      // Helper function to extract spot price (NETTO) from full cost (BRUTTO)
      //
      // Forward formula: fullCost = spotNetto × taxRate + (|spotNetto| × percentage + fixedFee) + networkCostsBrutto
      // Reverse formula requires case distinction due to absolute value
      double extractSpotPrice(double fullCost) {
        final percentage = settings.energyProviderPercentage / 100; // Convert to decimal
        final fixedFeeBrutto = settings.energyProviderFixedFee;

        // Network costs: convert to BRUTTO if user entered NETTO
        final networkCostsBrutto = settings.includeTax
            ? settings.networkCosts
            : settings.networkCosts * taxRate;

        // Common numerator for both cases
        final numerator = fullCost - fixedFeeBrutto - networkCostsBrutto;

        // Case A: spotNetto ≥ 0
        // fullCost = spotNetto × (taxRate + percentage) + fixedFee + networkCostsBrutto
        // → spotNetto = (fullCost - fixedFee - networkCostsBrutto) / (taxRate + percentage)
        final denominatorPositive = taxRate + percentage;
        final spotPositive = numerator / denominatorPositive;

        // Case B: spotNetto < 0
        // fullCost = spotNetto × (taxRate - percentage) + fixedFee + networkCostsBrutto
        // → spotNetto = (fullCost - fixedFee - networkCostsBrutto) / (taxRate - percentage)
        final denominatorNegative = taxRate - percentage;
        final spotNegative = denominatorNegative != 0 ? numerator / denominatorNegative : 0.0;

        // Return the case that is self-consistent (sign matches assumption)
        if (spotPositive >= 0) {
          return spotPositive; // Case A is valid
        } else if (spotNegative < 0) {
          return spotNegative; // Case B is valid
        } else {
          // Fallback: assume positive (most common case)
          return spotPositive;
        }
      }

      // Extract spot prices for comparison
      adjustedMedian = extractSpotPrice(median);
      adjustedPrice = extractSpotPrice(price);
    }

    // Special handling for very low median values
    if (adjustedMedian.abs() <= 1.5) {
      if (adjustedPrice < adjustedMedian) return Colors.green;  // Everything below median is green
      if (adjustedPrice < adjustedMedian + 2.0) return Colors.orange;
      return Colors.red;
    }

    // Normal calculation with asymmetric minimum range
    final range15 = adjustedMedian * 0.15;
    final greenThreshold = adjustedMedian - range15;  // Normal 15% downwards

    // Upwards: minimum 1ct range to avoid too sensitive coloring
    final upwardRange = range15 > 1.0 ? range15 : 1.0;
    final orangeThreshold = adjustedMedian + upwardRange;

    // Color logic based on adjusted values
    if (adjustedPrice < greenThreshold) return Colors.green;      // < Median - 15%
    if (adjustedPrice < orangeThreshold) return Colors.orange;    // Median ± 15%
    return Colors.red;                                    // > Median + 15%
  }

  @deprecated
  static Color getPriceColor(double price, double minPrice, double maxPrice) {
    final range = maxPrice - minPrice;
    if (range == 0) return Colors.green;
    
    final relative = (price - minPrice) / range;
    
    if (relative < 0.33) return Colors.green;
    if (relative < 0.66) return Colors.orange;
    return Colors.red;
  }

  /// Quartile-based icon selection
  static IconData getPriceIconQuartile(double price, List<PriceData> prices) {
    final color = getPriceColorMedian(price, prices);

    if (color == Colors.green) return Icons.lightbulb; // Glühbirne für günstig
    if (color == Colors.orange) return Icons.circle_outlined; // Uhr für mittel (warten)
    return Icons.warning_amber; // Warnung für teuer
  }

  @deprecated
  static IconData getPriceIcon(double price, double minPrice, double maxPrice) {
    final range = maxPrice - minPrice;
    if (range == 0) return Icons.lightbulb;
    
    final relative = (price - minPrice) / range;
    
    if (relative < 0.33) return Icons.lightbulb; // Glühbirne für günstig
    if (relative < 0.66) return Icons.schedule; // Uhr für mittel (warten)
    return Icons.warning_amber; // Warnung für teuer
  }

  static String formatPrice(double price) {
    // Fix for -0.00 display issue: if the absolute value rounds to 0.00, show 0.00
    final rounded = price.toStringAsFixed(2);
    if (rounded == '-0.00') {
      return '0.00 ct/kWh';
    }
    return '$rounded ct/kWh';
  }

  static String formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  static PriceData? getCurrentPrice(List<PriceData> prices) {
    final now = DateTime.now();
    try {
      return prices.firstWhere(
        (price) => price.startTime.isBefore(now) && price.endTime.isAfter(now),
      );
    } catch (e) {
      return null;
    }
  }

  static List<PriceData> getTodayPrices(List<PriceData> prices) {
    final now = DateTime.now();
    return prices.where((price) => 
      price.startTime.day == now.day && 
      price.startTime.month == now.month &&
      price.startTime.year == now.year
    ).toList();
  }
  
  /// Get ALL prices for today (00:00 - 23:59), not just remaining hours
  /// Used for calculating daily min/max that stays constant throughout the day
  static List<PriceData> getFullDayPrices(List<PriceData> prices, DateTime targetDay) {
    return prices.where((price) => 
      price.startTime.day == targetDay.day && 
      price.startTime.month == targetDay.month &&
      price.startTime.year == targetDay.year
    ).toList();
  }
  
  /// Get tomorrow's prices
  static List<PriceData> getTomorrowPrices(List<PriceData> prices) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return prices.where((price) => 
      price.startTime.day == tomorrow.day && 
      price.startTime.month == tomorrow.month &&
      price.startTime.year == tomorrow.year
    ).toList();
  }
}