import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/price_data.dart';
import '../utils/price_utils.dart';

class PriceChart extends StatelessWidget {
  final List<PriceData> prices;
  final List<PriceData> allPricesForColors;

  const PriceChart({
    Key? key, 
    required this.prices,
    required this.allPricesForColors,
  }) : super(key: key);

  double _calculateYInterval(double range) {
    // Calculate appropriate interval with nice round numbers
    if (range <= 2) return 0.5;      // Small range: 0.5ct increments
    if (range <= 5) return 1.0;      // Small-medium range: 1ct increments  
    if (range <= 10) return 2.0;     // Medium range: 2ct increments
    if (range <= 25) return 5.0;     // Larger range: 5ct increments
    if (range <= 50) return 10.0;    // Big range: 10ct increments
    return 20.0;                     // Very large range: 20ct increments
  }

  @override
  Widget build(BuildContext context) {
    if (prices.isEmpty) return const SizedBox();
    
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final spots = prices.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();
    
    final minY = prices.map((p) => p.price).reduce((a, b) => a < b ? a : b);
    final maxY = prices.map((p) => p.price).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        minY: minY - padding,
        maxY: maxY + padding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          horizontalInterval: _calculateYInterval(maxY - minY),
          verticalInterval: 3,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.1) 
                : Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: isDarkMode 
                ? Colors.white.withOpacity(0.1) 
                : Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              'Preis: ct/kWh',
              style: TextStyle(
                color: isDarkMode ? Colors.white54 : Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            axisNameSize: 16,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: _calculateYInterval(maxY - minY),
              getTitlesWidget: (value, meta) {
                final interval = _calculateYInterval(maxY - minY);
                
                // Only show labels that are nice round numbers according to our interval
                final remainder = value % interval;
                if (remainder.abs() > 0.01) {  // Not a clean multiple of our interval
                  return const SizedBox.shrink();
                }
                
                // Y-Labels: Show clean multiples of interval
                
                // Avoid labels too close to chart edges
                final chartMin = minY - padding;
                final chartMax = maxY + padding;
                final edgeMargin = interval * 0.1; // Reduced from 0.3 to 0.1
                
                if (value < chartMin + edgeMargin || value > chartMax - edgeMargin) {
                  return const SizedBox.shrink();
                }
                
                // Format with one decimal place for consistency
                String label = value.toStringAsFixed(1);
                
                return Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: Text(
              'Uhrzeit',
              style: TextStyle(
                color: isDarkMode ? Colors.white54 : Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            axisNameSize: 16,
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < prices.length) {
                  final index = value.toInt();
                  final price = prices[index];
                  final hour = price.startTime.hour;
                  final now = DateTime.now();
                  final isToday = price.startTime.day == now.day && 
                                  price.startTime.month == now.month && 
                                  price.startTime.year == now.year;
                  
                  // Check if this is the first entry of tomorrow
                  bool isDayBoundary = false;
                  if (!isToday && index > 0) {
                    final prevPrice = prices[index - 1];
                    final prevIsToday = prevPrice.startTime.day == now.day && 
                                       prevPrice.startTime.month == now.month && 
                                       prevPrice.startTime.year == now.year;
                    isDayBoundary = prevIsToday;
                  } else if (!isToday && index == 0) {
                    // First entry is already tomorrow
                    isDayBoundary = true;
                  }

                  // Always show the day boundary with subtle emphasis
                  if (isDayBoundary) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 1.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '0h',
                            style: TextStyle(
                              fontSize: 12, // Etwas größer
                              fontWeight: FontWeight.bold, // Fetter
                              height: 1.0,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Morgen',
                            style: TextStyle(
                              fontSize: 9,
                              height: 0.9,
                              color: Colors.blue.withOpacity(0.7), // Dezenter
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  // Check if there's a 0h day boundary anywhere in the data
                  bool hasDayBoundary = prices.any((p) => 
                    p.startTime.hour == 0 && 
                    (p.startTime.day != now.day || p.startTime.month != now.month || p.startTime.year != now.year)
                  );
                  
                  // If we have a day boundary, skip 23h and 1h labels to avoid crowding around 0h
                  if (hasDayBoundary && (hour == 23 || hour == 1)) {
                    return const SizedBox.shrink();
                  }
                  
                  // Show every 3 hours based on actual hour, not index
                  if (hour % 3 != 0) {
                    return const SizedBox.shrink();
                  }

                  // Normal hours display
                  return Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      '${hour}h',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.0,
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  );
                }

                // Kein gültiger Preiswert
                return const SizedBox.shrink();
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: isDarkMode ? Colors.white24 : Colors.black26,
              width: 1,
            ),
            left: BorderSide(
              color: isDarkMode ? Colors.white24 : Colors.black26,
              width: 1,
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,  // Tooltip bleibt im sichtbaren Bereich
            fitInsideVertically: true,    // Auch vertikal anpassen
            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
              return touchedBarSpots.map((barSpot) {
                final flSpot = barSpot;
                if (flSpot.x.toInt() >= 0 && flSpot.x.toInt() < prices.length) {
                  final price = prices[flSpot.x.toInt()];
                  final time = '${price.startTime.hour}:00 - ${price.endTime.hour}:00';
                  return LineTooltipItem(
                    '$time\n${PriceUtils.formatPrice(price.price)}',
                    TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  );
                }
                return null;
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: Colors.green,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                Color dotColor;
                if (index < prices.length) {
                  final priceData = prices[index];
                  // Use all available prices for stable color calculation, not just future prices
                  // This prevents colors from jumping as hours pass
                  // Fallback to display prices if allPricesForColors is empty
                  final pricesForColorCalc = allPricesForColors.isNotEmpty ? allPricesForColors : prices;
                  dotColor = PriceUtils.getPriceColorMedian(priceData.price, pricesForColorCalc);
                  
                  // Color calculation using median ±15% for stable colors across all price data
                } else {
                  dotColor = Colors.green;
                }
                
                return FlDotCirclePainter(
                  radius: 4,
                  color: dotColor,
                  strokeWidth: 2,
                  strokeColor: isDarkMode ? Colors.black : Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.green.withOpacity(0.3),
                  Colors.green.withOpacity(0.1),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        extraLinesData: ExtraLinesData(
          verticalLines: prices.asMap().entries
            .where((entry) {
              final index = entry.key;
              final price = entry.value;
              final now = DateTime.now();
              
              // Nur 0h-Stunden prüfen
              if (price.startTime.hour != 0) return false;
              
              // Wenn es die erste Stunde in den Daten ist, prüfen ob es morgen ist
              if (index == 0) {
                return price.startTime.day != now.day ||
                       price.startTime.month != now.month ||
                       price.startTime.year != now.year;
              }
              
              // Prüfen ob es einen Tageswechsel gibt (vorherige Stunde war heute, diese ist morgen)
              final prevPrice = prices[index - 1];
              final prevIsToday = prevPrice.startTime.day == now.day &&
                                 prevPrice.startTime.month == now.month &&
                                 prevPrice.startTime.year == now.year;
              final currentIsToday = price.startTime.day == now.day &&
                                    price.startTime.month == now.month &&
                                    price.startTime.year == now.year;
              
              // Tagesgrenze: vorherige Stunde war heute, aktuelle ist nicht heute
              return prevIsToday && !currentIsToday;
            })
            .map((entry) => VerticalLine(
              x: entry.key.toDouble(),
              color: isDarkMode 
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
              strokeWidth: 1.5,
              dashArray: [4, 4],
            ))
            .toList(),
        ),
      ),
    );
  }
}