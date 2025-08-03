import 'package:flutter/material.dart';
import '../services/shelly_service.dart';

class ShellyLoginDialog extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const ShellyLoginDialog({
    Key? key,
    required this.onLoginSuccess,
  }) : super(key: key);

  @override
  State<ShellyLoginDialog> createState() => _ShellyLoginDialogState();
}

class _ShellyLoginDialogState extends State<ShellyLoginDialog> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte alle Felder ausfüllen')),
      );
      return;
    }

    setState(() => isLoading = true);
    
    final shellyService = ShellyService();
    final success = await shellyService.login(
      emailController.text,
      passwordController.text,
    );

    setState(() => isLoading = false);

    if (mounted) {
      if (success) {
        Navigator.pop(context);
        widget.onLoginSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erfolgreich angemeldet')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anmeldung fehlgeschlagen')),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    setState(() => isLoading = true);
    
    final shellyService = ShellyService();
    await shellyService.logout();
    
    setState(() => isLoading = false);
    
    if (mounted) {
      Navigator.pop(context);
      widget.onLoginSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abgemeldet')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ShellyService().loadCredentials(),
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.data ?? false;
        
        return AlertDialog(
          title: const Text('Shelly Cloud Login'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLoggedIn) ...[
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Passwort',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  enabled: !isLoading,
                ),
              ] else
                const Text('Sie sind bereits angemeldet.'),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () {
                if (isLoggedIn) {
                  _handleLogout();
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(isLoggedIn ? 'Abmelden' : 'Abbrechen'),
            ),
            if (!isLoggedIn)
              ElevatedButton(
                onPressed: isLoading ? null : _handleLogin,
                child: const Text('Anmelden'),
              ),
          ],
        );
      },
    );
  }
}