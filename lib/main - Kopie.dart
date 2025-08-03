import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  final String timeZoneName = 'Europe/Vienna'; // Für Österreich
  tz.setLocalLocation(tz.getLocation(timeZoneName));
  runApp(const StrompreisApp());
}

class StrompreisApp extends StatelessWidget {
  const StrompreisApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Strompreis Monitor',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _pages = [
    const PriceOverviewPage(),
    const DevicesPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.euro),
            label: 'Preise',
          ),
          NavigationDestination(
            icon: Icon(Icons.power),
            label: 'Geräte',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Einstellungen',
          ),
        ],
      ),
    );
  }
}

// Strompreis-Übersicht
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

  @override
  void initState() {
    super.initState();
    loadPrices();
    // Aktualisiere Preise alle 30 Minuten
    Timer.periodic(const Duration(minutes: 30), (timer) {
      loadPrices();
    });
  }

  Future<void> loadPrices() async {
    try {
      final awattarService = AwattarService();
      final fetchedPrices = await awattarService.fetchPrices();
      
      setState(() {
        prices = fetchedPrices;
        isLoading = false;
        
        if (prices.isNotEmpty) {
          // Finde den aktuellen Preis
          final now = DateTime.now();
          final currentHour = DateTime(now.year, now.month, now.day, now.hour);
          
          // Suche den Preis für die aktuelle Stunde
          try {
            final currentPriceData = prices.firstWhere(
              (price) => price.startTime.isAtSameMomentAs(currentHour) ||
                        (price.startTime.isBefore(now) && price.endTime.isAfter(now))
            );
            currentPrice = currentPriceData.price;
          } catch (e) {
            // Falls kein aktueller Preis gefunden wird, nimm den nächsten
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strompreise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadPrices,
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
                    // Aktuelle Preis-Karte
                    Card(
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
                                      '${currentPrice.toStringAsFixed(2)} ct/kWh',
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        color: _getPriceColor(currentPrice),
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
                                  _getPriceIcon(currentPrice),
                                  color: _getPriceColor(currentPrice),
                                  size: 32,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Min/Max Preise
                    Row(
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
                                    'Niedrigster Preis',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    '${minPrice.toStringAsFixed(2)} ct/kWh',
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
                                    'Höchster Preis',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    '${maxPrice.toStringAsFixed(2)} ct/kWh',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Preis-Chart
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
                    
                    // Beste Zeiten
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

  Color _getPriceColor(double price) {
    final range = maxPrice - minPrice;
    final relative = (price - minPrice) / range;
    
    if (relative < 0.33) return Colors.green;
    if (relative < 0.66) return Colors.orange;
    return Colors.red;
  }

  IconData _getPriceIcon(double price) {
    final range = maxPrice - minPrice;
    final relative = (price - minPrice) / range;
    
    if (relative < 0.33) return Icons.lightbulb; // Glühbirne für günstig
    if (relative < 0.66) return Icons.schedule; // Uhr für mittel (warten)
    return Icons.warning_amber; // Warnung für teuer
  }

  List<PriceData> getBestTimes() {
    if (prices.isEmpty) return [];
    
    final sorted = List<PriceData>.from(prices)
      ..sort((a, b) => a.price.compareTo(b.price));
    
    return sorted.take(3).toList();
  }
}

// Preis-Chart Widget
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
    
    // Min und Max für bessere Skalierung
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
                  final hour = prices[value.toInt()].startTime.hour;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '${hour}h',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                return const Text('');
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
                // Farbe basierend auf dem Preisniveau
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

// Geräte-Seite
class DevicesPage extends StatefulWidget {
  const DevicesPage({Key? key}) : super(key: key);

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<SmartDevice> devices = [];
  List<ShellyDevice> shellyDevices = [];
  bool isLoadingShelly = false;
  final shellyService = ShellyService();

  @override
  void initState() {
    super.initState();
    loadDevices();
    _loadShellyDevices();
  }

  void loadDevices() {
    // Beispiel-Geräte - später aus SharedPreferences laden
    setState(() {
      devices = [
        SmartDevice(
          id: '1',
          name: 'Waschmaschine',
          type: DeviceType.washer,
          shellyId: '',
          isAutomated: true,
          targetPrice: 15.0,
        ),
        SmartDevice(
          id: '2',
          name: 'Geschirrspüler',
          type: DeviceType.dishwasher,
          shellyId: '',
          isAutomated: false,
          targetPrice: 12.0,
        ),
      ];
    });
  }

  Future<void> _loadShellyDevices() async {
    setState(() => isLoadingShelly = true);
    
    if (await shellyService.loadCredentials()) {
      try {
        final devices = await shellyService.getDevices();
        setState(() {
          shellyDevices = devices;
          isLoadingShelly = false;
        });
      } catch (e) {
        setState(() => isLoadingShelly = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler beim Laden der Shelly-Geräte: $e')),
          );
        }
      }
    } else {
      setState(() => isLoadingShelly = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Geräte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShellyDevices,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Automatisierte Geräte
          Text(
            'Automatisierte Geräte',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...devices.map((device) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: device.isAutomated ? Colors.green : Colors.grey,
                child: Icon(
                  device.getIcon(),
                  color: Colors.white,
                ),
              ),
              title: Text(device.name),
              subtitle: Text(
                device.isAutomated 
                  ? 'Automatisch bei < ${device.targetPrice.toStringAsFixed(2)} ct/kWh'
                  : 'Manuell',
              ),
              trailing: Switch(
                value: device.isAutomated,
                onChanged: (value) {
                  setState(() {
                    device.isAutomated = value;
                  });
                },
              ),
              onTap: () {
                _showDeviceSettings(device);
              },
            ),
          )).toList(),
          
          const SizedBox(height: 24),
          
          // Shelly Geräte
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Shelly Geräte',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (isLoadingShelly)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          
          if (shellyDevices.isEmpty && !isLoadingShelly)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.power_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('Keine Shelly-Geräte gefunden'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsPage(),
                          ),
                        );
                      },
                      child: const Text('Mit Shelly Cloud verbinden'),
                    ),
                  ],
                ),
              ),
            ),
          
          ...shellyDevices.map((device) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: device.isOnline 
                  ? (device.isOn ? Colors.green : Colors.grey)
                  : Colors.red,
                child: Icon(
                  Icons.power,
                  color: Colors.white,
                ),
              ),
              title: Text(device.name),
              subtitle: Text(
                device.isOnline 
                  ? (device.isOn ? 'Eingeschaltet' : 'Ausgeschaltet')
                  : 'Offline',
              ),
              trailing: Switch(
                value: device.isOn,
                onChanged: device.isOnline ? (value) async {
                  setState(() {
                    device.isOn = value;
                  });
                  
                  final success = await shellyService.toggleDevice(device.id, value);
                  if (!success && mounted) {
                    // Revert on failure
                    setState(() {
                      device.isOn = !value;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fehler beim Schalten des Geräts')),
                    );
                  }
                } : null,
              ),
            ),
          )).toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDevice,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDeviceSettings(SmartDevice device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Shelly ID',
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: device.shellyId),
              ),
              const SizedBox(height: 16),
              Text('Zielpreis: ${device.targetPrice.toStringAsFixed(2)} ct/kWh'),
              Slider(
                value: device.targetPrice,
                min: 0,
                max: 50,
                divisions: 50,
                label: device.targetPrice.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() {
                    device.targetPrice = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      // Speichern
                      Navigator.pop(context);
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addDevice() {
    // Gerät hinzufügen Dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neues Gerät hinzufügen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Gerätename',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Shelly ID',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              // Gerät hinzufügen
              Navigator.pop(context);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }
}

// Einstellungen-Seite
class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notificationsEnabled = true;
  bool priceThresholdEnabled = true;
  bool cheapestTimeEnabled = true;
  double notificationThreshold = 10.0;
  int notificationMinutesBefore = 15;
  TimeOfDay quietTimeStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay quietTimeEnd = const TimeOfDay(hour: 7, minute: 0);
  
  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }
 // FÜGE DIESE DREI METHODEN HIER EIN:
  Future<bool> _checkShellyAuth() async {
    final shellyService = ShellyService();
    return await shellyService.loadCredentials();
  }

  Future<String?> _getShellyEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('shelly_email');
  }

  void _showShellyLoginDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Shelly Cloud Login'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: !isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                enabled: !isLoading,
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () async {
                final shellyService = ShellyService();
                if (await shellyService.loadCredentials()) {
                  setDialogState(() => isLoading = true);
                  await shellyService.logout();
                  setDialogState(() => isLoading = false);
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {}); // Refresh UI
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Abgemeldet')),
                    );
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: FutureBuilder<bool>(
                future: _checkShellyAuth(),
                builder: (context, snapshot) {
                  return Text(snapshot.data == true ? 'Abmelden' : 'Abbrechen');
                },
              ),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (emailController.text.isEmpty || passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bitte alle Felder ausfüllen')),
                  );
                  return;
                }

                setDialogState(() => isLoading = true);
                
                final shellyService = ShellyService();
                final success = await shellyService.login(
                  emailController.text,
                  passwordController.text,
                );

                setDialogState(() => isLoading = false);

                if (mounted) {
                  if (success) {
                    Navigator.pop(context);
                    setState(() {}); // Refresh UI
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erfolgreich angemeldet')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Anmeldung fehlgeschlagen')),
                    );
                  }
                }
              },
              child: const Text('Anmelden'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _initializeNotifications() async {
    // Android Einstellungen
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS Einstellungen mit Berechtigungsanfrage
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        debugPrint('Notification clicked: ${response.payload}');
      },
    );
    
    // Berechtigung für Android 13+ anfordern
    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidPlugin = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        debugPrint('Notification permission granted: $granted');
        
        // Exact Alarm Permission für Android 12+
        final exactAlarmGranted = await androidPlugin.requestExactAlarmsPermission();
        debugPrint('Exact alarm permission granted: $exactAlarmGranted');
      }
    }
    
    // Plane Benachrichtigungen
    _scheduleNotifications();
  }

  Future<void> _scheduleNotifications() async {
    if (!notificationsEnabled) return;
    
    // Hole aktuelle Preise
    final awattarService = AwattarService();
    final prices = await awattarService.fetchPrices();
    
    if (prices.isEmpty) return;
    
    // Lösche alle geplanten Benachrichtigungen
    await notifications.cancelAll();
    
    int notificationId = 1; // Start bei 1 für IDs
    
    // 1. Preis-Schwellwert Benachrichtigungen
    if (priceThresholdEnabled) {
      for (var price in prices) {
        if (price.price <= notificationThreshold) {
          // Prüfe ob in Ruhezeit
          if (!_isInQuietTime(price.startTime)) {
            await _schedulePriceNotification(price, notificationId++);
          }
        }
      }
    }
    
    // 2. Günstigste Zeit Benachrichtigung
    if (cheapestTimeEnabled) {
      // Finde günstigste Zeit heute
      final now = DateTime.now();
      final todayPrices = prices.where((p) => p.startTime.day == now.day).toList();
      if (todayPrices.isNotEmpty) {
        final cheapestToday = todayPrices.reduce((a, b) => a.price < b.price ? a : b);
        await _scheduleCheapestTimeNotification(cheapestToday, 'heute', notificationId++);
      }
      
      // Finde günstigste Zeit morgen
      final tomorrowPrices = prices.where((p) => p.startTime.day == now.day + 1).toList();
      if (tomorrowPrices.isNotEmpty) {
        final cheapestTomorrow = tomorrowPrices.reduce((a, b) => a.price < b.price ? a : b);
        await _scheduleCheapestTimeNotification(cheapestTomorrow, 'morgen', notificationId++);
      }
    }
    
    debugPrint('Scheduled ${notificationId - 1} notifications');
  }

  Future<void> _schedulePriceNotification(PriceData price, int notificationId) async {
    final notificationTime = price.startTime.subtract(const Duration(minutes: 5));
    
    debugPrint('Scheduling price notification #$notificationId for ${price.startTime} at $notificationTime');
    
    if (notificationTime.isAfter(DateTime.now())) {
      await notifications.zonedSchedule(
        notificationId,
        '💡 Günstiger Strompreis!',
        'Jetzt nur ${price.price.toStringAsFixed(2)} ct/kWh - Perfekt für energieintensive Geräte!',
        tz.TZDateTime.from(notificationTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'price_alerts',
            'Preis-Benachrichtigungen',
            channelDescription: 'Benachrichtigungen bei günstigen Strompreisen',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint('Price notification scheduled successfully');
    } else {
      debugPrint('Notification time is in the past, skipping');
    }
  }

  Future<void> _scheduleCheapestTimeNotification(PriceData price, String day, int notificationId) async {
    final notificationTime = price.startTime.subtract(Duration(minutes: notificationMinutesBefore));
    
    debugPrint('Scheduling cheapest time notification #$notificationId for $day at $notificationTime');
    
    if (notificationTime.isAfter(DateTime.now()) && !_isInQuietTime(notificationTime)) {
      await notifications.zonedSchedule(
        notificationId,
        '⚡ Günstigster Zeitpunkt $day!',
        'In $notificationMinutesBefore Minuten beginnt der günstigste Zeitpunkt des Tages (${price.price.toStringAsFixed(2)} ct/kWh)',
        tz.TZDateTime.from(notificationTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'cheapest_time',
            'Günstigste Zeit',
            channelDescription: 'Benachrichtigung zum günstigsten Zeitpunkt',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint('Cheapest time notification scheduled successfully');
    } else {
      debugPrint('Notification time is in the past or in quiet time, skipping');
    }
  }

  bool _isInQuietTime(DateTime time) {
    final timeOfDay = TimeOfDay.fromDateTime(time);
    final startMinutes = quietTimeStart.hour * 60 + quietTimeStart.minute;
    final endMinutes = quietTimeEnd.hour * 60 + quietTimeEnd.minute;
    final currentMinutes = timeOfDay.hour * 60 + timeOfDay.minute;
    
    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Benachrichtigungen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Push-Benachrichtigungen'),
                    subtitle: const Text('Hauptschalter für alle Benachrichtigungen'),
                    value: notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        notificationsEnabled = value;
                        if (value) {
                          _scheduleNotifications();
                        } else {
                          notifications.cancelAll();
                        }
                      });
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Preis-Schwellwert'),
                    subtitle: Text('Benachrichtigung wenn Preis unter ${notificationThreshold.toStringAsFixed(2)} ct/kWh'),
                    value: priceThresholdEnabled && notificationsEnabled,
                    onChanged: notificationsEnabled ? (value) {
                      setState(() {
                        priceThresholdEnabled = value;
                        _scheduleNotifications();
                      });
                    } : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Schwellwert: ${notificationThreshold.toStringAsFixed(2)} ct/kWh'),
                        Slider(
                          value: notificationThreshold,
                          min: 0,
                          max: 30,
                          divisions: 60,
                          label: notificationThreshold.toStringAsFixed(2),
                          onChanged: (notificationsEnabled && priceThresholdEnabled) ? (value) {
                            setState(() {
                              notificationThreshold = value;
                            });
                          } : null,
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Günstigste Zeit'),
                    subtitle: Text('$notificationMinutesBefore Min. vor dem günstigsten Zeitpunkt'),
                    value: cheapestTimeEnabled && notificationsEnabled,
                    onChanged: notificationsEnabled ? (value) {
                      setState(() {
                        cheapestTimeEnabled = value;
                        _scheduleNotifications();
                      });
                    } : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vorlaufzeit: $notificationMinutesBefore Minuten'),
                        Slider(
                          value: notificationMinutesBefore.toDouble(),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          label: '$notificationMinutesBefore Min.',
                          onChanged: (notificationsEnabled && cheapestTimeEnabled) ? (value) {
                            setState(() {
                              notificationMinutesBefore = value.toInt();
                            });
                          } : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ruhezeiten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keine Benachrichtigungen während der Ruhezeiten',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Ruhezeit Start'),
                    subtitle: Text('${quietTimeStart.hour}:${quietTimeStart.minute.toString().padLeft(2, '0')} Uhr'),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: quietTimeStart,
                      );
                      if (time != null) {
                        setState(() {
                          quietTimeStart = time;
                          _scheduleNotifications();
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Ruhezeit Ende'),
                    subtitle: Text('${quietTimeEnd.hour}:${quietTimeEnd.minute.toString().padLeft(2, '0')} Uhr'),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: quietTimeEnd,
                      );
                      if (time != null) {
                        setState(() {
                          quietTimeEnd = time;
                          _scheduleNotifications();
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API Einstellungen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('aWATTar API'),
                    subtitle: const Text('Verbunden'),
                    trailing: const Icon(Icons.check_circle, color: Colors.green),
                  ),
                  ListTile(
                    title: const Text('Shelly Cloud'),
                    subtitle: FutureBuilder<bool>(
                      future: _checkShellyAuth(),
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return FutureBuilder<String?>(
                            future: _getShellyEmail(),
                            builder: (context, emailSnapshot) {
                              return Text('Verbunden als ${emailSnapshot.data ?? '...'}');
                            },
                          );
                        }
                        return const Text('Nicht verbunden');
                      },
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      _showShellyLoginDialog();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _scheduleNotifications,
            icon: const Icon(Icons.refresh),
            label: const Text('Benachrichtigungen aktualisieren'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
}

// Datenmodelle
class PriceData {
  final DateTime startTime;
  final DateTime endTime;
  final double price;

  PriceData({
    required this.startTime,
    required this.endTime,
    required this.price,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      startTime: DateTime.fromMillisecondsSinceEpoch(json['start_timestamp']),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['end_timestamp']),
      price: json['marketprice'] / 10.0, // Convert to ct/kWh
    );
  }
}

enum DeviceType { washer, dishwasher, dryer, charger, heater, other }

class SmartDevice {
  final String id;
  final String name;
  final DeviceType type;
  final String shellyId;
  bool isAutomated;
  double targetPrice;

  SmartDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.shellyId,
    required this.isAutomated,
    required this.targetPrice,
  });

  IconData getIcon() {
    switch (type) {
      case DeviceType.washer:
        return Icons.local_laundry_service;
      case DeviceType.dishwasher:
        return Icons.kitchen;
      case DeviceType.dryer:
        return Icons.dry_cleaning;
      case DeviceType.charger:
        return Icons.ev_station;
      case DeviceType.heater:
        return Icons.thermostat;
      default:
        return Icons.power;
    }
  }
}

// aWATTar API Service
class AwattarService {
  static const String baseUrl = 'https://api.awattar.at/v1/marketdata';

  Future<List<PriceData>> fetchPrices() async {
    final now = DateTime.now();
    // Starte bei der aktuellen Stunde (nicht der aktuellen Minute)
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    final end = DateTime(now.year, now.month, now.day + 2); // Bis Ende morgen

    final url = Uri.parse('$baseUrl?start=${currentHour.millisecondsSinceEpoch}&end=${end.millisecondsSinceEpoch}');
    
    debugPrint('Fetching prices from: ${currentHour.toIso8601String()} to ${end.toIso8601String()}');
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> priceList = data['data'];
        
        debugPrint('Received ${priceList.length} price entries');
        
        // Konvertiere zu PriceData
        final allPrices = priceList.map((item) => PriceData.fromJson(item)).toList();
        
        // Debug: Zeige die ersten paar Preise
        if (allPrices.isNotEmpty) {
          debugPrint('First price: ${allPrices.first.startTime} - ${allPrices.first.endTime}');
          debugPrint('Current time: $now');
        }
        
        // Gib ALLE Preise zurück (inklusive der aktuellen Stunde)
        return allPrices;
      } else {
        throw Exception('Failed to load prices: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching prices: $e');
    }
  }
}

// Shelly API Service (Beispiel-Implementierung)
class ShellyService {
  static const String baseUrl = 'https://api.shelly.cloud';
  String? authToken;
  String? serverUri;
  
  ShellyService({this.authToken});

  // Login zur Shelly Cloud
  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/user/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'email=${Uri.encodeQueryComponent(email)}'
            '&password=${Uri.encodeQueryComponent(password)}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        authToken = data['auth_key'];
        serverUri = data['server_uri'] ?? baseUrl;
        
        // Speichere Auth-Token sicher
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('shelly_auth_token', authToken!);
        await prefs.setString('shelly_server_uri', serverUri!);
        await prefs.setString('shelly_email', email);
        
        debugPrint('Shelly login successful');
        return true;
      } else {
        debugPrint('Shelly login failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Shelly login error: $e');
      return false;
    }
  }

  // Lade gespeicherte Credentials
  Future<bool> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    authToken = prefs.getString('shelly_auth_token');
    serverUri = prefs.getString('shelly_server_uri');
    return authToken != null;
  }

  // Hole alle Geräte
  Future<List<ShellyDevice>> getDevices() async {
    if (authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$serverUri/device/all_status'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'auth_key': authToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final devices = <ShellyDevice>[];
        
        if (data['devices'] != null) {
          for (var deviceId in data['devices'].keys) {
            final deviceData = data['devices'][deviceId];
            devices.add(ShellyDevice(
              id: deviceId,
              name: deviceData['settings']['name'] ?? 'Unnamed Device',
              type: deviceData['settings']['device']['type'] ?? 'unknown',
              isOnline: deviceData['online'] ?? false,
              isOn: deviceData['relays']?[0]?['ison'] ?? false,
            ));
          }
        }
        
        return devices;
      } else {
        throw Exception('Failed to get devices: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting devices: $e');
      throw e;
    }
  }

  // Schalte Gerät ein/aus
  Future<bool> toggleDevice(String deviceId, bool turnOn) async {
    if (authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$serverUri/device/relay/control'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'auth_key': authToken!,
          'id': deviceId,
          'channel': '0',
          'turn': turnOn ? 'on' : 'off',
        },
      );

      if (response.statusCode == 200) {
        debugPrint('Device $deviceId turned ${turnOn ? 'on' : 'off'}');
        return true;
      } else {
        debugPrint('Failed to control device: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Error controlling device: $e');
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shelly_auth_token');
    await prefs.remove('shelly_server_uri');
    await prefs.remove('shelly_email');
    authToken = null;
    serverUri = null;
  }
}

// Shelly Geräte-Model
class ShellyDevice {
  final String id;
  final String name;
  final String type;
  final bool isOnline;
  bool isOn;

  ShellyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isOnline,
    required this.isOn,
  });
}