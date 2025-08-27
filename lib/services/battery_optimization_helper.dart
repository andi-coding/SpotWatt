import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BatteryOptimizationHelper {
  /// Prüft und fordert Battery Optimization Berechtigung an
  /// Mit Context für Dialog-Anzeige
  static Future<bool> requestBatteryOptimizationExemption([BuildContext? context]) async {
    debugPrint("[BatteryOptimization] Starting battery optimization exemption request");
    
    // 1. Check if we already have battery optimization exemption
    final currentStatus = await Permission.ignoreBatteryOptimizations.status;
    if (currentStatus.isGranted) {
      debugPrint("[BatteryOptimization] ✅ Battery optimization already disabled");
      return true;
    }
    
    // 2. Show instruction dialog BEFORE requesting (if we have context)
    if (context != null) {
      debugPrint("[BatteryOptimization] Showing instructions for battery optimization");
      final userAccepted = await _showBatteryOptimizationDialog(context);
      if (!userAccepted) {
        debugPrint("[BatteryOptimization] ❌ User cancelled battery optimization request");
        return false;
      }
    }
    
    // 3. Request battery optimization exemption
    debugPrint("[BatteryOptimization] Requesting battery optimization exemption");
    final status = await Permission.ignoreBatteryOptimizations.request();
    
    if (status.isGranted) {
      debugPrint("[BatteryOptimization] ✅ Battery optimization exemption granted");
      return true;
    } else {
      debugPrint("[BatteryOptimization] ❌ Battery optimization exemption denied");
      return false;
    }
  }
  
  /// Überprüft ob Battery Optimization bereits deaktiviert ist
  static Future<bool> isBatteryOptimizationDisabled() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    debugPrint("[BatteryOptimization] Battery optimization status: $status");
    return status.isGranted;
  }
  
  /// Öffnet die System-Einstellungen für Battery Optimization
  static Future<void> openBatteryOptimizationSettings() async {
    debugPrint("[BatteryOptimization] Opening battery optimization settings");
    await openAppSettings();
  }
  
  /// Zeigt Anweisungen für Battery Optimization Berechtigung
  static Future<bool> _showBatteryOptimizationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User muss Button klicken
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.battery_saver, color: Colors.orange),
              SizedBox(width: 8),
              Text('Hintergrundaktivität'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SpottWatt benötigt dauerhafte Hintergrundaktivität, um die Strompreise regelmäßig zu aktualisieren.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'Ohne diese Berechtigung:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.close, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Preise werden nicht im Hintergrund aktualisiert',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.close, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Benachrichtigungen könnten ausbleiben',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Diese Einstellung deaktiviert Energiespar-Einschränkungen nur für SpottWatt.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
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
                  Icon(Icons.cancel),
                  SizedBox(width: 4),
                  Text('Später'),
                ],
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.battery_saver_outlined),
                  SizedBox(width: 4),
                  Text('Zulassen'),
                ],
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    ) ?? false;
  }
}