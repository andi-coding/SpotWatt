import 'package:flutter/material.dart';
import 'dart:async';
import '../models/price_data.dart';
import '../services/price_cache_service.dart';
import '../widgets/price_chart.dart';
import '../widgets/price_card.dart';
import '../utils/price_utils.dart';

class PriceOverviewPage extends StatefulWidget {
  const PriceOverviewPage({Key? key}) : super(key: key);

  @override
  State<PriceOverviewPage> createState() => _PriceOverviewPageState();
}

class _PriceOverviewPageState extends State<PriceOverviewPage> {
  List<PriceData> prices = [];
  bool isLoading = true;
  double currentPrice = 0.0;
  double minPrice = 0.0;
  double maxPrice = 0.0;
  DateTime? cheapestTime;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    loadPrices();
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      loadPrices();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadPrices({bool forceRefresh = false}) async {
    try {
      final priceCacheService = PriceCacheService();
      final fetchedPrices = await priceCacheService.getPrices(forceRefresh: forceRefresh);
      
      setState(() {
        prices = fetchedPrices;
        isLoading = false;
        
        if (prices.isNotEmpty) {
          final now = DateTime.now();
          final currentHour = DateTime(now.year, now.month, now.day, now.hour);
          
          try {
            final currentPriceData = prices.firstWhere(
              (price) => price.startTime.isAtSameMomentAs(currentHour) ||
                        (price.startTime.isBefore(now) && price.endTime.isAfter(now))
            );
            currentPrice = currentPriceData.price;
          } catch (e) {
            currentPrice = prices.first.price;
            debugPrint('No current price found, using next price');
          }
          
          minPrice = prices.map((p) => p.price).reduce((a, b) => a < b ? a : b);
          maxPrice = prices.map((p) => p.price).reduce((a, b) => a > b ? a : b);
          
          final cheapest = prices.reduce((a, b) => a.price < b.price ? a : b);
          cheapestTime = cheapest.startTime;
        }
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Preise: $e')),
        );
      }
    }
  }

  List<PriceData> getBestTimes() {
    if (prices.isEmpty) return [];
    
    final sorted = List<PriceData>.from(prices)
      ..sort((a, b) => a.price.compareTo(b.price));
    
    return sorted.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strompreise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => loadPrices(forceRefresh: true),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadPrices,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CurrentPriceCard(
                      currentPrice: currentPrice,
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                    ),
                    const SizedBox(height: 16),
                    MinMaxPriceCards(
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                      cheapestTime: cheapestTime,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Preisverlauf (bis morgen)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: PriceChart(prices: prices),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Günstigste Zeiten in den nächsten Stunden',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    ...getBestTimes().map((time) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Text(
                            time.startTime.day == DateTime.now().day ? 'Heute' : 'Morgen',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                        title: Text(
                          '${time.startTime.hour}:00 - ${time.endTime.hour}:00 Uhr',
                        ),
                        subtitle: Text('${time.price.toStringAsFixed(2)} ct/kWh'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time, size: 16),
                            Text(
                              'in ${time.startTime.difference(DateTime.now()).inHours}h',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                  ],
                ),
              ),
            ),
    );
  }
}