import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/price_data.dart';
import 'awattar_service.dart';

class CloudflarePriceService {
  // CloudFlare Worker URL
  static const String WORKER_URL = 'https://spotwatt-prices.spotwatt-api.workers.dev';

  /// Fetch prices from CloudFlare Worker
  static Future<List<PriceData>> fetchPrices({
    required PriceMarket market,
  }) async {
    final marketCode = market == PriceMarket.austria ? 'AT' : 'DE';

    try {
      final response = await http.get(
        Uri.parse('$WORKER_URL?market=$marketCode'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch prices: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      // Parse prices from CloudFlare Worker response
      final prices = (data['prices'] as List).map((item) => PriceData(
        startTime: DateTime.parse(item['startTime']),
        endTime: DateTime.parse(item['endTime']),
        price: item['price'].toDouble(),
      )).toList();

      return prices;
    } catch (e) {
      print('[CloudFlare] Error fetching prices: $e');
      rethrow; // Throw error to caller
    }
  }
}