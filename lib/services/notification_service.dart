import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../models/price_data.dart';
import 'price_cache_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  Future<void> initialize(BuildContext context) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked: ${response.payload}');
      },
    );
    
    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidPlugin = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestExactAlarmsPermission();
      }
    }
  }

  Future<void> scheduleNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    
    if (!notificationsEnabled) return;
    
    final priceCacheService = PriceCacheService();
    final prices = await priceCacheService.getPrices();
    
    if (prices.isEmpty) return;
    
    await notifications.cancelAll();
    
    int notificationId = 1;
    
    final priceThresholdEnabled = prefs.getBool('price_threshold_enabled') ?? true;
    final notificationThreshold = prefs.getDouble('notification_threshold') ?? 10.0;
    
    if (priceThresholdEnabled) {
      for (var price in prices) {
        if (price.price <= notificationThreshold) {
          if (!_isInQuietTime(price.startTime, prefs)) {
            await _schedulePriceNotification(price, notificationId++);
          }
        }
      }
    }
    
    final cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? true;
    final notificationMinutesBefore = prefs.getInt('notification_minutes_before') ?? 15;
    
    if (cheapestTimeEnabled) {
      final now = DateTime.now();
      final todayPrices = prices.where((p) => p.startTime.day == now.day).toList();
      if (todayPrices.isNotEmpty) {
        final cheapestToday = todayPrices.reduce((a, b) => a.price < b.price ? a : b);
        await _scheduleCheapestTimeNotification(
          cheapestToday, 
          'heute', 
          notificationId++, 
          notificationMinutesBefore
        );
      }
      
      final tomorrowPrices = prices.where((p) => p.startTime.day == now.day + 1).toList();
      if (tomorrowPrices.isNotEmpty) {
        final cheapestTomorrow = tomorrowPrices.reduce((a, b) => a.price < b.price ? a : b);
        await _scheduleCheapestTimeNotification(
          cheapestTomorrow, 
          'morgen', 
          notificationId++,
          notificationMinutesBefore
        );
      }
    }
    
    debugPrint('Scheduled ${notificationId - 1} notifications');
  }

  Future<void> _schedulePriceNotification(PriceData price, int notificationId) async {
    final notificationTime = price.startTime.subtract(const Duration(minutes: 5));
    
    if (notificationTime.isAfter(DateTime.now())) {
      await notifications.zonedSchedule(
        notificationId,
        '💡 Günstiger Strompreis!',
        'Jetzt nur ${price.price.toStringAsFixed(2)} ct/kWh - Perfekt für energieintensive Geräte!',
        tz.TZDateTime.from(notificationTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'price_alerts',
            'Preis-Benachrichtigungen',
            channelDescription: 'Benachrichtigungen bei günstigen Strompreisen',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> _scheduleCheapestTimeNotification(
    PriceData price, 
    String day, 
    int notificationId,
    int minutesBefore
  ) async {
    final notificationTime = price.startTime.subtract(Duration(minutes: minutesBefore));
    final prefs = await SharedPreferences.getInstance();
    
    if (notificationTime.isAfter(DateTime.now()) && !_isInQuietTime(notificationTime, prefs)) {
      await notifications.zonedSchedule(
        notificationId,
        '⚡ Günstigster Zeitpunkt $day!',
        'In $minutesBefore Minuten beginnt der günstigste Zeitpunkt des Tages (${price.price.toStringAsFixed(2)} ct/kWh)',
        tz.TZDateTime.from(notificationTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'cheapest_time',
            'Günstigste Zeit',
            channelDescription: 'Benachrichtigung zum günstigsten Zeitpunkt',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  bool _isInQuietTime(DateTime time, SharedPreferences prefs) {
    // Standard-Ruhezeiten falls nicht gesetzt
    final startHour = prefs.getInt('quiet_time_start_hour') ?? 22;
    final startMinute = prefs.getInt('quiet_time_start_minute') ?? 0;
    final endHour = prefs.getInt('quiet_time_end_hour') ?? 7;
    final endMinute = prefs.getInt('quiet_time_end_minute') ?? 0;
    
    final timeOfDay = TimeOfDay.fromDateTime(time);
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;
    final currentMinutes = timeOfDay.hour * 60 + timeOfDay.minute;
    
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  Future<void> cancelAllNotifications() async {
    await notifications.cancelAll();
  }
  
  /// Aktualisiert die Preise und plant Notifications neu
  Future<void> refreshPricesAndSchedule() async {
    final priceCacheService = PriceCacheService();
    await priceCacheService.getPrices(forceRefresh: true);
    await scheduleNotifications();
  }
}