import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = '${packageInfo.version}+${packageInfo.buildNumber}';
      });
    }
  }

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
                  Image.asset(
                    'assets/icons/spotwatt_logo_final.png',
                    width: 64,
                    height: 64,
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
                    'Version $_version',
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
            child: ListTile(
              leading: Icon(Icons.mail_outline, color: Theme.of(context).colorScheme.primary),
              title: const Text('Kontakt & Feedback'),
              subtitle: const Text('contact@spotwatt.at'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final Uri emailUri = Uri(
                  scheme: 'mailto',
                  path: 'contact@spotwatt.at',
                  queryParameters: {
                    'subject': 'SpotWatt Feedback',
                  },
                );
                try {
                  await launchUrl(emailUri);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('E-Mail konnte nicht geöffnet werden: $e')),
                    );
                  }
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
              title: const Text('Website'),
              subtitle: const Text('www.spotwatt.at'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final Uri websiteUrl = Uri.parse('https://www.spotwatt.at');
                try {
                  await launchUrl(websiteUrl, mode: LaunchMode.externalApplication);
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
              leading: Icon(Icons.favorite, color: Colors.pink),
              title: const Text('SpotWatt unterstützen'),
              subtitle: const Text('Wenn dir die App gefällt, freue ich mich über deine Unterstützung'),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () async {
                final Uri kofiUrl = Uri.parse('https://ko-fi.com/spotwatt');
                try {
                  await launchUrl(kofiUrl, mode: LaunchMode.externalApplication);
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
        ],
      ),
    );
  }
}