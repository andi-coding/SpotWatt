import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import 'price_cache_service.dart';
import 'background_task_service.dart';
import 'firebase_notification_service.dart';
import 'notification_service.dart';

/// Shared logic for handling FCM price update messages
/// Used by both background and foreground handlers
/// Made public so it can be called from main.dart for early foreground message handling
Future<void> handlePriceUpdateMessage(RemoteMessage message, {required bool isBackground}) async {
  final prefix = isBackground ? '[FCM-BG]' : '[FCM-FG]';

  debugPrint('$prefix handlePriceUpdateMessage called');
  debugPrint('$prefix Message action: ${message.data['action']}');

  if (message.data['action'] != 'update_prices') {
    debugPrint('$prefix Ignoring message - action is not update_prices');
    return;
  }

  try {
    if (isBackground) {
      debugPrint('$prefix Initializing timezone for background isolate...');
      try {
        tz_data.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
        debugPrint('$prefix Timezone initialized successfully');
      } catch (e) {
        debugPrint('$prefix ❌ Timezone initialization failed: $e');
        throw e;
      }
    }

    // Get user's selected market
    debugPrint('$prefix Loading SharedPreferences...');
    final prefs = await SharedPreferences.getInstance();
    final market = prefs.getString('price_market') ?? 'AT';
    debugPrint('$prefix Market: $market');

    // Fetch fresh prices AND update all services (Widget, Notifications, Tips)
    debugPrint('$prefix Fetching fresh prices and updating services...');
    await PriceCacheService().fetchAndUpdateAll(market: market);
    debugPrint('$prefix Fresh prices fetched and all services updated');

    // Reschedule WorkManager for next hourly check
    debugPrint('$prefix Rescheduling WorkManager...');
    await BackgroundTaskService.reschedule();
    debugPrint('$prefix WorkManager rescheduled');

    debugPrint('$prefix ✅ Price update completed successfully');

  } catch (e, stackTrace) {
    debugPrint('$prefix ❌ Error updating prices: $e');
    debugPrint('$prefix Stack trace: $stackTrace');

    // Schedule retry worker as fallback (only for background handler)
    if (isBackground) {
      try {
        await Workmanager().registerOneOffTask(
          'fcm-retry-${DateTime.now().millisecondsSinceEpoch}', // Unique ID with timestamp
          'fetchPricesRetry',                                    // Task name (checked in callback)
          constraints: Constraints(
            networkType: NetworkType.connected,  // Wait for network before starting
          ),
          initialDelay: Duration(seconds: 30),   // Wait 30s before attempting (avoids immediate retry)
          backoffPolicy: BackoffPolicy.exponential,  // If retry fails, use exponential backoff
          backoffPolicyDelay: Duration(seconds: 30),
        );
        debugPrint('$prefix ✅ Retry worker scheduled (waits for network)');
      } catch (workerError) {
        debugPrint('$prefix ❌ Failed to schedule retry worker: $workerError');
        // Non-critical: Hourly worker will eventually update prices
      }
    }
  }
}

/// Background message handler - MUST be top-level function!
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Flutter bindings for background isolate
  debugPrint('[FCM-BG] ========== BACKGROUND HANDLER STARTED ==========');
  debugPrint('[FCM-BG] Timestamp: ${DateTime.now().toIso8601String()}');
  debugPrint('[FCM-BG] Message ID: ${message.messageId}');
  debugPrint('[FCM-BG] Sent time: ${message.sentTime}');

  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[FCM-BG] Flutter bindings initialized');

    // ✅ Initialize Firebase Core (CRITICAL for background isolate!)
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[FCM-BG] Firebase Core initialized');
  } catch (e, stackTrace) {
    debugPrint('[FCM-BG] ❌ Failed to initialize: $e');
    debugPrint('[FCM-BG] Stack trace: $stackTrace');
    return;
  }

  debugPrint('[FCM-BG] Background message received: ${message.data}');

  try {
    // Only handle silent "update_prices" messages in background
    // Notification messages (daily_summary, cheapest_hour, etc.) are automatically displayed by Android
    if (message.data['action'] == 'update_prices') {
      await handlePriceUpdateMessage(message, isBackground: true);
    } else {
      debugPrint('[FCM-BG] Notification message - Android will display automatically');
    }
    debugPrint('[FCM-BG] ========== BACKGROUND HANDLER COMPLETED ==========');
  } catch (e, stackTrace) {
    debugPrint('[FCM-BG] ❌ Handler failed: $e');
    debugPrint('[FCM-BG] Stack trace: $stackTrace');
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging? _messaging;
  String? _currentToken;

  /// Initialize FCM and register device token
  /// Note: We only use data messages (no visible notifications), so no permission needed
  Future<void> initialize() async {
    try {
      _messaging = FirebaseMessaging.instance;

      // Get device token (no permission needed for data-only messages)
      String? token = await _messaging!.getToken();
      if (token != null) {
        _currentToken = token;
        debugPrint('[FCM] Device token: ${token.substring(0, 20)}...');

        // Check if token has changed
        final prefs = await SharedPreferences.getInstance();
        final lastToken = prefs.getString('fcm_last_token');

        if (token != lastToken) {
          // Token changed or first registration
          debugPrint('[FCM] Token changed, registering with Firebase...');
          await FirebaseNotificationService().registerFCMToken();
          await FirebaseNotificationService().syncPreferences();
          await prefs.setString('fcm_last_token', token);
        } else {
          debugPrint('[FCM] Token unchanged, skipping registration');
        }
      }

      // Listen for token refresh (rare, but happens)
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('[FCM] Token refreshed, updating Firebase...');

        // Update Firebase
        await FirebaseNotificationService().registerFCMToken();
        await FirebaseNotificationService().syncPreferences();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_last_token', newToken);
      });

      // Note: Foreground message handler is now registered in main.dart
      // to ensure messages are not lost during app startup

    } catch (e) {
      debugPrint('[FCM] Initialization failed: $e');
    }
  }

  /// Get current FCM token (for debugging)
  String? get currentToken => _currentToken;

  /// Show FCM notification in foreground using local notifications
  /// FCM provides the complete notification (title/body) - we just display it
  static Future<void> showForegroundNotification(RemoteMessage message) async {
    try {
      // FCM already parsed the notification for us!
      final notification = message.notification;
      if (notification == null) {
        debugPrint('[FCM] No notification payload - skipping');
        return;
      }

      final title = notification.title ?? 'SpotWatt';
      final body = notification.body ?? '';

      // Extract notification type from data payload
      final notificationType = message.data['type'] ?? 'general';

      debugPrint('[FCM] Showing foreground notification: $title');

      // Determine channel based on type
      String channelId;
      String channelName;
      int notificationId;

      switch (notificationType) {
        case 'daily_summary':
          channelId = 'daily_summary';
          channelName = 'Tägliche Zusammenfassung';
          notificationId = 100;
          break;
        case 'cheapest_hour':
          channelId = 'cheapest_hour';
          channelName = 'Günstigste Stunden';
          notificationId = 200;
          break;
        case 'threshold_alert':
          channelId = 'price_threshold';
          channelName = 'Preisschwellen';
          notificationId = 300;
          break;
        case 'window_reminder':
          channelId = 'window_reminders';
          channelName = 'Zeitfenster-Erinnerungen';
          notificationId = 2000;
          break;
        default:
          channelId = 'default';
          channelName = 'Benachrichtigungen';
          notificationId = 999;
      }

      // Import NotificationService to access flutter_local_notifications
      final notificationService = NotificationService();

      // Simply show the notification that FCM already prepared for us
      await notificationService.notifications.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_notification_small',
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
            ),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );

      debugPrint('[FCM] ✅ Foreground notification displayed');

    } catch (e, stackTrace) {
      debugPrint('[FCM] ❌ Failed to show foreground notification: $e');
      debugPrint('[FCM] Stack trace: $stackTrace');
    }
  }
}
