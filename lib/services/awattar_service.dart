import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/price_data.dart';

enum PriceMarket {
  austria('AT', 'Österreich', 'https://api.awattar.at/v1/marketdata'),
  germany('DE', 'Deutschland', 'https://api.awattar.de/v1/marketdata');

  final String code;
  final String displayName;
  final String apiUrl;
  
  const PriceMarket(this.code, this.displayName, this.apiUrl);
}

class AwattarService {
  Future<PriceMarket> getSelectedMarket() async {
    final prefs = await SharedPreferences.getInstance();
    final marketCode = prefs.getString('price_market') ?? 'AT';
    return PriceMarket.values.firstWhere(
      (m) => m.code == marketCode,
      orElse: () => PriceMarket.austria,
    );
  }

  Future<List<PriceData>> fetchPrices() async {
    final market = await getSelectedMarket();
    final now = DateTime.now();
    // WICHTIG: Immer ab Tagesbeginn abfragen, damit wir die kompletten Tagespreise haben
    // für korrekte Min/Max Berechnung
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0);
    final end = DateTime(now.year, now.month, now.day + 2);

    final url = Uri.parse('${market.apiUrl}?start=${startOfDay.millisecondsSinceEpoch}&end=${end.millisecondsSinceEpoch}');
    
    debugPrint('Fetching prices from ${market.displayName} market: ${startOfDay.toIso8601String()} to ${end.toIso8601String()}');
    
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