import 'package:flutter/material.dart';
import 'price_overview_page.dart';
import 'spartipps_page.dart';
import 'settings_page.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../widgets/savings_tips_preview.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  final NotificationService _notificationService = NotificationService();

  final List<Widget> _pages = [
    const PriceOverviewPage(),
    const SpartippsPage(),
    // const DevicesPage(), // Hidden for now - keeping code for later
    const SettingsPage(),
  ];
  
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    // Terms are now handled in onboarding, no need for separate dialog

    // Setup notification tap handler BEFORE initializing notifications
    NotificationService.setNotificationTapCallback((tabIndex) {
      if (mounted) {
        setState(() {
          _selectedIndex = tabIndex;
        });
      }
    });

    // Notifications initialisieren (without requesting permissions)
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
    return NotificationListener<SpartippsNavigationNotification>(
      onNotification: (notification) {
        // Switch to Spartipps tab when notification is received
        setState(() {
          _selectedIndex = 1; // Spartipps tab index
        });
        return true;
      },
      child: Scaffold(
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
            icon: Icon(Icons.lightbulb_outline),
            label: 'Spartipps',
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
      ),
    );
  }
}