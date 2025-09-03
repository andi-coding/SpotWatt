import 'package:flutter/material.dart';
import 'price_overview_page.dart';
import 'devices_page.dart';
import 'settings_page.dart';
import '../services/notification_service.dart';
import '../services/price_cache_service.dart';
import '../services/widget_service.dart';
import '../services/location_permission_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final NotificationService _notificationService = NotificationService();
  
  final List<Widget> _pages = [
    const PriceOverviewPage(),
    // const DevicesPage(), // Hidden for now - keeping code for later
    const SettingsPage(),
  ];
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    // Notifications initialisieren
    await _notificationService.initialize(context);
    
    // Location Permissions werden nur angefragt wenn User Location-based Notifications aktiviert
    
    // Setup widget click listener
    WidgetService.setupWidgetClickListener(() async {
      debugPrint('[Widget] Widget clicked - opening app');
      // Just update the widget with cached data
      await WidgetService.updateWidget();
      // Optionally reload the current view to show latest cached data
      setState(() {});
    });
  }

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
          // NavigationDestination( // Hidden for now - keeping code for later
          //   icon: Icon(Icons.power),
          //   label: 'Geräte',
          // ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Einstellungen',
          ),
        ],
      ),
    );
  }
}