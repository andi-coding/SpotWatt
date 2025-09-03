import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/price_data.dart';
import 'awattar_service.dart';

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  
  @override
  String toString() => message;
}

class PriceCacheService {
  static const String _cacheKey = 'price_cache';
  static const String _cacheTimestampKey = 'price_cache_timestamp';
  //static const Duration _cacheValidity = Duration(hours: 6); // Cache für 6 Stunden gültig
  
  final AwattarService _awattarService = AwattarService();
  
  /// Tests actual internet connectivity with DNS lookup
  Future<bool> _testInternetConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Waits for network connectivity with timeout (includes DNS test)
  Future<bool> _waitForNetwork({Duration timeout = const Duration(seconds: 5)}) async {
    final connectivity = Connectivity();
    final endTime = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(endTime)) {
      // Check connectivity first
      final currentStatus = await connectivity.checkConnectivity();
      if (currentStatus != ConnectivityResult.none) {
        // Connectivity exists, now test actual internet
        print('[Cache] Connectivity detected, testing DNS...');
        final hasInternet = await _testInternetConnectivity();
        if (hasInternet) {
          print('[Cache] DNS test successful');
          return true;
        }
        print('[Cache] DNS test failed, waiting...');
      }
      
      // Wait 1 second before retry
      await Future.delayed(Duration(seconds: 1));
    }
    
    print('[Cache] Network wait timeout');
    return false;
  }
  
  /// Lädt Preise aus Cache oder API
  /// Nutzt Cache wenn:
  /// - Cache vorhanden und nicht älter als 6 Stunden
  /// - Cache enthält Preise für heute und morgen (falls nach 13:00)
  Future<List<PriceData>> getPrices() async {
    final cachedPrices = await _loadFromCache();
    if (cachedPrices != null) {
      final isValid = await _isCacheValid(cachedPrices);
      print('[Cache] Found cached prices: ${cachedPrices.length}, valid: $isValid');
      if (isValid) {
        return cachedPrices;
      }
    } else {
      print('[Cache] No cached prices found - making API call');
    }
    
    // Cache invalid - wait for network before API call
    print('[Cache] Waiting for network...');
    final hasNetwork = await _waitForNetwork();
    
    if (!hasNetwork) {
      print('[Cache] No network available');
      throw NetworkException('Für aktuelle Preise wird eine Internetverbindung benötigt. Bitte WiFi oder Mobile Daten aktivieren.');
    } else {
      print('[Cache] Network available, making API call');
      try {
        final prices = await _awattarService.fetchPrices();
        await _saveToCache(prices);
        print('[Cache] API call successful, got ${prices.length} prices');
        return prices;
      } catch (e, stackTrace) {
        print('[Cache] API call failed: $e');
        print('[Cache] StackTrace: $stackTrace');
        rethrow;
      }
    }
  }
  
  /// Prüft ob Cache noch gültig ist
  Future<bool> _isCacheValid(List<PriceData> prices) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_cacheTimestampKey);
    if (timestamp == null) {
      print('[Cache] No timestamp found - invalid');
      return false;
    }
    
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    print('[Cache] Current time: ${now.toString()}');
    print('[Cache] Cache time: ${cacheTime.toString()}');
    print('[Cache] Cache age: ${now.difference(cacheTime).inMinutes} minutes');
    
    // Cache zu alt?
    //if (now.difference(cacheTime) > _cacheValidity) return false;
    
    // Debug: Show all available dates in prices
    final availableDates = prices.map((p) => '${p.startTime.day}/${p.startTime.month} ${p.startTime.hour}h').toSet().toList();
    print('[Cache] Available price dates/hours: $availableDates');
    
    // Haben wir Preise für heute?
    final hasToday = prices.any((p) => 
      p.startTime.day == now.day && 
      p.startTime.month == now.month && 
      p.startTime.year == now.year
    );
    print('[Cache] Has today prices (${now.day}/${now.month}/${now.year}): $hasToday');
    if (!hasToday) {
      print('[Cache] Missing today prices - invalid');
      return false;
    }
    
    // Nach 13:00 sollten wir auch Morgen-Preise haben
    if (now.hour >= 13) {
      final tomorrow = now.add(const Duration(days: 1));
      final hasTomorrow = prices.any((p) => 
        p.startTime.day == tomorrow.day && 
        p.startTime.month == tomorrow.month && 
        p.startTime.year == tomorrow.year
      );
      print('[Cache] Time is after 13:00 (${now.hour}:${now.minute}), checking for tomorrow (${tomorrow.day}/${tomorrow.month}/${tomorrow.year})');
      print('[Cache] Has tomorrow prices: $hasTomorrow');
      if (!hasTomorrow) {
        print('[Cache] Missing tomorrow prices after 13:00 - invalid');
        return false;
      }
    }
    
    print('[Cache] Cache is valid');
    return true;
  }
  
  /// Lädt Preise aus Cache
  Future<List<PriceData>?> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson = prefs.getString(_cacheKey);
    
    if (cacheJson == null) return null;
    
    try {
      final List<dynamic> decoded = json.decode(cacheJson);
      return decoded.map((item) => PriceData.fromJson(item)).toList();
    } catch (e) {
      // Cache korrupt - löschen
      await clearCache();
      return null;
    }
  }
  
  /// Speichert Preise in Cache
  Future<void> _saveToCache(List<PriceData> prices) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Preise als JSON speichern
    final pricesJson = prices.map((p) => p.toJson()).toList();
    await prefs.setString(_cacheKey, json.encode(pricesJson));
    
    // Timestamp speichern
    await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// Löscht den Cache
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimestampKey);
  }
  
  /// Gibt das Alter des Caches zurück
  Future<Duration?> getCacheAge() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_cacheTimestampKey);
    
    if (timestamp == null) return null;
    
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(cacheTime);
  }
}