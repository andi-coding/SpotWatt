import 'package:flutter/material.dart';
import '../utils/price_utils.dart';

class CurrentPriceCard extends StatelessWidget {
  final double currentPrice;
  final double minPrice;
  final double maxPrice;

  const CurrentPriceCard({
    Key? key,
    required this.currentPrice,
    required this.minPrice,
    required this.maxPrice,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PriceUtils.formatPrice(currentPrice),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: PriceUtils.getPriceColor(currentPrice, minPrice, maxPrice),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Gültig bis ${DateTime.now().hour + 1}:00 Uhr',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                Icon(
                  PriceUtils.getPriceIcon(currentPrice, minPrice, maxPrice),
                  color: PriceUtils.getPriceColor(currentPrice, minPrice, maxPrice),
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
    return Row(
      children: [
        Expanded(
          child: Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.arrow_downward, color: Colors.green),
                  const SizedBox(height: 8),
                  Text(
                    'Tagesminimum',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    PriceUtils.formatPrice(minPrice),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (cheapestTime != null)
                    Text(
                      '${cheapestTime!.hour}:${cheapestTime!.minute.toString().padLeft(2, '0')} Uhr',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.arrow_upward, color: Colors.red),
                  const SizedBox(height: 8),
                  Text(
                    'Tagesmaximum',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    PriceUtils.formatPrice(maxPrice),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (expensiveTime != null)
                    Text(
                      '${expensiveTime!.hour}:${expensiveTime!.minute.toString().padLeft(2, '0')} Uhr',
                      style: Theme.of(context).textTheme.bodySmall,
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