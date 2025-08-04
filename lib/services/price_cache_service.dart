import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/price_data.dart';
import 'awattar_service.dart';

class PriceCacheService {
  static const String _cacheKey = 'price_cache';
  static const String _cacheTimestampKey = 'price_cache_timestamp';
  static const Duration _cacheValidity = Duration(hours: 6); // Cache für 6 Stunden gültig
  
  final AwattarService _awattarService = AwattarService();
  
  /// Lädt Preise aus Cache oder API
  /// Nutzt Cache wenn:
  /// - Cache vorhanden und nicht älter als 6 Stunden
  /// - Cache enthält Preise für heute und morgen (falls nach 13:00)
  Future<List<PriceData>> getPrices({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedPrices = await _loadFromCache();
      if (cachedPrices != null && await _isCacheValid(cachedPrices)) {
        return cachedPrices;
      }
    }
    
    // Cache ungültig oder forceRefresh - neue Preise laden
    final prices = await _awattarService.fetchPrices();
    await _saveToCache(prices);
    return prices;
  }
  
  /// Prüft ob Cache noch gültig ist
  Future<bool> _isCacheValid(List<PriceData> prices) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_cacheTimestampKey);
    
    if (timestamp == null) return false;
    
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    
    // Cache zu alt?
    if (now.difference(cacheTime) > _cacheValidity) return false;
    
    // Haben wir Preise für heute?
    final hasToday = prices.any((p) => p.startTime.day == now.day);
    if (!hasToday) return false;
    
    // Nach 13:00 sollten wir auch Morgen-Preise haben
    if (now.hour >= 13) {
      final hasTomorrow = prices.any((p) => p.startTime.day == now.day + 1);
      if (!hasTomorrow) return false;
    }
    
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