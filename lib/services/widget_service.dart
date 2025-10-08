import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:spotwatt/services/price_cache_service.dart';
import 'package:spotwatt/utils/price_utils.dart';
import 'package:spotwatt/models/price_data.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class WidgetService {
  static const String androidWidgetName = 'PriceWidgetProvider';
  static const String iosWidgetKind = 'PriceWidget';
  static const MethodChannel _channel = MethodChannel('com.spotwatt.app/widget');
  
  static Future<void> updateWidget() async {
    try {
      final cacheService = PriceCacheService();
      
      // Get current prices using same logic as app (with cache validation)
      final prices = await cacheService.getPrices();
      
      final now = DateTime.now();
      final currentPrice = PriceUtils.getCurrentPrice(prices);
      
      // Get FULL day prices (all 24 hours of today) for min/max calculation
      // This ensures min/max values stay constant throughout the day
      final fullTodayPrices = PriceUtils.getFullDayPrices(prices, now);
      
      if (currentPrice == null || fullTodayPrices.isEmpty) return;
      
      // Calculate min and max for the ENTIRE day (00:00 - 23:59)
      final minPriceData = fullTodayPrices.reduce((a, b) => 
        a.price < b.price ? a : b);
      final maxPriceData = fullTodayPrices.reduce((a, b) => 
        a.price > b.price ? a : b);
      final minPrice = minPriceData.price;
      final maxPrice = maxPriceData.price;
      final minTime = DateFormat('HH:mm').format(minPriceData.startTime);
      final maxTime = DateFormat('HH:mm').format(maxPriceData.startTime);
      
      // Determine price status using median logic (low, medium, high)
      final priceStatus = _getPriceStatusMedian(currentPrice.price, prices);
      
      // Calculate trend for next hours
      final priceTrend = _getPriceTrend(prices, now);
      
      // Format update time
      final updateTime = DateFormat('HH:mm').format(now);

      // Get time slot end (next hour)
      final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
      final timeSlot = DateFormat('HH:mm').format(nextHour);

      // Get theme setting for widget
      final themeMode = await _getThemeModeSetting();
      
      // Save data to widget
      await HomeWidget.saveWidgetData<String>('current_price', 
        '${currentPrice.price.toStringAsFixed(2)} ct/kWh');
      await HomeWidget.saveWidgetData<String>('min_price', 
        minPrice.toStringAsFixed(2));
      await HomeWidget.saveWidgetData<String>('max_price', 
        maxPrice.toStringAsFixed(2));
      await HomeWidget.saveWidgetData<String>('min_time', minTime);
      await HomeWidget.saveWidgetData<String>('max_time', maxTime);
      print('Widget Update: Min at $minTime, Max at $maxTime');
      await HomeWidget.saveWidgetData<String>('price_status', priceStatus);
      await HomeWidget.saveWidgetData<String>('price_trend', priceTrend);
      await HomeWidget.saveWidgetData<String>('last_update', updateTime);
      await HomeWidget.saveWidgetData<String>('time_slot', timeSlot);
      await HomeWidget.saveWidgetData<String>('theme_mode', themeMode);
      
      // Update the widget
      print('[WidgetService] Calling HomeWidget.updateWidget...');
      final updateResult = await HomeWidget.updateWidget(
        name: androidWidgetName,
        iOSName: iosWidgetKind,
      );
      print('[WidgetService] HomeWidget.updateWidget result: $updateResult');
    } catch (e, stackTrace) {
      print('[WidgetService] Error updating widget: $e');
      print('[WidgetService] StackTrace: $stackTrace');
    }
  }
  
  static String _getPriceStatusMedian(double current, List<PriceData> prices) {
    if (prices.isEmpty) return 'medium';
    
    // Use same median-based logic as the app (±15% around median)
    final sortedPrices = prices.map((p) => p.price).toList()..sort();
    final length = sortedPrices.length;
    final medianIndex = (length / 2).floor();
    final median = sortedPrices[medianIndex]; // Simple: always take the middle element
    
    // Create symmetric ranges around median (±15%) - same as app
    final range15 = median * 0.15;
    final greenThreshold = median - range15;   // Median - 15%
    final orangeThreshold = median + range15;  // Median + 15%
    
    if (current < greenThreshold) return 'low';      // < Median - 15%
    if (current < orangeThreshold) return 'medium';  // Median ± 15%
    return 'high';                                   // > Median + 15%
  }
  
  @deprecated
  static String _getPriceStatus(double current, double min, double max) {
    final range = max - min;
    final position = current - min;
    final percentage = position / range;
    
    if (percentage <= 0.33) {
      return 'low';
    } else if (percentage <= 0.66) {
      return 'medium';
    } else {
      return 'high';
    }
  }
  
  static String _getPriceTrend(List<PriceData> prices, DateTime now) {
    try {
      // Get current price
      final currentPrice = PriceUtils.getCurrentPrice(prices);
      if (currentPrice == null) return 'stable';
      
      // Get full day prices for context
      final fullTodayPrices = PriceUtils.getFullDayPrices(prices, now);
      if (fullTodayPrices.isEmpty) return 'stable';
      
      // Calculate today's min and max for context
      final todayMin = fullTodayPrices.map((p) => p.price).reduce((a, b) => a < b ? a : b);
      final todayMax = fullTodayPrices.map((p) => p.price).reduce((a, b) => a > b ? a : b);
      final todayRange = todayMax - todayMin;
      
      // Get next 3 hours
      final nextHours = prices.where((price) {
        return price.startTime.isAfter(now) && 
               price.startTime.isBefore(now.add(const Duration(hours: 3)));
      }).toList();
      
      if (nextHours.isEmpty) return 'stable';
      
      // Sort by time to ensure correct order
      nextHours.sort((a, b) => a.startTime.compareTo(b.startTime));
      
      // Calculate weighted average (60% next hour, 25% second hour, 15% third hour)
      double weightedAvg;
      if (nextHours.length == 1) {
        weightedAvg = nextHours[0].price;
      } else if (nextHours.length == 2) {
        weightedAvg = nextHours[0].price * 0.7 + nextHours[1].price * 0.3;
      } else {
        weightedAvg = nextHours[0].price * 0.6 + 
                     nextHours[1].price * 0.25 + 
                     nextHours[2].price * 0.15;
      }
      
      // NEUE LOGIK: Kombiniere prozentuale und absolute Änderung
      final difference = weightedAvg - currentPrice.price;
      final percentageChange = (difference / currentPrice.price) * 100;
      
      // Position im Tagesbereich (0 = Min, 1 = Max)
      final currentPosition = (currentPrice.price - todayMin) / todayRange;
      final futurePosition = (weightedAvg - todayMin) / todayRange;
      
      // Schwellwerte anpassen basierend auf Position im Tagesbereich
      // Wenn wir schon sehr günstig sind (< 20% vom Min), ignoriere kleine Anstiege
      // Wenn wir schon sehr teuer sind (> 80% vom Min), ignoriere kleine Rückgänge
      
      if (todayRange < 0.5) {
        // Sehr kleiner Tagesbereich (< 0.5 ct Unterschied) - alles ist "stabil"
        return 'stable';
      }
      
      // Absolute Änderung im Kontext des Tagesbereichs
      final relativeChange = (futurePosition - currentPosition) * 100; // In Prozent des Tagesbereichs
      
      // Neue Schwellwerte basierend auf Tageskontext:
      // - Wenn Änderung < 5% des Tagesbereichs: stabil
      // - 5-20% des Tagesbereichs: leichter Trend
      // - > 20% des Tagesbereichs: starker Trend
      
      final absRelativeChange = relativeChange.abs();
      
      if (absRelativeChange < 5) {
        return 'stable';  // →
      } else if (absRelativeChange <= 20) {
        // Leichter Trend (5-20% Änderung im Tagesbereich)
        return relativeChange > 0 ? 'slightly_rising' : 'slightly_falling';
      } else {
        // Starker Trend (> 20% des Tagesbereichs)
        return relativeChange > 0 ? 'strongly_rising' : 'strongly_falling';
      }
    } catch (e) {
      return 'stable';
    }
  }
  
  static Future<void> registerBackgroundCallback() async {
    await HomeWidget.registerBackgroundCallback(backgroundCallback);
  }
  
  static Future<void> backgroundCallback(Uri? uri) async {
    if (uri?.host == 'updatewidget') {
      await updateWidget();
    }
  }
  
  /// Setup listener for widget clicks from Android
  static void setupWidgetClickListener(Function onWidgetClick) {
    print('[WidgetService] Setting up widget click listener');
    _channel.setMethodCallHandler((call) async {
      print('[WidgetService] Received method call: ${call.method}');
      if (call.method == 'widgetClicked') {
        print('[WidgetService] Widget clicked event received');
        onWidgetClick();
      }
    });
    print('[WidgetService] Widget click listener setup complete');
  }
  
  static Future<String> _getThemeModeSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('theme_mode') ?? 'system';
    } catch (e) {
      return 'system'; // Default to system on error
    }
  }
}