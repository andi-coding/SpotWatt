import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class LocationService {
  static const String _homeLatKey = 'home_latitude';
  static const String _homeLonKey = 'home_longitude';
  static const String _homeRadiusKey = 'home_radius';
  static const double _defaultRadius = 100.0; // 100 meters default

  // Request location permissions
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      if (!await requestLocationPermission()) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Save home location
  Future<bool> saveHomeLocation() async {
    final position = await getCurrentLocation();
    if (position == null) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_homeLatKey, position.latitude);
    await prefs.setDouble(_homeLonKey, position.longitude);
    
    return true;
  }

  // Save custom home location
  Future<bool> saveCustomHomeLocation(double latitude, double longitude) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_homeLatKey, latitude);
    await prefs.setDouble(_homeLonKey, longitude);
    
    return true;
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

  // Check if user is at home
  Future<bool> isUserAtHome() async {
    final currentPosition = await getCurrentLocation();
    if (currentPosition == null) return false;

    final homeLocation = await getHomeLocation();
    if (homeLocation == null) return false;

    final radius = await getHomeRadius();

    final distance = calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      homeLocation['latitude']!,
      homeLocation['longitude']!,
    );

    return distance <= radius;
  }

  // Calculate distance between two points in meters
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * (math.pi / 180);
  }

  // Clear home location
  Future<void> clearHomeLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeLatKey);
    await prefs.remove(_homeLonKey);
    await prefs.remove(_homeRadiusKey);
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