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

class _PriceOverviewPageState extends State<PriceOverviewPage> with WidgetsBindingObserver {
  List<PriceData> prices = [];
  List<PriceData> allPricesForColors = []; // All available prices for stable color calculations
  bool isLoading = true;
  double currentPrice = 0.0;
  double minPrice = 0.0;
  double maxPrice = 0.0;
  DateTime? cheapestTime;
  DateTime? expensiveTime;
  Timer? _refreshTimer;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadPrices();
    // Aktualisiere jede Minute um vergangene Stunden aus dem Graph zu entfernen
    // und den aktuellen Preis neu zu berechnen (kein API-Call, nur Cache)
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      loadPrices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _appLifecycleState = state;
    });
    print('[PriceOverview] App lifecycle state changed to: $state');
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    // Network errors - most common
    if (errorStr.contains('socketexception') || 
        errorStr.contains('failed host lookup') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('timeoutexception') ||
        errorStr.contains('clientexception') ||
        errorStr.contains('httpexception')) {
      return 'Keine Internetverbindung verfügbar. Bitte WiFi oder Mobile Daten aktivieren.';
    }
    
    // Our custom network exception
    if (errorStr.contains('internetverbindung')) {
      return error.toString().replaceAll('NetworkException: ', '').replaceAll('Exception: ', '');
    }
    
    // Data/parsing errors
    if (errorStr.contains('formatexception') ||
        errorStr.contains('json') ||
        errorStr.contains('cast') ||
        errorStr.contains('null check')) {
      return 'Die Preisdaten konnten nicht gelesen werden. Versuchen Sie es später erneut.';
    }
    
    // Generic fallback - never show technical errors
    return 'Ein unerwarteter Fehler ist aufgetreten. Bitte versuchen Sie es später erneut.';
  }

  Future<void> loadPrices() async {
    try {
      final priceCacheService = PriceCacheService();
      final fetchedPrices = await priceCacheService.getPrices();
      
      setState(() {
        final now = DateTime.now();
        final currentHour = DateTime(now.year, now.month, now.day, now.hour);
        
        // Filter out past hours - only keep current hour and future hours for display
        prices = fetchedPrices.where((price) => 
          price.startTime.isAtSameMomentAs(currentHour) || 
          price.startTime.isAfter(currentHour)
        ).toList();
        
        // Keep all fetched prices for stable color calculations
        allPricesForColors = fetchedPrices;
        
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
          
          // Calculate min/max ONLY for today (full 24 hours)
          // This ensures values stay constant throughout the day
          final todayFullPrices = PriceUtils.getFullDayPrices(fetchedPrices, now);
          
          if (todayFullPrices.isNotEmpty) {
            // Use today's full day prices for min/max
            minPrice = todayFullPrices.map((p) => p.price).reduce((a, b) => a < b ? a : b);
            maxPrice = todayFullPrices.map((p) => p.price).reduce((a, b) => a > b ? a : b);
            
            final cheapest = todayFullPrices.reduce((a, b) => a.price < b.price ? a : b);
            cheapestTime = cheapest.startTime;
            
            final expensive = todayFullPrices.reduce((a, b) => a.price > b.price ? a : b);
            expensiveTime = expensive.startTime;
          } else {
            // Fallback: if no today prices, use all available prices
            minPrice = prices.map((p) => p.price).reduce((a, b) => a < b ? a : b);
            maxPrice = prices.map((p) => p.price).reduce((a, b) => a > b ? a : b);
            
            final cheapest = prices.reduce((a, b) => a.price < b.price ? a : b);
            cheapestTime = cheapest.startTime;
            
            final expensive = prices.reduce((a, b) => a.price > b.price ? a : b);
            expensiveTime = expensive.startTime;
          }
        }
      });
    } catch (e, stackTrace) {
      setState(() {
        isLoading = false;
      });
      // Detailed error logging
      print('[PriceOverview] Error in loadPrices(): $e');
      print('[PriceOverview] StackTrace: $stackTrace');
      // Only show error if app is in foreground
      if (mounted && _appLifecycleState == AppLifecycleState.resumed) {
        final message = _getErrorMessage(e);
        final isNetworkError = message.contains('Internetverbindung') || 
                              message.contains('WiFi') ||
                              message.contains('Mobile Daten');
        
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                if (isNetworkError) ...[
                  SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => loadPrices(),
                      child: Text(
                        'Erneut versuchen',
                        style: TextStyle(
                          color: isDarkMode ? Colors.blue[300] : Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            backgroundColor: isDarkMode 
                ? Colors.grey[800] 
                : Colors.grey[100],
            duration: Duration(seconds: 5),
            action: null, // No action needed anymore
          ),
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
    
    // Sort by price to find the 3 cheapest
    final sortedByPrice = List<PriceData>.from(futurePrices)
      ..sort((a, b) => a.price.compareTo(b.price));
    
    // Take the 3 cheapest, then sort them chronologically
    final cheapest3 = sortedByPrice.take(3).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    
    return cheapest3;
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
            onPressed: () => loadPrices(),
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
                      allPrices: allPricesForColors,
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
                      height: 220,
                      child: PriceChart(
                        prices: prices,
                        allPricesForColors: allPricesForColors,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Günstigste Zeiten in den nächsten Stunden',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    ...getBestTimes().map((time) {
                      final now = DateTime.now();
                      final isToday = time.startTime.day == now.day;
                      final dayText = isToday ? 'Heute' : 'Morgen';
                      final timeText = isToday
                        ? '${time.startTime.hour}:00 - ${time.endTime.hour}:00 Uhr'
                        : '${time.startTime.hour}:00 - ${time.endTime.hour}:00 Uhr (Morgen)';

                      // Calculate time difference
                      final difference = time.startTime.difference(now);
                      final hours = difference.inHours;
                      final minutes = difference.inMinutes;

                      // Determine display text
                      String timeUntilText;
                      if (time.startTime.hour == now.hour && time.startTime.day == now.day) {
                        // Current hour
                        timeUntilText = 'Jetzt';
                      } else if (hours == 0) {
                        // Less than 1 hour
                        timeUntilText = 'in ${minutes}min';
                      } else {
                        // 1 or more hours
                        timeUntilText = 'in ${hours}h';
                      }

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
                                timeUntilText,
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