import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage premium features access
/// In a production app, this would integrate with in-app purchases (IAP)
/// For now, we'll use a simple SharedPreferences flag for testing
class PremiumService {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal();

  static const String _premiumKey = 'has_premium';

  /// Check if user has premium access
  Future<bool> hasPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_premiumKey) ?? false;
  }

  /// Enable premium (for testing / IAP integration point)
  Future<void> enablePremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, true);
  }

  /// Disable premium (for testing)
  Future<void> disablePremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, false);
  }

  /// Premium features list
  static const premiumFeatures = [
    'Unbegrenzte Geräte',
    'Optimale Zeitfenster für alle Geräte',
    'Individuelle Zeitbeschränkungen',
    'Erinnerungen für optimale Startzeiten',
    'Erweiterte Statistiken',
    'Prioritäts-Support',
  ];

  /// Maximum devices for free tier
  static const int freeDeviceLimit = 2;
}
