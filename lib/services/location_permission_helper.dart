import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationPermissionHelper {
  /// Fragt zuerst Fine/Coarse, danach explizit Background-Location ab.
  /// Mit Context für Dialog-Anzeige
  static Future<bool> requestLocationPermissions([BuildContext? context]) async {
    debugPrint("[LocationPermissions] Starting permission request flow");
    
    // 1. Basis-Permissions (Fine/Coarse)
    debugPrint("[LocationPermissions] Requesting basic location permission...");
    final fine = await Permission.location.request();
    if (fine.isDenied) {
      debugPrint("[LocationPermissions] ❌ User denied basic location permission");
      return false;
    }
    
    debugPrint("[LocationPermissions] ✅ Basic location permission granted");

    // 2. Check if we already have background permission
    final currentStatus = await Permission.locationAlways.status;
    if (currentStatus.isGranted) {
      debugPrint("[LocationPermissions] ✅ Background location already granted");
      return true;
    }
    
    // 3. Show instruction dialog BEFORE requesting (if we have context)
    if (context != null) {
      debugPrint("[LocationPermissions] Showing instructions for background permission");
      await _showBackgroundLocationDialog(context);
    }
    
    // 4. Open LOCATION settings directly (not general app settings)
    debugPrint("[LocationPermissions] Opening location settings for background permission");
    await Permission.locationAlways.request(); // This should open location-specific settings
    
    // 5. Check again after user returns from settings
    await Future.delayed(const Duration(seconds: 1)); // Give time for permission change
    final finalStatus = await Permission.locationAlways.status;
    
    if (finalStatus.isGranted) {
      debugPrint("[LocationPermissions] ✅ Background location granted in settings");
      return true;
    } else {
      debugPrint("[LocationPermissions] ❌ Background location still not granted");
      return false;
    }

  }
  
  /// Überprüft ob Background-Location bereits erteilt ist
  static Future<bool> hasBackgroundLocationPermission() async {
    final status = await Permission.locationAlways.status;
    debugPrint("[LocationPermissions] Background location status: $status");
    return status.isGranted;
  }
  
  /// Überprüft ob grundlegende Location-Permission erteilt ist
  static Future<bool> hasLocationPermission() async {
    final status = await Permission.location.status;
    debugPrint("[LocationPermissions] Basic location status: $status");
    return status.isGranted;
  }
  
  /// Zeigt Anweisungen für Background-Location Permission
  static Future<void> _showBackgroundLocationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User muss Button klicken
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.blue),
              SizedBox(width: 8),
              Text('Standort-Berechtigung'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Für standortbasierte Benachrichtigungen benötigt SpottWatt Zugriff auf Ihren Standort.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'Bitte wählen Sie in den Einstellungen:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '"Immer zulassen"',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '"Zugriff nur während der Nutzung der App zulassen"',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings),
                  SizedBox(width: 4),
                  Text('Zu Einstellungen'),
                ],
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}