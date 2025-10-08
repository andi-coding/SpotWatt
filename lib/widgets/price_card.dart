import 'package:flutter/material.dart';
import '../utils/price_utils.dart';
import '../models/price_data.dart';

class CurrentPriceCard extends StatelessWidget {
  final double currentPrice;
  final double minPrice;
  final double maxPrice;
  final List<PriceData> allPrices;

  const CurrentPriceCard({
    Key? key,
    required this.currentPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.allPrices,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aktueller Strompreis',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        PriceUtils.formatPrice(currentPrice),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: PriceUtils.getPriceColorMedian(currentPrice, allPrices),
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Gültig bis ${DateTime.now().hour + 1}:00 Uhr',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  PriceUtils.getPriceIconQuartile(currentPrice, allPrices),
                  color: PriceUtils.getPriceColorMedian(currentPrice, allPrices),
                  size: 32,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MinMaxPriceCards extends StatelessWidget {
  final double minPrice;
  final double maxPrice;
  final DateTime? cheapestTime;
  final DateTime? expensiveTime;

  const MinMaxPriceCards({
    Key? key,
    required this.minPrice,
    required this.maxPrice,
    this.cheapestTime,
    this.expensiveTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      children: [
        Expanded(
          child: Card(
            color: isDarkMode 
              ? Colors.green.withOpacity(0.1)
              : Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.arrow_downward, 
                    color: isDarkMode ? Colors.green.shade300 : Colors.green,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tagesminimum',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDarkMode 
                        ? Colors.white.withOpacity(0.9)
                        : null,
                    ),
                  ),
                  Text(
                    PriceUtils.formatPrice(minPrice),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isDarkMode ? Colors.green.shade300 : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (cheapestTime != null)
                    Text(
                      '${cheapestTime!.hour}:${cheapestTime!.minute.toString().padLeft(2, '0')} Uhr',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDarkMode 
                          ? Colors.white.withOpacity(0.7)
                          : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            color: isDarkMode 
              ? Colors.red.withOpacity(0.1)
              : Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.arrow_upward, 
                    color: isDarkMode ? Colors.red.shade300 : Colors.red,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tagesmaximum',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDarkMode 
                        ? Colors.white.withOpacity(0.9)
                        : null,
                    ),
                  ),
                  Text(
                    PriceUtils.formatPrice(maxPrice),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isDarkMode ? Colors.red.shade300 : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (expensiveTime != null)
                    Text(
                      '${expensiveTime!.hour}:${expensiveTime!.minute.toString().padLeft(2, '0')} Uhr',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDarkMode 
                          ? Colors.white.withOpacity(0.7)
                          : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}