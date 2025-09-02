import 'package:flutter/material.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';
import 'location_permission_helper.dart';
import 'location_service.dart';

class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  static const String homeGeofenceId = 'home_geofence';
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize native geofence manager
      await NativeGeofenceManager.instance.initialize();
      
      debugPrint('[GeofenceService] Native geofence initialized');
      _isInitialized = true;
    } catch (e) {
      debugPrint('[GeofenceService] Error initializing: $e');
    }
  }

  Future<void> setupHomeGeofence(double latitude, double longitude, double radius) async {
    try {
      // Initialize if not already done
      if (!_isInitialized) {
        await initialize();
      }
      
      debugPrint('[GeofenceService] Setting up geofence at lat=$latitude, lng=$longitude, radius=${radius}m');

      // Remove any existing home geofence first
      await removeHomeGeofence();
      
      // Create geofence
      final homeGeofence = Geofence(
        id: homeGeofenceId,
        location: Location(latitude: latitude, longitude: longitude),
        radiusMeters: radius,
        triggers: {
          GeofenceEvent.enter,
          GeofenceEvent.exit,
        },
        iosSettings: const IosGeofenceSettings(
          initialTrigger: false,
        ),
        androidSettings: const AndroidGeofenceSettings(
          initialTriggers: {},
        ),
      );

      // Register geofence with callback
      try {
        await NativeGeofenceManager.instance.createGeofence(
          homeGeofence, 
          geofenceTriggered,
        );
        debugPrint('[GeofenceService] ✅ Geofence successfully registered with Android system');
      } catch (geofenceError) {
        debugPrint('[GeofenceService] ❌ CRITICAL: Failed to register geofence with Android: $geofenceError');
        
        // Show specific error notification
        final notificationService = NotificationService();
        await notificationService.notifications.show(
          9995,
          '❌ DEBUG: Geofence Registration Failed',
          'Android Error: $geofenceError',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'debug_geofence',
              'Debug Geofence',
              channelDescription: 'Debug notifications for geofence testing',
              importance: Importance.max,
              priority: Priority.max,
              color: Colors.red,
            ),
          ),
        );
        rethrow; // Re-throw to prevent success notification
      }
      
      // Show debug notification that geofence was created
     /* final notificationService = NotificationService();
      await notificationService.notifications.show(
        9997,
        '🎯 DEBUG: Geofence erstellt',
        'Position: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}\nRadius: ${radius.toInt()}m',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'debug_geofence',
            'Debug Geofence',
            channelDescription: 'Debug notifications for geofence testing',
            importance: Importance.max,
            priority: Priority.max,
            color: Colors.blue,
          ),
        ),
      );*/
      
      debugPrint('[GeofenceService] ✅ Home geofence successfully created');
    } catch (e) {
      debugPrint('[GeofenceService] ❌ Error setting up geofence: $e');
      
      // Show error notification
      final notificationService = NotificationService();
      await notificationService.notifications.show(
        9996,
        '❌ DEBUG: Geofence Fehler',
        'Fehler beim Erstellen: $e',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'debug_geofence',
            'Debug Geofence',
            channelDescription: 'Debug notifications for geofence testing',
            importance: Importance.max,
            priority: Priority.max,
            color: Colors.red,
          ),
        ),
      );
    }
  }

  Future<void> removeHomeGeofence() async {
    try {
      // Create a dummy geofence with the same ID for removal
      final dummyGeofence = Geofence(
        id: homeGeofenceId,
        location: const Location(latitude: 0, longitude: 0),
        radiusMeters: 100,
        triggers: {
          GeofenceEvent.enter,
          GeofenceEvent.exit,
        },
        iosSettings: const IosGeofenceSettings(
          initialTrigger: false,
        ),
        androidSettings: const AndroidGeofenceSettings(
          initialTriggers: {},
        ),
      );
      
      await NativeGeofenceManager.instance.removeGeofence(dummyGeofence);
      debugPrint('[GeofenceService] Home geofence removed');
    } catch (e) {
      debugPrint('[GeofenceService] Error removing geofence: $e');
    }
  }

  Future<bool> isAtHome() async {
    final prefs = await SharedPreferences.getInstance();
    
    // If no location is set, treat as "always at home" (graceful fallback)
    final locationService = LocationService();
    final homeLocation = await locationService.getHomeLocation();
    
    if (homeLocation == null) {
      debugPrint('[GeofenceService] No home location set - treating as always at home');
      return true; // Graceful fallback: always send notifications
    }
    
    // Check if device location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GeofenceService] Device location services disabled - treating as always at home (graceful fallback)');
      return true; // Graceful fallback: always send notifications
    }
    
    return prefs.getBool('is_at_home') ?? true;
  }

  // Request location permissions - including background location
  Future<bool> requestPermissions() async {
    try {
      await initialize();
      
      // Use our comprehensive permission helper
      final granted = await LocationPermissionHelper.requestLocationPermissions();
      
      if (!granted) {
        debugPrint('[GeofenceService] ❌ Background location permissions not granted - Geofencing will not work');
        return false;
      }
      
      debugPrint('[GeofenceService] ✅ All location permissions granted');
      return true;
    } catch (e) {
      debugPrint('[GeofenceService] Error requesting permissions: $e');
      return false;
    }
  }

  // Check if permissions are granted
  Future<bool> hasPermissions() async {
    try {
      await initialize();
      
      // Check if we have background location permission
      final hasBackground = await LocationPermissionHelper.hasBackgroundLocationPermission();
      return hasBackground;
    } catch (e) {
      debugPrint('[GeofenceService] Error checking permissions: $e');
      return false;
    }
  }
}

// Global geofence callback function - must be top-level
@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrint('[GeofenceService] Geofence triggered: ${params.geofences.map((e) => e.id).join(', ')} - ${params.event}');
  
  try {
    final prefs = await SharedPreferences.getInstance();
    final locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
    
    if (!locationBasedNotifications) {
      debugPrint('[GeofenceService] Location-based notifications disabled - ignoring geofence event');
      return;
    }

    // Check if any of the triggered geofences is our home geofence
    final homeGeofence = params.geofences.firstWhere(
      (geofence) => geofence.id == GeofenceService.homeGeofenceId,
      orElse: () => throw StateError('No home geofence found'),
    );
    
    if (homeGeofence.id == GeofenceService.homeGeofenceId) {      
      if (params.event == GeofenceEvent.enter) {
        await handleGeofenceEnter(prefs);
      } else if (params.event == GeofenceEvent.exit) {
        await handleGeofenceExit(prefs);
      }
    }
  } catch (e) {
    debugPrint('[GeofenceService] Error in geofence callback: $e');
  }
}

// Top-level handler functions
Future<void> handleGeofenceEnter(SharedPreferences prefs) async {
  debugPrint('[GeofenceService] User entered home area');
  // Update location status and schedule notifications  
  await prefs.setBool('is_at_home', true);
  
  try {
    // Initialize timezone and schedule notifications
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
    
    final notificationService = NotificationService();
    await notificationService.scheduleNotifications();
    debugPrint('[GeofenceService] Notifications scheduled');
  } catch (e) {
    debugPrint('[GeofenceService] Error scheduling notifications: $e');
  }
}

Future<void> handleGeofenceExit(SharedPreferences prefs) async {
  debugPrint('[GeofenceService] User exited home area');
  // Update location status and cancel notifications
  await prefs.setBool('is_at_home', false);
  
  try {
    // Initialize timezone and cancel notifications
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
    
    final notificationService = NotificationService();
    await notificationService.cancelAllNotifications();
    debugPrint('[GeofenceService] Notifications canceled');
  } catch (e) {
    debugPrint('[GeofenceService] Error canceling notifications: $e');
  }
}

bool isInQuietTime(SharedPreferences prefs) {
  final quietTimeEnabled = prefs.getBool('quiet_time_enabled') ?? false;
  if (!quietTimeEnabled) return false;
  
  final now = DateTime.now();
  final startHour = prefs.getInt('quiet_time_start_hour') ?? 22;
  final startMinute = prefs.getInt('quiet_time_start_minute') ?? 0;
  final endHour = prefs.getInt('quiet_time_end_hour') ?? 6;
  final endMinute = prefs.getInt('quiet_time_end_minute') ?? 0;
  
  final startMinutes = startHour * 60 + startMinute;
  final endMinutes = endHour * 60 + endMinute;
  final currentMinutes = now.hour * 60 + now.minute;
  
  if (startMinutes <= endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  } else {
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  }
}