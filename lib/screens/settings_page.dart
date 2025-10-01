import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../services/shelly_service.dart';
import '../services/location_permission_helper.dart';
import '../utils/price_utils.dart';
import '../widgets/shelly_login_dialog.dart';
import 'price_settings_page.dart';
import 'notification_settings_page.dart';
import 'display_settings_page.dart';
import 'about_page.dart';
import 'legal_page.dart';

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
              title: const Text('Benachrichtigungs-Einstellungen'),
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
            child: ListTile(
              leading: Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
              title: const Text('Anzeige-Einstellungen'),
              subtitle: const Text(''),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DisplaySettingsPage(),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
              title: const Text('Über SpotWatt'),
              subtitle: const Text('Version, Kontakt & Support'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutPage(),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 8),
          
          Card(
            child: ListTile(
              leading: Icon(Icons.policy_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Rechtliches'),
              subtitle: const Text('Nutzungsbedingungen, Datenschutz & Impressum'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LegalPage(),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 8),
          
          // API Einstellungen entfernt - jetzt in Preis-Einstellungen integriert
          
          /*
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
          */
        ],
      ),
    );
  }

}