import 'package:flutter/material.dart';
import '../main.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({Key? key}) : super(key: key);

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
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
        ],
      ),
    );
  }
}