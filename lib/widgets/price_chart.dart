import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/price_data.dart';

class PriceChart extends StatelessWidget {
  final List<PriceData> prices;

  const PriceChart({Key? key, required this.prices}) : super(key: key);

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
          horizontalInterval: (maxY - minY) / 5,
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
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < prices.length) {
                  final price = prices[value.toInt()];
                  final hour = price.startTime.hour;
                  final isToday = price.startTime.day == DateTime.now().day;

                  // Spezialfall: Mit zusätzlichem Text ("Morgen")
                  if (hour == 0 && !isToday) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${hour}h',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              height: 1.0,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            'Morgen',
                            style: TextStyle(
                              fontSize: 8.5,
                              height: 1.0,
                              color: isDarkMode ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Standardfall: Nur Stunde
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
            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
              return touchedBarSpots.map((barSpot) {
                final flSpot = barSpot;
                if (flSpot.x.toInt() >= 0 && flSpot.x.toInt() < prices.length) {
                  final price = prices[flSpot.x.toInt()];
                  final time = '${price.startTime.hour}:00 - ${price.endTime.hour}:00';
                  return LineTooltipItem(
                    '$time\n${price.price.toStringAsFixed(2)} ct/kWh',
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
                final priceRange = maxY - minY;
                final relativePrice = (spot.y - minY) / priceRange;
                
                if (relativePrice < 0.33) {
                  dotColor = Colors.green;
                } else if (relativePrice < 0.66) {
                  dotColor = Colors.orange;
                } else {
                  dotColor = Colors.red;
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
      ),
    );
  }
}