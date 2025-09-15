import 'package:shared_preferences/shared_preferences.dart';

class SettingsCache {
  static final SettingsCache _instance = SettingsCache._internal();
  factory SettingsCache() => _instance;
  SettingsCache._internal();

  // Cached settings
  bool fullCostMode = false;
  double networkCosts = 0.0;
  double energyProviderFixedFee = 0.0;
  double energyProviderPercentage = 0.0;
  bool includeTax = true;
  String priceMarket = 'AT';
  String energyProvider = 'custom';

  // Initialize and load settings
  Future<void> init() async {
    await loadSettings();
  }

  // Load settings from SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    fullCostMode = prefs.getBool('full_cost_mode') ?? false;
    networkCosts = prefs.getDouble('network_costs') ?? 0.0;
    energyProviderFixedFee = prefs.getDouble('energy_provider_fixed_fee') ?? 0.0;
    energyProviderPercentage = prefs.getDouble('energy_provider_percentage') ?? 0.0;
    includeTax = prefs.getBool('include_tax') ?? true;
    priceMarket = prefs.getString('price_market') ?? 'AT';
    energyProvider = prefs.getString('energy_provider') ?? 'custom';
  }
}