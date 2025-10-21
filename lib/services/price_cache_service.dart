import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../models/price_data.dart';
import 'awattar_service.dart';
import 'cloudflare_price_service.dart';
import 'full_cost_calculator.dart';
import 'notification_service.dart';
import 'widget_service.dart';
import 'savings_tips_service.dart';

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
  
  // DNS check removed - HTTP client handles connectivity internally
  // and provides better error handling with SocketException/TimeoutException
  
  /// Gets the current market from preferences
  Future<String> _getCurrentMarket() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('price_market') ?? 'AT';
  }

  /// Gets cache keys for a specific market
  Future<(String cacheKey, String timestampKey)> _getCacheKeys(String market) async {
    // Add Full Cost suffix to cache key if Full Cost mode is enabled
    // This creates separate caches for each mode, allowing instant switching
    final fullCostMode = await _fullCostCalculator.isFullCostMode();
    final fullCostSuffix = fullCostMode ? '_fullcost' : '';

    if (market == 'AT') {
      return (
        '${_cacheKeyAT}${fullCostSuffix}',
        '${_cacheTimestampKeyAT}${fullCostSuffix}'
      );
    } else {
      return (
        '${_cacheKeyDE}${fullCostSuffix}',
        '${_cacheTimestampKeyDE}${fullCostSuffix}'
      );
    }
  }

  /// Lädt Preise aus Cache oder API
  /// Nutzt Cache wenn:
  /// - Cache vorhanden und nicht älter als 6 Stunden
  /// - Cache enthält Preise für heute und morgen (falls nach 14:00)
  Future<List<PriceData>> getPrices() async {
    final market = await _getCurrentMarket();
    final (cacheKey, _) = await _getCacheKeys(market);

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

    // ✅ Full Cost is already in cache (added by _fetchFreshPrices)
    // No need to calculate again!
    return prices;
  }
  
  /// Force fetch fresh prices from API (used by FCM background handler)
  /// Bypasses cache and always makes API call
  Future<List<PriceData>> fetchFreshPrices({String market = 'AT'}) async {
    return await _fetchFreshPrices(market);
  }

  /// Fetch prices AND update all dependent services
  /// Use this from top-level handlers (FCM, Background Worker, Pull-to-Refresh)
  /// This orchestrates the update flow: API → Cache → Services
  Future<void> fetchAndUpdateAll({String? market}) async {
    final targetMarket = market ?? await _getCurrentMarket();
    print('[Cache] fetchAndUpdateAll() for $targetMarket');

    // 1. Fetch fresh prices (API + Full Cost + Cache)
    await fetchFreshPrices(market: targetMarket);

    // 2. Update all dependent services (orchestrated from here)
    await updateDependentServices();

    print('[Cache] ✅ fetchAndUpdateAll() completed');
  }

  /// Update all services that depend on price data
  /// Assumes cache already contains fresh prices
  /// Each service will call getPrices() which reads from cache
  Future<void> updateDependentServices() async {
    print('[Services] Updating dependent services...');

    // Run all updates in parallel for better performance
    await Future.wait([
      NotificationService()
          .scheduleNotifications()
          .then((_) => print('[Services] ✅ Notifications'))
          .catchError((e) {
        print('[Services] ⚠️ Notifications failed: $e');
        return null;
      }),
      WidgetService.updateWidget()
          .then((_) => print('[Services] ✅ Widget'))
          .catchError((e) {
        print('[Services] ⚠️ Widget failed: $e');
        return null;
      }),
      SavingsTipsService()
          .recalculateTomorrowTips()
          .then((_) => print('[Services] ✅ Tips'))
          .catchError((e) {
        print('[Services] ⚠️ Tips failed: $e');
        return null;
      }),
    ]);

    print('[Services] ✅ All services updated');
  }

  Future<List<PriceData>> _fetchFreshPrices(String market) async {
    print('[Cache] Fetching from CloudFlare Worker for $market');

    try {
      // 1. API call (without Full Cost)
      final prices = await CloudflarePriceService.fetchPrices(
        market: market == 'AT' ? PriceMarket.austria : PriceMarket.germany,
      );

      // 2. Add Full Cost immediately (before caching)
      final fullCostPrices = await _fullCostCalculator.addFullCostToPrices(prices);
      print('[Cache] Full Cost calculated: ${fullCostPrices.length} prices');

      // 3. Save to cache (WITH Full Cost)
      await _saveToCache(fullCostPrices, market);

      // ✅ Service calls removed - orchestration happens at top level
      // See: fetchAndUpdateAll() for coordinated updates

      print('[Cache] CloudFlare fetch successful for $market, got ${fullCostPrices.length} prices');
      return fullCostPrices;

    } on TimeoutException catch (e) {
      print('[Cache] Request timeout: $e');
      throw NetworkException('Zeitüberschreitung bei Preisabruf. Bitte versuche es später erneut.');

    } on SocketException catch (e) {
      print('[Cache] Network error: $e');
      throw NetworkException('Für aktuelle Preise wird eine Internetverbindung benötigt. Bitte WiFi oder Mobile Daten aktivieren.');

    } catch (e, stackTrace) {
      print('[Cache] API call failed for $market: $e');
      print('[Cache] StackTrace: $stackTrace');
      rethrow;
    }
  }
  
  /// Prüft ob Cache noch gültig ist
  Future<bool> _isCacheValid(List<PriceData> prices, String market) async {
    final prefs = await SharedPreferences.getInstance();
    final (_, timestampKey) = await _getCacheKeys(market);
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
    
    // RULE 1: Haben wir Preise für HEUTE?
    final hasToday = prices.any((p) =>
      p.startTime.day == now.day &&
      p.startTime.month == now.month &&
      p.startTime.year == now.year
    );
    print('[Cache] Has today prices (${now.day}/${now.month}/${now.year}): $hasToday');
    if (!hasToday) {
      print('[Cache] ❌ Missing today prices - INVALID');
      return false;
    }

    // RULE 2: Nach 17:00 Uhr MÜSSEN Morgen-Preise da sein!
    // Begründung:
    // - ENTSO-E published Preise ~14:00 Uhr (sicher bis 17:00)
    // - User plant abends (17-21 Uhr) für morgen
    // - Falls FCM fehlschlägt, holen wir Preise spätestens beim App-Open ab 17:00
    final tomorrow = now.add(const Duration(days: 1));
    final hasTomorrow = prices.any((p) =>
      p.startTime.day == tomorrow.day &&
      p.startTime.month == tomorrow.month &&
      p.startTime.year == tomorrow.year
    );

    // Critical time window: After 17:00, tomorrow prices are REQUIRED
    if (now.hour >= 17 && !hasTomorrow) {
      print('[Cache] ❌ After 17:00 but missing tomorrow prices - INVALID');
      print('[Cache] Expected tomorrow: ${tomorrow.day}/${tomorrow.month}/${tomorrow.year}');
      return false;
    }

    // Before 17:00, tomorrow prices are optional (ENTSO-E might not have published yet)
    if (now.hour < 17 && !hasTomorrow) {
      print('[Cache] ℹ️ Before 17:00, tomorrow prices not yet required (cache still valid)');
    } else if (hasTomorrow) {
      print('[Cache] ✅ Tomorrow prices available');
    }

    print('[Cache] ✅ Cache is valid');
    return true;
  }
  
  /// Lädt Preise aus Cache
  Future<List<PriceData>?> _loadFromCache(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    // IMPORTANT: Reload from disk to get data written by background isolate (FCM handler)
    await prefs.reload();
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
    print('[Cache] 💾 Saving ${prices.length} prices to cache for market: $market');
    final prefs = await SharedPreferences.getInstance();
    final (cacheKey, timestampKey) = await _getCacheKeys(market);

    // Preise als JSON speichern
    final pricesJson = prices.map((p) => p.toJson()).toList();
    final success = await prefs.setString(cacheKey, json.encode(pricesJson));
    print('[Cache] 💾 setString($cacheKey) result: $success');

    // Timestamp speichern
    final timestampSuccess = await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    print('[Cache] 💾 setInt($timestampKey) result: $timestampSuccess');

    // Verify save
    final saved = prefs.getString(cacheKey);
    if (saved != null) {
      print('[Cache] ✅ Verified: prices saved successfully');
    } else {
      print('[Cache] ❌ ERROR: Failed to save prices to cache!');
    }
  }
  
  /// Löscht den Cache für einen spezifischen Markt
  Future<void> clearCache({String? market}) async {
    final prefs = await SharedPreferences.getInstance();

    if (market != null) {
      // Clear specific market cache (both Full Cost modes)
      await prefs.remove('${_cacheKeyAT}');
      await prefs.remove('${_cacheKeyAT}_fullcost');
      await prefs.remove('${_cacheTimestampKeyAT}');
      await prefs.remove('${_cacheTimestampKeyAT}_fullcost');

      await prefs.remove('${_cacheKeyDE}');
      await prefs.remove('${_cacheKeyDE}_fullcost');
      await prefs.remove('${_cacheTimestampKeyDE}');
      await prefs.remove('${_cacheTimestampKeyDE}_fullcost');

      print('[Cache] Cleared cache for $market (both Full Cost modes)');
    } else {
      // Clear all caches (both Full Cost modes)
      await prefs.remove(_cacheKeyAT);
      await prefs.remove('${_cacheKeyAT}_fullcost');
      await prefs.remove(_cacheKeyDE);
      await prefs.remove('${_cacheKeyDE}_fullcost');
      await prefs.remove(_cacheTimestampKeyAT);
      await prefs.remove('${_cacheTimestampKeyAT}_fullcost');
      await prefs.remove(_cacheTimestampKeyDE);
      await prefs.remove('${_cacheTimestampKeyDE}_fullcost');

      print('[Cache] Cleared all caches (both markets, both Full Cost modes)');
    }
  }

  /// Force clear all caches (for debugging)
  Future<void> clearAllCaches() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear both markets, both Full Cost modes
    await prefs.remove(_cacheKeyAT);
    await prefs.remove('${_cacheKeyAT}_fullcost');
    await prefs.remove(_cacheKeyDE);
    await prefs.remove('${_cacheKeyDE}_fullcost');
    await prefs.remove(_cacheTimestampKeyAT);
    await prefs.remove('${_cacheTimestampKeyAT}_fullcost');
    await prefs.remove(_cacheTimestampKeyDE);
    await prefs.remove('${_cacheTimestampKeyDE}_fullcost');

    // Also remove any legacy keys that might still exist
    await prefs.remove('price_cache');
    await prefs.remove('price_cache_timestamp');

    print('[Cache] All caches cleared (including Full Cost modes)');
  }

  /// Check and update cache for market switch (only if needed)
  Future<void> ensureCacheForMarket(String market) async {
    final (cacheKey, _) = await _getCacheKeys(market);
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
    final (_, timestampKey) = await _getCacheKeys(marketToCheck);
    final timestamp = prefs.getInt(timestampKey);

    if (timestamp == null) return null;

    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(cacheTime);
  }
}