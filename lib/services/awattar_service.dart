import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/price_data.dart';

class AwattarService {
  static const String baseUrl = 'https://api.awattar.at/v1/marketdata';

  Future<List<PriceData>> fetchPrices() async {
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final end = DateTime(now.year, now.month, now.day + 2);

    final url = Uri.parse('$baseUrl?start=${currentHour.millisecondsSinceEpoch}&end=${end.millisecondsSinceEpoch}');
    
    debugPrint('Fetching prices from: ${currentHour.toIso8601String()} to ${end.toIso8601String()}');
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> priceList = data['data'];
        
        debugPrint('Received ${priceList.length} price entries');
        
        final allPrices = priceList.map((item) => PriceData.fromJson(item)).toList();
        
        if (allPrices.isNotEmpty) {
          debugPrint('First price: ${allPrices.first.startTime} - ${allPrices.first.endTime}');
          debugPrint('Current time: $now');
        }
        
        return allPrices;
      } else {
        throw Exception('Failed to load prices: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching prices: $e');
    }
  }
}