import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/shelly_device.dart';

class ShellyService {
  static const String baseUrl = 'https://api.shelly.cloud';
  static const String euServerUrl = 'https://shelly-13-eu.shelly.cloud';
  String? authToken;
  String? serverUri;
  
  ShellyService({this.authToken});
  
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('shelly_device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('shelly_device_id', deviceId);
    }
    return deviceId;
  }

  Future<bool> login(String email, String password) async {
    try {
      final String deviceId = await _getDeviceId();
      final loginUrl = 'https://api.shelly.cloud/auth/login';
      debugPrint('Login URL: $loginUrl');
      
      final Map<String, String> body = {
        'email': email,
        'password': password,
      };
      
      debugPrint('Login attempt with:');
      debugPrint('Email: $email');
      
      final response = await http.post(
        Uri.parse(loginUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: body,
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final data = json.decode(response.body);
          
          authToken = data['auth_key'] ?? data['token'] ?? data['access_token'];
          serverUri = data['server_uri'] ?? data['server_url'] ?? baseUrl;
          
          if (authToken == null) {
            debugPrint('No auth token found in response');
            debugPrint('Response data keys: ${data.keys.toList()}');
            return false;
          }
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('shelly_auth_token', authToken!);
          await prefs.setString('shelly_server_uri', serverUri!);
          await prefs.setString('shelly_email', email);
          
          debugPrint('Shelly login successful');
          return true;
        } catch (e) {
          debugPrint('Error parsing response: $e');
          return false;
        }
      } else {
        debugPrint('Login failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Shelly login error: $e');
      return false;
    }
  }

  Future<bool> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    authToken = prefs.getString('shelly_auth_token');
    serverUri = prefs.getString('shelly_server_uri');
    return authToken != null;
  }

  Future<List<ShellyDevice>> getDevices() async {
    if (authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$serverUri/device/all_status'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'auth_key': authToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final devices = <ShellyDevice>[];
        
        if (data['devices'] != null) {
          for (var deviceId in data['devices'].keys) {
            final deviceData = data['devices'][deviceId];
            devices.add(ShellyDevice(
              id: deviceId,
              name: deviceData['settings']['name'] ?? 'Unnamed Device',
              type: deviceData['settings']['device']['type'] ?? 'unknown',
              isOnline: deviceData['online'] ?? false,
              isOn: deviceData['relays']?[0]?['ison'] ?? false,
            ));
          }
        }
        
        return devices;
      } else {
        throw Exception('Failed to get devices: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting devices: $e');
      throw e;
    }
  }

  Future<bool> toggleDevice(String deviceId, bool turnOn) async {
    if (authToken == null) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$serverUri/device/relay/control'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'auth_key': authToken!,
          'id': deviceId,
          'channel': '0',
          'turn': turnOn ? 'on' : 'off',
        },
      );

      if (response.statusCode == 200) {
        debugPrint('Device $deviceId turned ${turnOn ? 'on' : 'off'}');
        return true;
      } else {
        debugPrint('Failed to control device: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Error controlling device: $e');
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shelly_auth_token');
    await prefs.remove('shelly_server_uri');
    await prefs.remove('shelly_email');
    authToken = null;
    serverUri = null;
  }
}