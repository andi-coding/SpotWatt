import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:price_app/services/awattar_service.dart';
import 'package:price_app/services/price_cache_service.dart';
import 'package:price_app/utils/price_utils.dart';
import 'package:price_app/models/price_data.dart';
import 'package:intl/intl.dart';
import 'dart:io';

class WidgetService {
  static const String androidWidgetName = 'PriceWidgetProvider';
  static const String iosWidgetKind = 'PriceWidget';
  static const MethodChannel _channel = MethodChannel('com.example.price_app/widget');
  
  static Future<void> updateWidget() async {
    try {
      final awattarService = AwattarService();
      final cacheService = PriceCacheService();
      
      // Get current prices
      var prices = await cacheService.getCachedPrices();
      if (prices == null || prices.isEmpty) {
        // Try to fetch fresh data
        prices = await awattarService.fetchPrices();
        if (prices.isEmpty) return;
      }
      
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
      
      // Determine price status (low, medium, high)
      final priceStatus = _getPriceStatus(currentPrice.price, minPrice, maxPrice);
      
      // Calculate trend for next hours
      final priceTrend = _getPriceTrend(prices, now);
      
      // Format update time
      final updateTime = DateFormat('HH:mm').format(now);
      
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
      await HomeWidget.saveWidgetData<String>('last_update', 'Stand: $updateTime');
      
      // Update the widget
      print('[WidgetService] Calling HomeWidget.updateWidget...');
      final updateResult = await HomeWidget.updateWidget(
        name: androidWidgetName,
        iOSName: iosWidgetKind,
      );
      print('[WidgetService] HomeWidget.updateWidget result: $updateResult');
      
      // Force Android widget update through native channel
      if (Platform.isAndroid) {
        try {
          print('[WidgetService] Calling native forceUpdateWidget...');
          final result = await _channel.invokeMethod('forceUpdateWidget');
          print('[WidgetService] Native forceUpdateWidget returned: $result');
        } catch (e) {
          print('[WidgetService] ERROR calling forceUpdateWidget: $e');
          print('[WidgetService] Error type: ${e.runtimeType}');
          if (e is MissingPluginException) {
            print('[WidgetService] MethodChannel not properly configured!');
          }
        }
      }
    } catch (e) {
      print('Error updating widget: $e');
    }
  }
  
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
}