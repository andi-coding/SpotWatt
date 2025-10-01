import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TermsDialog extends StatelessWidget {
  const TermsDialog({Key? key}) : super(key: key);

  static const String _termsAcceptedKey = 'terms_accepted';

  /// Check if user has already accepted terms
  static Future<bool> hasAcceptedTerms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_termsAcceptedKey) ?? false;
  }

  /// Mark terms as accepted
  static Future<void> acceptTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_termsAcceptedKey, true);
  }

  /// Show the terms dialog if not yet accepted
  static Future<void> showIfNeeded(BuildContext context) async {
    final accepted = await hasAcceptedTerms();
    if (!accepted && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const TermsDialog(),
      );
    }
  }

  Future<void> _launchUrl(String url, BuildContext context) async {
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link konnte nicht geöffnet werden: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Willkommen bei SpotWatt!'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mit der Nutzung dieser App stimmst du den folgenden Bedingungen zu:',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Nutzungsbedingungen Link
              InkWell(
                onTap: () => _launchUrl('https://www.spotwatt.at/terms.html', context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_outlined, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Nutzungsbedingungen',
                          style: TextStyle(
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.open_in_new, color: colorScheme.primary, size: 14),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Datenschutzerklärung Link
              InkWell(
                onTap: () => _launchUrl('https://www.spotwatt.at/privacy.html', context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.privacy_tip_outlined, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Datenschutzerklärung',
                          style: TextStyle(
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.open_in_new, color: colorScheme.primary, size: 14),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Du kannst diese Dokumente jederzeit in den Einstellungen unter "Rechtliches" einsehen.',
                style: textTheme.bodySmall?.copyWith(
                  color: textTheme.bodySmall?.color?.withAlpha(179),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // App schließen wenn abgelehnt
            SystemNavigator.pop();
          },
          child: const Text('Ablehnen'),
        ),
        FilledButton(
          onPressed: () async {
            await acceptTerms();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Akzeptieren'),
        ),
      ],
    );
  }
}
