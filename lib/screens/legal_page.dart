import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechtliches'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.description_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Nutzungsbedingungen'),
              subtitle: const Text('Bedingungen für die App-Nutzung'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final Uri termsUrl = Uri.parse('https://www.spotwatt.at/terms.html');
                try {
                  // Skip canLaunchUrl check, just try to launch (like Ko-fi does)
                  await launchUrl(termsUrl, mode: LaunchMode.externalApplication);
                } catch (e) {
                  print('DEBUG: Error launching URL: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Link konnte nicht geöffnet werden: $e')),
                    );
                  }
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Datenschutzerklärung'),
              subtitle: const Text('Informationen zum Datenschutz'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final Uri privacyUrl = Uri.parse('https://www.spotwatt.at/privacy.html');
                try {
                  await launchUrl(privacyUrl, mode: LaunchMode.externalApplication);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Link konnte nicht geöffnet werden: $e')),
                    );
                  }
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: Icon(Icons.article_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('Impressum'),
              subtitle: const Text('Rechtliche Informationen'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final Uri imprintUrl = Uri.parse('https://www.spotwatt.at/imprint.html');
                try {
                  await launchUrl(imprintUrl, mode: LaunchMode.externalApplication);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Link konnte nicht geöffnet werden: $e')),
                    );
                  }
                }
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          /*Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Hinweis',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'SpotWatt respektiert deine Privatsphäre:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildBulletPoint(context, 'Keine Registrierung erforderlich'),
                  _buildBulletPoint(context, 'Keine persönlichen Daten werden gesammelt'),
                  _buildBulletPoint(context, 'Alle Einstellungen bleiben lokal auf deinem Gerät'),
                  _buildBulletPoint(context, 'Keine Tracking- oder Analyse-Tools'),
                  const SizedBox(height: 12),
                  Text(
                    'Die einzigen externen Verbindungen:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildBulletPoint(context, 'Abruf der Strompreise von der aWATTar API'),
                ],
              ),
            ),
          ),*/
        ],
      ),
    );
  }
  
  Widget _buildBulletPoint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Text('• ', style: Theme.of(context).textTheme.bodyMedium),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}