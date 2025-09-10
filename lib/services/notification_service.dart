import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../models/price_data.dart';
import '../utils/price_utils.dart';
import 'price_cache_service.dart';
import 'geofence_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
  int _notificationId = 1; // Global notification ID counter

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

  Future<void> rescheduleNotifications() async {
    debugPrint('[NotificationService] Rescheduling notifications due to settings change');
    await notifications.cancelAll();
    await scheduleNotifications();
  }

  Future<void> scheduleNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    
    final priceCacheService = PriceCacheService();
    final prices = await priceCacheService.getPrices();
    
    if (prices.isEmpty) return;
    
    // Cancel all notifications to avoid duplicates
    await notifications.cancelAll();
    
    // Reset notification ID counter
    _notificationId = 1;
    
    final priceThresholdEnabled = prefs.getBool('price_threshold_enabled') ?? false;
    final notificationThreshold = prefs.getDouble('notification_threshold') ?? 10.0;
    
    if (priceThresholdEnabled) {
      for (var price in prices) {
        if (price.price <= notificationThreshold) {
          if (!_isInQuietTime(price.startTime, prefs)) {
            await _schedulePriceNotification(price);
          }
        }
      }
    }
    
    final cheapestTimeEnabled = prefs.getBool('cheapest_time_enabled') ?? true;
    final notificationMinutesBefore = prefs.getInt('notification_minutes_before') ?? 15;
    
    if (cheapestTimeEnabled) {
      final now = DateTime.now();
      debugPrint('[NotificationService] Current time: $now');
      
      // Find all available days in the price data
      final availableDays = prices.map((p) => p.startTime.day).toSet().toList()..sort();
      debugPrint('[NotificationService] Available days in data: $availableDays');
      
      // For each available day, find the cheapest hour of the WHOLE day
      for (final day in availableDays) {
        final dayPrices = prices.where((p) => p.startTime.day == day).toList();
        debugPrint('[NotificationService] Day $day: ${dayPrices.length} hours found');
        
        if (dayPrices.length >= 24) { // Only if we have the complete day
          final cheapestOfDay = dayPrices.reduce((a, b) => a.price < b.price ? a : b);
          final dayName = day == now.day ? 'today' : day == now.day + 1 ? 'tomorrow' : 'day $day';
          
          debugPrint('[NotificationService] Cheapest of $dayName (day $day): ${cheapestOfDay.startTime} - ${PriceUtils.formatPrice(cheapestOfDay.price)}');
          
          await _scheduleCheapestTimeNotification(
            cheapestOfDay, 
            notificationMinutesBefore
          );
        } else {
          debugPrint('[NotificationService] Skipping day $day - incomplete (only ${dayPrices.length}/24 hours)');
        }
      }
    }
    
    // Schedule daily summary
    final dailySummaryEnabled = prefs.getBool('daily_summary_enabled') ?? true;
    if (dailySummaryEnabled) {
      await _scheduleDailySummary(prices, prefs);
    }
    
    debugPrint('Scheduled ${_notificationId - 1} notifications');
  }

  Future<void> _schedulePriceNotification(PriceData price) async {
    final notificationTime = price.startTime.subtract(const Duration(minutes: 5));
    
    // Check location-based settings
    final prefs = await SharedPreferences.getInstance();
    final locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
    
    if (locationBasedNotifications) {
      final geofenceService = GeofenceService();
      final isAtHome = await geofenceService.isAtHome();
      if (!isAtHome) {
        debugPrint('Notification skipped - user not at home');
        return;
      }
    }
    
    if (notificationTime.isAfter(DateTime.now())) {
      await notifications.zonedSchedule(
        _notificationId++,
        '💡 Günstiger Strompreis in 5 Min!',
        'Ab ${price.startTime.hour.toString().padLeft(2, '0')}:00 Uhr nur ${PriceUtils.formatPrice(price.price)} - Perfekt für energieintensive Geräte!',
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
    int minutesBefore
  ) async {
    final notificationTime = price.startTime.subtract(Duration(minutes: minutesBefore));
    final prefs = await SharedPreferences.getInstance();
    
    // Check location-based settings
    final locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
    
    if (locationBasedNotifications) {
      final geofenceService = GeofenceService();
      final isAtHome = await geofenceService.isAtHome();
      if (!isAtHome) {
        debugPrint('Cheapest time notification skipped - user not at home');
        return;
      }
    }
    
    if (notificationTime.isAfter(DateTime.now()) && !_isInQuietTime(notificationTime, prefs)) {
      debugPrint('[NotificationService] ✅ Scheduling cheapest time notification for: $notificationTime (price starts: ${price.startTime})');
      await notifications.zonedSchedule(
        _notificationId++,
        '⚡ Günstigster Zeitpunkt!',
        'In $minutesBefore Minuten beginnt der günstigste Zeitpunkt des Tages (${PriceUtils.formatPrice(price.price)})',
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
    } else {
      debugPrint('[NotificationService] ❌ Skipping cheapest time notification for: $notificationTime (price starts: ${price.startTime}) - already past or in quiet time');
    }
  }

  bool _isInQuietTime(DateTime time, SharedPreferences prefs) {
    // Check if quiet time is enabled
    final quietTimeEnabled = prefs.getBool('quiet_time_enabled') ?? false;
    if (!quietTimeEnabled) return false;
    
    // Standard-Ruhezeiten falls nicht gesetzt
    final startHour = prefs.getInt('quiet_time_start_hour') ?? 22;
    final startMinute = prefs.getInt('quiet_time_start_minute') ?? 0;
    final endHour = prefs.getInt('quiet_time_end_hour') ?? 6;
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
  
  
  // Find cheapest hours
  List<PriceData> findCheapestHours(List<PriceData> prices, int count) {
    if (prices.isEmpty) return [];
    
    final sortedPrices = List<PriceData>.from(prices)
      ..sort((a, b) => a.price.compareTo(b.price));
    
    return sortedPrices.take(count).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
  
  // Schedule daily summary notification
  Future<void> _scheduleDailySummary(
    List<PriceData> prices, 
    SharedPreferences prefs
  ) async {
    final summaryHour = prefs.getInt('daily_summary_hour') ?? 7;
    final summaryMinute = prefs.getInt('daily_summary_minute') ?? 0;
    
    final now = DateTime.now();
    var notificationTime = DateTime(
      now.year,
      now.month,
      now.day,
      summaryHour,
      summaryMinute,
    );
    
    // If time has passed today, schedule for tomorrow
    bool isForTomorrow = false;
    if (notificationTime.isBefore(now)) {
      notificationTime = notificationTime.add(const Duration(days: 1));
      isForTomorrow = true;
    }
    
    // Find prices for the CURRENT day (today), not the notification day
    // The summary should always show today's prices when sent
    final targetDay = isForTomorrow ? now.add(const Duration(days: 1)) : now;
    
    // Only get FUTURE hours of the target day (from notification time onwards)
    final futurePrices = prices.where((p) => 
      p.startTime.day == targetDay.day &&
      p.startTime.month == targetDay.month &&
      p.startTime.year == targetDay.year &&
      p.startTime.isAfter(notificationTime) // Only hours after the notification time
    ).toList();
    
    if (futurePrices.isEmpty) return;
    
    // Get number of hours from preferences
    final hoursCount = prefs.getInt('daily_summary_hours') ?? 3;
    
    // Find cheapest hours from FUTURE prices only
    final cheapestHours = findCheapestHours(futurePrices, hoursCount);
    
    // Check for high price warnings
    final highPriceWarningEnabled = prefs.getBool('high_price_warning_enabled') ?? false;
    final highPriceThreshold = prefs.getDouble('high_price_threshold') ?? 50.0;
    
    String? highPriceWarning;
    if (highPriceWarningEnabled) {
      // Only warn about FUTURE high prices
      final highPrices = futurePrices.where((p) => p.price > highPriceThreshold).toList();
      if (highPrices.isNotEmpty) {
        // Sort high prices by time (chronological order)
        highPrices.sort((a, b) => a.startTime.compareTo(b.startTime));
        
        final warningBuffer = StringBuffer();
        warningBuffer.write('⚠️ WARNUNG: Heute sehr hohe Preise!\n\n');
        
        for (var price in highPrices) {
          warningBuffer.write('• ${price.startTime.hour.toString().padLeft(2, '0')}:00-');
          warningBuffer.write('${price.endTime.hour.toString().padLeft(2, '0')}:00: ');
          warningBuffer.write('${PriceUtils.formatPrice(price.price)}\n');
        }
        warningBuffer.write('\n');
        
        highPriceWarning = warningBuffer.toString();
      }
    }
    
    // Format message - always for "heute" when notification is sent
    final dayText = 'heute';
    final buffer = StringBuffer();
    
    // Add high price warning first if exists
    if (highPriceWarning != null) {
      buffer.write(highPriceWarning);
      buffer.write('\n'); // Extra line between warning and cheapest hours
    }
    
    // Add cheapest hours section
    buffer.write('💡 Die $hoursCount günstigsten Stunden $dayText:\n\n');
    for (var i = 0; i < cheapestHours.length; i++) {
      final hour = cheapestHours[i];
      buffer.write('• ${hour.startTime.hour}:00-${hour.endTime.hour}:00 Uhr: ');
      buffer.write('${PriceUtils.formatPrice(hour.price)}\n');
    }
    
    // Check location if needed
    final locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
    if (locationBasedNotifications) {
      final geofenceService = GeofenceService();
      final isAtHome = await geofenceService.isAtHome();
      if (!isAtHome) {
        debugPrint('Daily summary skipped - user not at home');
        return;
      }
    }
    
    // Check quiet time
    if (_isInQuietTime(notificationTime, prefs)) {
      debugPrint('Daily summary skipped - in quiet time');
      return;
    }
    
    final notificationText = buffer.toString().trim();
    
    await notifications.zonedSchedule(
      _notificationId++,
      '📊 Tägliche Strompreis-Übersicht',
      notificationText,
      tz.TZDateTime.from(notificationTime, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_summary',
          'Tägliche Zusammenfassung',
          channelDescription: 'Tägliche Übersicht der günstigsten Strompreise',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(notificationText),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    
    debugPrint('Scheduled daily summary for $notificationTime');
  }
}