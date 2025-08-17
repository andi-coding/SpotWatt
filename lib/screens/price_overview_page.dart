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
  DateTime? expensiveTime;
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
        final now = DateTime.now();
        final currentHour = DateTime(now.year, now.month, now.day, now.hour);
        
        // Filter out past hours - only keep current hour and future hours
        prices = fetchedPrices.where((price) => 
          price.startTime.isAtSameMomentAs(currentHour) || 
          price.startTime.isAfter(currentHour)
        ).toList();
        
        isLoading = false;
        
        if (prices.isNotEmpty) {
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
          
          final expensive = prices.reduce((a, b) => a.price > b.price ? a : b);
          expensiveTime = expensive.startTime;
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
    
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    
    // Only consider current and future prices
    final futurePrices = prices.where((price) => 
      price.startTime.isAtSameMomentAs(currentHour) || 
      price.startTime.isAfter(currentHour)
    ).toList();
    
    final sorted = List<PriceData>.from(futurePrices)
      ..sort((a, b) => a.price.compareTo(b.price));
    
    return sorted.take(3).toList();
  }
  
  String _getChartTitle() {
    if (prices.isEmpty) return 'Preisverlauf';
    
    final now = DateTime.now();
    final hasTomorrow = prices.any((p) => p.startTime.day != now.day);
    
    if (hasTomorrow) {
      // Check if we only have tomorrow's prices
      final hasToday = prices.any((p) => p.startTime.day == now.day);
      if (!hasToday) {
        return 'Preisverlauf (Morgen)';
      }
      return 'Preisverlauf (Heute & Morgen)';
    }
    return 'Preisverlauf (Heute)';
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
                      expensiveTime: expensiveTime,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _getChartTitle(),
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
                    ...getBestTimes().map((time) {
                      final isToday = time.startTime.day == DateTime.now().day;
                      final dayText = isToday ? 'Heute' : 'Morgen';
                      final timeText = isToday 
                        ? '${time.startTime.hour}:00 - ${time.endTime.hour}:00 Uhr'
                        : '${time.startTime.hour}:00 - ${time.endTime.hour}:00 Uhr (Morgen)';
                      
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isToday ? Colors.green : Colors.blue,
                            child: Text(
                              dayText,
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                          title: Text(timeText),
                          subtitle: Text(PriceUtils.formatPrice(time.price)),
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
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
    );
  }
}