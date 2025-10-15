import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/energy_provider.dart';

/// Service to fetch and cache energy provider data from API
class EnergyProviderService {
  static final EnergyProviderService _instance = EnergyProviderService._internal();
  factory EnergyProviderService() => _instance;
  EnergyProviderService._internal();

  static const String _apiUrl = 'https://spotwatt-prices.spotwatt-api.workers.dev/providers';
  static const Duration _cacheDuration = Duration(days: 1); // 1 day cache

  /// Get provider data for a specific region (with 1-day cache)
  Future<ProviderDataResponse> getProviders(String region) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'provider_data_$region';
    final timestampKey = '${cacheKey}_timestamp';

    // 1. Check cache
    final cached = prefs.getString(cacheKey);
    final lastUpdate = prefs.getInt(timestampKey);

    if (cached != null && lastUpdate != null) {
      final age = DateTime.now().millisecondsSinceEpoch - lastUpdate;
      if (age < _cacheDuration.inMilliseconds) {
        debugPrint('[Providers] Using cached data for $region (${(age / 86400000).toStringAsFixed(1)} days old)');
        return ProviderDataResponse.fromJson(jsonDecode(cached));
      }
    }

    // 2. Fetch from API
    debugPrint('[Providers] Fetching from API for $region...');
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl?region=$region'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final providerData = ProviderDataResponse.fromJson(jsonDecode(response.body));

        // Save to cache
        await prefs.setString(cacheKey, response.body);
        await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

        // Save tax rate separately for fast access (used by FullCostCalculator)
        await prefs.setDouble('tax_rate_$region', providerData.taxRate);

        debugPrint('[Providers] ✅ Cached provider data for $region');
        return providerData;
      } else {
        throw Exception('API returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[Providers] ❌ API call failed: $e');

      // 3. Fallback to stale cache if API fails
      if (cached != null) {
        debugPrint('[Providers] Using stale cache as fallback');
        return ProviderDataResponse.fromJson(jsonDecode(cached));
      }

      // 4. No cache available - throw error
      throw Exception('Failed to load provider data and no cache available');
    }
  }

  /// Force refresh (clear cache and fetch fresh data)
  Future<ProviderDataResponse> forceRefresh(String region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('provider_data_$region');
    await prefs.remove('provider_data_${region}_timestamp');
    await prefs.remove('tax_rate_$region');
    return getProviders(region);
  }
}
