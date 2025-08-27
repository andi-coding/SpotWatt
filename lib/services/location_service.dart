import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'geofence_service.dart';

class LocationService {
  static const String _homeLatKey = 'home_latitude';
  static const String _homeLonKey = 'home_longitude';
  static const String _homeRadiusKey = 'home_radius';
  static const double _defaultRadius = 100.0; // 100 meters for reliable detection
  
  final GeofenceService _geofenceService = GeofenceService();

  // Save home location
  Future<bool> saveHomeLocation() async {
    try {
      // Permissions are already handled when feature is enabled
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_homeLatKey, position.latitude);
      await prefs.setDouble(_homeLonKey, position.longitude);
      
      // Setup geofence if location-based notifications are enabled
      final locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
      if (locationBasedNotifications) {
        await _setupHomeGeofence(position.latitude, position.longitude);
      }
      
      return true;
    } catch (e) {
      debugPrint('Error getting location: $e');
      return false;
    }
  }


  // Get saved home location
  Future<Map<String, double>?> getHomeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_homeLatKey);
    final lon = prefs.getDouble(_homeLonKey);

    if (lat == null || lon == null) return null;

    return {
      'latitude': lat,
      'longitude': lon,
    };
  }

  // Set home radius
  Future<void> setHomeRadius(double radiusInMeters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_homeRadiusKey, radiusInMeters);
  }

  // Get home radius
  Future<double> getHomeRadius() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_homeRadiusKey) ?? _defaultRadius;
  }


  // Clear home location
  Future<void> clearHomeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeLatKey);
    await prefs.remove(_homeLonKey);
    await prefs.remove(_homeRadiusKey);
    
    // Remove geofence
    await _geofenceService.removeHomeGeofence();
  }

  // Setup geofence with current home location and radius
  Future<void> _setupHomeGeofence(double latitude, double longitude) async {
    final prefs = await SharedPreferences.getInstance();
    final radius = prefs.getDouble(_homeRadiusKey) ?? _defaultRadius;
    
    await _geofenceService.initialize();
    await _geofenceService.setupHomeGeofence(latitude, longitude, radius);
  }

  // Enable location-based notifications (setup geofence)
  Future<void> enableLocationBasedNotifications() async {
    final homeLocation = await getHomeLocation();
    if (homeLocation != null) {
      // Request permissions first
      final hasPermissions = await _geofenceService.requestPermissions();
      if (hasPermissions) {
        await _setupHomeGeofence(homeLocation['latitude']!, homeLocation['longitude']!);
      } else {
        debugPrint('[LocationService] Geofence permissions not granted');
      }
    }
  }

  // Disable location-based notifications (remove geofence)
  Future<void> disableLocationBasedNotifications() async {
    await _geofenceService.removeHomeGeofence();
  }

  // Update home radius and refresh geofence
  Future<void> updateHomeRadius(double radius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_homeRadiusKey, radius);
    
    final homeLocation = await getHomeLocation();
    final locationBasedNotifications = prefs.getBool('location_based_notifications') ?? false;
    
    if (homeLocation != null && locationBasedNotifications) {
      await _setupHomeGeofence(homeLocation['latitude']!, homeLocation['longitude']!);
    }
  }

  // Get address from coordinates
  Future<String?> getAddressFromLocation(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        
        // Build address string
        List<String> addressParts = [];
        
        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.postalCode != null && place.postalCode!.isNotEmpty) {
          addressParts.add(place.postalCode!);
        }
        
        if (addressParts.isEmpty && place.name != null && place.name!.isNotEmpty) {
          addressParts.add(place.name!);
        }
        
        return addressParts.join(', ');
      }
    } catch (e) {
      print('Error getting address: $e');
    }
    return null;
  }
}