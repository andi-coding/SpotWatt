class AppConstants {
  // API URLs
  static const String awattarBaseUrl = 'https://api.awattar.at/v1/marketdata';
  static const String shellyBaseUrl = 'https://api.shelly.cloud';
  static const String shellyEuServerUrl = 'https://shelly-13-eu.shelly.cloud';
  
  // App Info
  static const String appName = 'WattWise';
  static const String appVersion = '1.0.0';
  
  // Default Values
  static const double defaultNotificationThreshold = 10.0;
  static const int defaultNotificationMinutesBefore = 15;
  static const int defaultQuietTimeStartHour = 22;
  static const int defaultQuietTimeEndHour = 7;
  
  // Storage Keys
  static const String keyNotificationsEnabled = 'notifications_enabled';
  static const String keyPriceThresholdEnabled = 'price_threshold_enabled';
  static const String keyCheapestTimeEnabled = 'cheapest_time_enabled';
  static const String keyNotificationThreshold = 'notification_threshold';
  static const String keyNotificationMinutesBefore = 'notification_minutes_before';
  static const String keyShellyAuthToken = 'shelly_auth_token';
  static const String keyShellyServerUri = 'shelly_server_uri';
  static const String keyShellyEmail = 'shelly_email';
  static const String keyShellyDeviceId = 'shelly_device_id';
  
  // UI Constants
  static const double chartHeight = 200.0;
  static const double cardElevation = 2.0;
  static const double borderRadius = 12.0;
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
}