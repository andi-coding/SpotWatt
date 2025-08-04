import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'price_cache_service.dart';
import 'notification_service.dart';

/// Background Service für regelmäßige Updates
/// Nutzt einen Timer statt workmanager für bessere Kompatibilität
class BackgroundService {
  static Timer? _updateTimer;
  static Timer? _afternoonCheckTimer;
  static const String _lastUpdateKey = 'last_price_update';
  static const String _lastAfternoonCheckKey = 'last_afternoon_check';
  static const Duration _updateInterval = Duration(hours: 6);
  static const Duration _checkInterval = Duration(minutes: 30); // Häufigere Checks
  
  /// Startet den periodischen Update-Service
  static void startPeriodicUpdates() {
    // Sofort einmal ausführen
    _checkAndUpdatePrices();
    
    // Timer für regelmäßige Checks starten (alle 30 Minuten)
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(_checkInterval, (timer) {
      _checkAndUpdatePrices();
    });
    
    debugPrint('Background service started: Checks every 30 minutes');
  }
  
  /// Stoppt den periodischen Update-Service
  static void stopPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
    debugPrint('Background service stopped');
  }
  
  /// Prüft ob ein Update nötig ist und führt es aus
  static Future<void> _checkAndUpdatePrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdate = prefs.getInt(_lastUpdateKey);
      final lastAfternoonCheck = prefs.getInt(_lastAfternoonCheckKey);
      final now = DateTime.now();
      
      bool needsUpdate = false;
      String updateReason = '';
      
      if (lastUpdate == null) {
        needsUpdate = true;
        updateReason = 'First run';
      } else {
        final lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdate);
        final timeSinceUpdate = now.difference(lastUpdateTime);
        
        // 1. Reguläres Update alle 6 Stunden
        if (timeSinceUpdate > _updateInterval) {
          needsUpdate = true;
          updateReason = 'Regular 6h update';
        }
        
        // 2. Spezieller Check zwischen 13:00 und 15:00 für neue Tagespreise
        if (now.hour >= 13 && now.hour <= 15) {
          final todayAfternoonCheck = DateTime(now.year, now.month, now.day, 14);
          final lastCheckTime = lastAfternoonCheck != null 
            ? DateTime.fromMillisecondsSinceEpoch(lastAfternoonCheck)
            : DateTime(2000); // Sehr alte Zeit wenn noch nie gecheckt
            
          // Wenn wir heute noch nicht zwischen 13-15 Uhr gecheckt haben
          if (lastCheckTime.day != now.day) {
            needsUpdate = true;
            updateReason = 'Afternoon check for tomorrow prices';
            await prefs.setInt(_lastAfternoonCheckKey, now.millisecondsSinceEpoch);
          }
        }
        
        // 3. Morgens um 0:00 - 1:00 für neue Tagespreise
        if (now.hour >= 0 && now.hour <= 1 && lastUpdateTime.day != now.day) {
          needsUpdate = true;
          updateReason = 'Midnight update for new day';
        }
      }
      
      if (needsUpdate) {
        debugPrint('Update triggered: $updateReason at ${now.toIso8601String()}');
        await updatePricesAndNotifications();
      }
    } catch (e) {
      debugPrint('Background update check error: $e');
    }
  }
  
  /// Aktualisiert Preise und plant Notifications neu
  static Future<void> updatePricesAndNotifications() async {
    try {
      // Preise aktualisieren
      final priceCacheService = PriceCacheService();
      final prices = await priceCacheService.getPrices(forceRefresh: true);
      
      debugPrint('Background: Updated ${prices.length} prices');
      
      // Notifications neu planen
      final notificationService = NotificationService();
      await notificationService.scheduleNotifications();
      
      // Update-Zeit speichern
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastUpdateKey, DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('Background: Notifications scheduled');
    } catch (e) {
      debugPrint('Background update error: $e');
    }
  }
}