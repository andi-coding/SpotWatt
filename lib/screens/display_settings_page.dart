import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({Key? key}) : super(key: key);

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  int _defaultStartTab = 0; // 0 = Preise, 1 = Spartipps

  @override
  void initState() {
    super.initState();
    _loadStartTabPreference();
  }

  Future<void> _loadStartTabPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultStartTab = prefs.getInt('default_start_tab') ?? 0;
    });
  }

  Future<void> _saveStartTabPreference(int tabIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_start_tab', tabIndex);
    setState(() {
      _defaultStartTab = tabIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anzeige-Einstellungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Wählen Sie das Erscheinungsbild für App und Widget',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (themeProvider != null) ...[
            Card(
              child: RadioListTile<ThemeMode>(
                title: const Text('Smartphone-Einstellungen folgen'),
                subtitle: const Text('Automatisch zwischen Hell und Dunkel wechseln'),
                value: ThemeMode.system,
                groupValue: themeProvider.currentThemeMode,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    themeProvider.setThemeMode(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: RadioListTile<ThemeMode>(
                title: const Text('Normal (Hell)'),
                subtitle: const Text('Immer helles Design verwenden'),
                value: ThemeMode.light,
                groupValue: themeProvider.currentThemeMode,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    themeProvider.setThemeMode(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: RadioListTile<ThemeMode>(
                title: const Text('Dark Mode'),
                subtitle: const Text('Immer dunkles Design verwenden'),
                value: ThemeMode.dark,
                groupValue: themeProvider.currentThemeMode,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    themeProvider.setThemeMode(value);
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Startseite section
          Text(
            'Startseite',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wählen Sie welche Seite beim App-Start geöffnet wird',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          Card(
            child: RadioListTile<int>(
              title: const Text('Preise'),
              subtitle: const Text('Aktuelle Strompreise und Chart'),
              value: 0,
              groupValue: _defaultStartTab,
              onChanged: (int? value) {
                if (value != null) {
                  _saveStartTabPreference(value);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioListTile<int>(
              title: const Text('Spartipps'),
              subtitle: const Text('Optimale Zeitfenster für Geräte'),
              value: 1,
              groupValue: _defaultStartTab,
              onChanged: (int? value) {
                if (value != null) {
                  _saveStartTabPreference(value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}