import 'package:flutter/material.dart';

class PriceUtils {
  static Color getPriceColor(double price, double minPrice, double maxPrice) {
    final range = maxPrice - minPrice;
    if (range == 0) return Colors.green;
    
    final relative = (price - minPrice) / range;
    
    if (relative < 0.33) return Colors.green;
    if (relative < 0.66) return Colors.orange;
    return Colors.red;
  }

  static IconData getPriceIcon(double price, double minPrice, double maxPrice) {
    final range = maxPrice - minPrice;
    if (range == 0) return Icons.lightbulb;
    
    final relative = (price - minPrice) / range;
    
    if (relative < 0.33) return Icons.lightbulb; // Glühbirne für günstig
    if (relative < 0.66) return Icons.schedule; // Uhr für mittel (warten)
    return Icons.warning_amber; // Warnung für teuer
  }

  static String formatPrice(double price) {
    return '${price.toStringAsFixed(2)} ct/kWh';
  }

  static String formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}