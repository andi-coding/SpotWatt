import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../services/shelly_service.dart';
import '../services/location_permission_helper.dart';
import '../utils/price_utils.dart';
import '../widgets/shelly_login_dialog.dart';
import 'price_settings_page.dart';
import 'notification_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  Future<bool> _checkShellyAuth() async {
    final shellyService = ShellyService();
    return await shellyService.loadCredentials();
  }

  Future<String?> _getShellyEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('shelly_email');
  }

  void _showShellyLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShellyLoginDialog(
        onLoginSuccess: () {
          setState(() {});
        },
      ),
    );
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
            child: ListTile(
              leading: Icon(Icons.notifications, color: Theme.of(context).colorScheme.primary),
              title: const Text('Benachrichtigungen'),
              subtitle: const Text('Preisalarme, Ruhezeiten & Standort-Einstellungen'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSettingsPage(),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: ListTile(
              leading: Icon(Icons.euro, color: Theme.of(context).colorScheme.primary),
              title: const Text('Preis-Einstellungen'),
              subtitle: const Text('Vollkosten, Gebühren & Steuern konfigurieren'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PriceSettingsPage(),
                  ),
                );
              },
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
                  // Hidden for now - keeping code for later
                  /*
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
                    onTap: _showShellyLoginDialog,
                  ),
                  */
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
                  Row(
                    children: [
                      Icon(Icons.update, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Background Updates',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Die App aktualisiert Strompreise automatisch im Hintergrund:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Funktioniert auch wenn die App geschlossen ist!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}