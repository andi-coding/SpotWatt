import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/price_data.dart';
import 'awattar_service.dart';
import 'full_cost_calculator.dart';

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  
  @override
  String toString() => message;
}

class PriceCacheService {
  // Separate cache keys for each market
  static const String _cacheKeyAT = 'price_cache_AT';
  static const String _cacheKeyDE = 'price_cache_DE';
  static const String _cacheTimestampKeyAT = 'price_cache_timestamp_AT';
  static const String _cacheTimestampKeyDE = 'price_cache_timestamp_DE';
  
  final AwattarService _awattarService = AwattarService();
  final FullCostCalculator _fullCostCalculator = FullCostCalculator();
  
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
  
  /// Gets the current market from preferences
  Future<String> _getCurrentMarket() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('price_market') ?? 'AT';
  }

  /// Gets cache keys for a specific market
  (String cacheKey, String timestampKey) _getCacheKeys(String market) {
    if (market == 'AT') {
      return (_cacheKeyAT, _cacheTimestampKeyAT);
    } else {
      return (_cacheKeyDE, _cacheTimestampKeyDE);
    }
  }

  /// Lädt Preise aus Cache oder API
  /// Nutzt Cache wenn:
  /// - Cache vorhanden und nicht älter als 6 Stunden
  /// - Cache enthält Preise für heute und morgen (falls nach 14:00)
  Future<List<PriceData>> getPrices() async {
    final market = await _getCurrentMarket();
    final (cacheKey, _) = _getCacheKeys(market);

    List<PriceData> prices;

    final cachedPrices = await _loadFromCache(cacheKey);
    if (cachedPrices != null) {
      final isValid = await _isCacheValid(cachedPrices, market);
      print('[Cache] Found cached prices for $market: ${cachedPrices.length}, valid: $isValid');
      if (isValid) {
        prices = cachedPrices;
      } else {
        prices = await _fetchFreshPrices(market);
      }
    } else {
      print('[Cache] No cached prices found for $market - making API call');
      prices = await _fetchFreshPrices(market);
    }

    // Apply full cost calculations if enabled
    final fullCostPrices = await _fullCostCalculator.addFullCostToPrices(prices);
    return fullCostPrices;
  }
  
  Future<List<PriceData>> _fetchFreshPrices(String market) async {
    // Cache invalid - wait for network before API call
    print('[Cache] Waiting for network...');
    final hasNetwork = await _waitForNetwork();

    if (!hasNetwork) {
      print('[Cache] No network available');
      throw NetworkException('Für aktuelle Preise wird eine Internetverbindung benötigt. Bitte WiFi oder Mobile Daten aktivieren.');
    } else {
      print('[Cache] Network available, making API call for $market');
      try {
        final prices = await _awattarService.fetchPrices(market: market == 'AT' ? PriceMarket.austria : PriceMarket.germany);
        await _saveToCache(prices, market);
        print('[Cache] API call successful for $market, got ${prices.length} prices');
        return prices;
      } catch (e, stackTrace) {
        print('[Cache] API call failed for $market: $e');
        print('[Cache] StackTrace: $stackTrace');
        rethrow;
      }
    }
  }
  
  /// Prüft ob Cache noch gültig ist
  Future<bool> _isCacheValid(List<PriceData> prices, String market) async {
    final prefs = await SharedPreferences.getInstance();
    final (_, timestampKey) = _getCacheKeys(market);
    final timestamp = prefs.getInt(timestampKey);
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
    
    // Nach 14:00 sollten wir auch Morgen-Preise haben
    if (now.hour >= 14) {
      final tomorrow = now.add(const Duration(days: 1));
      final hasTomorrow = prices.any((p) => 
        p.startTime.day == tomorrow.day && 
        p.startTime.month == tomorrow.month && 
        p.startTime.year == tomorrow.year
      );
      print('[Cache] Time is after 14:00 (${now.hour}:${now.minute}), checking for tomorrow (${tomorrow.day}/${tomorrow.month}/${tomorrow.year})');
      print('[Cache] Has tomorrow prices: $hasTomorrow');
      if (!hasTomorrow) {
        print('[Cache] Missing tomorrow prices after 14:00 - invalid');
        return false;
      }
    }
    
    print('[Cache] Cache is valid');
    return true;
  }
  
  /// Lädt Preise aus Cache
  Future<List<PriceData>?> _loadFromCache(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson = prefs.getString(cacheKey);
    
    if (cacheJson == null) return null;
    
    try {
      final List<dynamic> decoded = json.decode(cacheJson);
      return decoded.map((item) => PriceData.fromJson(item)).toList();
    } catch (e) {
      // Cache korrupt - löschen
      await clearCache(market: cacheKey.contains('AT') ? 'AT' : 'DE');
      return null;
    }
  }
  
  /// Speichert Preise in Cache
  Future<void> _saveToCache(List<PriceData> prices, String market) async {
    final prefs = await SharedPreferences.getInstance();
    final (cacheKey, timestampKey) = _getCacheKeys(market);

    // Preise als JSON speichern
    final pricesJson = prices.map((p) => p.toJson()).toList();
    await prefs.setString(cacheKey, json.encode(pricesJson));

    // Timestamp speichern
    await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// Löscht den Cache für einen spezifischen Markt
  Future<void> clearCache({String? market}) async {
    final prefs = await SharedPreferences.getInstance();

    if (market != null) {
      // Clear specific market cache
      final (cacheKey, timestampKey) = _getCacheKeys(market);
      await prefs.remove(cacheKey);
      await prefs.remove(timestampKey);
    } else {
      // Clear all caches
      await prefs.remove(_cacheKeyAT);
      await prefs.remove(_cacheKeyDE);
      await prefs.remove(_cacheTimestampKeyAT);
      await prefs.remove(_cacheTimestampKeyDE);
    }
  }

  /// Force clear all caches (for debugging)
  Future<void> clearAllCaches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKeyAT);
    await prefs.remove(_cacheKeyDE);
    await prefs.remove(_cacheTimestampKeyAT);
    await prefs.remove(_cacheTimestampKeyDE);
    // Also remove any legacy keys that might still exist
    await prefs.remove('price_cache');
    await prefs.remove('price_cache_timestamp');
    print('[Cache] All caches cleared');
  }

  /// Check and update cache for market switch (only if needed)
  Future<void> ensureCacheForMarket(String market) async {
    final (cacheKey, _) = _getCacheKeys(market);
    final cachedPrices = await _loadFromCache(cacheKey);

    // Only fetch if cache is missing or invalid
    if (cachedPrices == null || !(await _isCacheValid(cachedPrices, market))) {
      print('[Cache] Cache for $market is invalid or missing, fetching...');
      await _fetchFreshPrices(market);
    } else {
      print('[Cache] Cache for $market is valid, no API call needed');
    }
  }
  
  /// Gibt das Alter des Caches zurück
  Future<Duration?> getCacheAge({String? market}) async {
    final prefs = await SharedPreferences.getInstance();
    final marketToCheck = market ?? await _getCurrentMarket();
    final (_, timestampKey) = _getCacheKeys(marketToCheck);
    final timestamp = prefs.getInt(timestampKey);

    if (timestamp == null) return null;

    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(cacheTime);
  }
}