import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Über SpotWatt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.bolt,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SpotWatt',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 1.0.0',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).textTheme.bodyLarge?.color?.withAlpha(179),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Die smarte App für günstige Stromzeiten',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.mail_outline, color: Theme.of(context).colorScheme.primary),
                  title: const Text('Kontakt & Feedback'),
                  subtitle: const Text('support@spotwatt.de'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    final Uri emailUri = Uri(
                      scheme: 'mailto',
                      path: 'support@spotwatt.de',
                      queryParameters: {
                        'subject': 'SpotWatt Feedback',
                      },
                    );
                    if (await canLaunchUrl(emailUri)) {
                      await launchUrl(emailUri);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                  title: const Text('Website'),
                  subtitle: const Text('spotwatt.github.io'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () async {
                    final Uri websiteUrl = Uri.parse('https://spotwatt.github.io');
                    if (await canLaunchUrl(websiteUrl)) {
                      await launchUrl(websiteUrl, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: ListTile(
              leading: Icon(Icons.favorite, color: Colors.pink),
              title: const Text('SpotWatt unterstützen'),
              subtitle: const Text('Wenn dir die App gefällt, freue ich mich über deine Unterstützung'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final Uri kofiUrl = Uri.parse('https://ko-fi.com/spotwatt');
                try {
                  if (await canLaunchUrl(kofiUrl)) {
                    await launchUrl(kofiUrl, mode: LaunchMode.externalApplication);
                  } else {
                    // Fallback - versuche trotzdem zu öffnen
                    await launchUrl(kofiUrl, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  // Zeige Fehlermeldung dem Nutzer
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ko-fi Link konnte nicht geöffnet werden: $e'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}