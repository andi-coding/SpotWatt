import 'package:shared_preferences/shared_preferences.dart';
import '../models/price_data.dart';
import '../screens/price_settings_page.dart';
import 'awattar_service.dart';

class FullCostCalculator {
  static final FullCostCalculator _instance = FullCostCalculator._internal();
  factory FullCostCalculator() => _instance;
  FullCostCalculator._internal();

  // Calculate full cost for a single price
  Future<double> calculateFullCost(double spotPrice) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if full cost mode is enabled
    final fullCostMode = prefs.getBool('full_cost_mode') ?? false;
    if (!fullCostMode) {
      return spotPrice;
    }

    // Get settings
    final networkCosts = prefs.getDouble('network_costs') ?? 0.0;
    final includeTax = prefs.getBool('include_tax') ?? true;
    
    // Get market for tax rate
    final marketCode = prefs.getString('price_market') ?? 'AT';
    final taxRate = marketCode == 'AT' ? 1.20 : 1.19;
    
    // Calculate provider fee
    final providerFee = await _calculateProviderFee(spotPrice);
    
    // Calculate total
    double total = spotPrice + providerFee + networkCosts;
    
    // Apply tax if enabled
    if (includeTax) {
      total = total * taxRate;
    }
    
    return total;
  }

  Future<double> _calculateProviderFee(double spotPrice) async {
    final prefs = await SharedPreferences.getInstance();
    final providerCode = prefs.getString('energy_provider') ?? 'custom';
    final percentage = prefs.getDouble('energy_provider_percentage') ?? 0.0;
    final fixedFee = prefs.getDouble('energy_provider_fixed_fee') ?? 0.0;
    
    return PriceSettingsHelper.calculateProviderFee(
      spotPrice, 
      providerCode, 
      percentage, 
      fixedFee
    );
  }

  // Process a list of prices and add full cost calculations
  Future<List<PriceData>> addFullCostToPrices(List<PriceData> prices) async {
    final prefs = await SharedPreferences.getInstance();
    final fullCostMode = prefs.getBool('full_cost_mode') ?? false;
    
    // If full cost mode is disabled, return prices as-is
    if (!fullCostMode) {
      return prices;
    }
    
    // Calculate full cost for each price
    final List<PriceData> fullCostPrices = [];
    for (final price in prices) {
      final fullCost = await calculateFullCost(price.price);
      fullCostPrices.add(price.withPrice(fullCost));
    }
    
    return fullCostPrices;
  }

  // Check if full cost mode is enabled
  Future<bool> isFullCostMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('full_cost_mode') ?? false;
  }
}