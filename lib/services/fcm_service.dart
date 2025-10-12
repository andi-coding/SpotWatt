import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'price_cache_service.dart';
import 'notification_service.dart';
import 'widget_service.dart';
import 'background_task_service.dart';

/// Background message handler - MUST be top-level function!
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Flutter bindings for background isolate
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[FCM] Background message received: ${message.data}');

  if (message.data['action'] == 'update_prices') {
    try {
      // Initialize timezone for background isolate
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Vienna'));

      // Get user's selected market
      final prefs = await SharedPreferences.getInstance();
      final market = prefs.getString('selected_market') ?? 'AT';

      // Fetch fresh prices from API (bypasses cache)
      debugPrint('[FCM] Fetching fresh prices from API for market: $market');
      await PriceCacheService().fetchFreshPrices(market: market);

      debugPrint('[FCM] Scheduling notifications...');
      await NotificationService().scheduleNotifications();

      debugPrint('[FCM] Updating widget...');
      await WidgetService.updateWidget();

      debugPrint('[FCM] Rescheduling WorkManager...');
      await BackgroundTaskService.reschedule();

      debugPrint('[FCM] Price update completed successfully');
    } catch (e, stackTrace) {
      debugPrint('[FCM] Error updating prices: $e');
      debugPrint('[FCM] Stack trace: $stackTrace');
    }
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging? _messaging;
  String? _currentToken;

  /// Initialize FCM and register device token
  Future<void> initialize() async {
    try {
      _messaging = FirebaseMessaging.instance;

      // Request permission (iOS requires explicit permission, Android auto-granted)
      NotificationSettings settings = await _messaging!.requestPermission(
        alert: false,  // No visible notifications (only wake-up)
        badge: false,
        sound: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('[FCM] User granted permission');

        // Get device token
        String? token = await _messaging!.getToken();
        if (token != null) {
          _currentToken = token;
          debugPrint('[FCM] Device token: ${token.substring(0, 20)}...');

          // Only register if token changed (saves API calls)
          final prefs = await SharedPreferences.getInstance();
          final lastRegisteredToken = prefs.getString('fcm_last_registered_token');

          if (token != lastRegisteredToken) {
            debugPrint('[FCM] Token changed, registering with server...');
            await _registerTokenWithServer(token);
            await prefs.setString('fcm_last_registered_token', token);
          } else {
            debugPrint('[FCM] Token unchanged, skipping registration');
          }
        }

        // Listen for token refresh (rare, but happens)
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          debugPrint('[FCM] Token refreshed, updating server...');
          await _registerTokenWithServer(newToken);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('fcm_last_registered_token', newToken);
        });

        // Handle foreground messages (app is open)
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('[FCM] Foreground message received: ${message.data}');
          // In foreground, we could show a snackbar or trigger update directly
        });

      } else {
        debugPrint('[FCM] User declined permission');
      }

    } catch (e) {
      debugPrint('[FCM] Initialization failed: $e');
    }
  }

  /// Register device token with your backend
  Future<void> _registerTokenWithServer(String token) async {
    try {
      // Get user's selected market
      final prefs = await SharedPreferences.getInstance();
      final region = prefs.getString('selected_market') ?? 'AT';

      final response = await http.post(
        Uri.parse('https://spotwatt-prices.spotwatt-api.workers.dev/fcm/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'region': region,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Token registered successfully with server');
      } else {
        debugPrint('[FCM] Token registration failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[FCM] Failed to register token with server: $e');
      // Non-critical error, app continues to work
    }
  }

  /// Unregister device token (when user disables notifications)
  Future<void> unregister() async {
    try {
      if (_currentToken != null) {
        await http.post(
          Uri.parse('https://spotwatt-prices.spotwatt-api.workers.dev/fcm/unregister'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': _currentToken}),
        );

        await _messaging?.deleteToken();
        _currentToken = null;

        debugPrint('[FCM] Token unregistered');
      }
    } catch (e) {
      debugPrint('[FCM] Failed to unregister token: $e');
    }
  }

  /// Get current FCM token (for debugging)
  String? get currentToken => _currentToken;
}
