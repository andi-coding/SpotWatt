import 'package:shared_preferences/shared_preferences.dart';
import '../models/price_data.dart';
import '../screens/price_settings_page.dart';
import 'awattar_service.dart';
import 'energy_provider_service.dart';

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

    // Get tax rate from API (with cache)
    final marketCode = prefs.getString('price_market') ?? 'AT';
    final taxRate = await _getTaxRate(marketCode);

    // Strategy: Convert SPOT to BRUTTO, then add BRUTTO fees
    // SPOT price is NETTO (exkl. USt) from EPEX
    // Provider fees are BRUTTO (inkl. USt) from DB
    // Network costs are BRUTTO (inkl. USt) from user input (standard)

    // 1. Apply tax to SPOT first (NETTO → BRUTTO)
    double spotBrutto = spotPrice * taxRate;

    // 2. Provider fee is already BRUTTO from DB
    final providerFeeBrutto = await _calculateProviderFee(spotPrice);

    // 3. Network costs are already BRUTTO by default (includeTax=true)
    //    If user entered NETTO (includeTax=false), apply tax
    final networkCostsBrutto = includeTax ? networkCosts : networkCosts * taxRate;

    // 4. Sum all BRUTTO values
    double total = spotBrutto + providerFeeBrutto + networkCostsBrutto;

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

  // Get tax rate for market from SharedPreferences (cached by EnergyProviderService)
  Future<double> _getTaxRate(String marketCode) async {
    final prefs = await SharedPreferences.getInstance();
    final taxRate = prefs.getDouble('tax_rate_$marketCode');

    if (taxRate != null) {
      return 1.0 + (taxRate / 100); // Convert to multiplier (20% => 1.20)
    }

    // Fallback to hardcoded values if not cached yet
    return marketCode == 'AT' ? 1.20 : 1.19;
  }
}