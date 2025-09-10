import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/price_utils.dart';
import '../services/awattar_service.dart';
import '../services/price_cache_service.dart';
import '../services/notification_service.dart';

enum EnergyProvider {
  custom('custom', 'Benutzerdefiniert'),
  awattarAT('awattar_at', 'aWATTar Hourly (AT)'),
  awattarDE('awattar_de', 'Tado Hourly (DE)');

  final String code;
  final String displayName;
  
  const EnergyProvider(this.code, this.displayName);
}

class PriceSettingsHelper {
  static double calculateProviderFee(double spotPrice, String providerCode, double percentage, double fixedFee) {
    switch (providerCode) {
      case 'awattar_at':
      case 'awattar_de':
        // aWATTar formula: |Spot * 3%| + 1.5 cent
        return spotPrice.abs() * 0.03 + 1.5;
      case 'custom':
      default:
        // Custom formula: |Spot * percentage| + fixed fee
        return spotPrice.abs() * (percentage / 100) + fixedFee;
    }
  }
}

class PriceSettingsPage extends StatefulWidget {
  const PriceSettingsPage({Key? key}) : super(key: key);

  @override
  State<PriceSettingsPage> createState() => _PriceSettingsPageState();
}

class _PriceSettingsPageState extends State<PriceSettingsPage> {
  bool fullCostMode = false;
  double energyProviderFee = 0.0;
  double energyProviderPercentage = 0.0;
  double energyProviderFixedFee = 0.0;
  double networkCosts = 0.0;
  bool includeTax = true;
  PriceMarket selectedMarket = PriceMarket.austria;
  EnergyProvider selectedProvider = EnergyProvider.custom;
  
  // Text controllers for input fields
  late TextEditingController _percentageController;
  late TextEditingController _fixedFeeController;
  late TextEditingController _networkCostsController;
  
  // Focus nodes for input fields
  final FocusNode _percentageFocusNode = FocusNode();
  final FocusNode _fixedFeeFocusNode = FocusNode();
  final FocusNode _networkCostsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _percentageController = TextEditingController();
    _fixedFeeController = TextEditingController();
    _networkCostsController = TextEditingController();
    
    // Add listeners to save when focus is lost
    _percentageFocusNode.addListener(() {
      if (!_percentageFocusNode.hasFocus) {
        _saveSettings();
      }
    });
    _fixedFeeFocusNode.addListener(() {
      if (!_fixedFeeFocusNode.hasFocus) {
        _saveSettings();
      }
    });
    _networkCostsFocusNode.addListener(() {
      if (!_networkCostsFocusNode.hasFocus) {
        _saveSettings();
      }
    });
    
    _loadSettings();
  }
  
  @override
  void dispose() {
    _percentageController.dispose();
    _fixedFeeController.dispose();
    _networkCostsController.dispose();
    _percentageFocusNode.dispose();
    _fixedFeeFocusNode.dispose();
    _networkCostsFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      fullCostMode = prefs.getBool('full_cost_mode') ?? false;
      energyProviderFee = prefs.getDouble('energy_provider_fee') ?? 0.0;
      energyProviderPercentage = prefs.getDouble('energy_provider_percentage') ?? 0.0;
      energyProviderFixedFee = prefs.getDouble('energy_provider_fixed_fee') ?? 0.0;
      networkCosts = prefs.getDouble('network_costs') ?? 0.0;
      includeTax = prefs.getBool('include_tax') ?? true;
      
      // Update text controllers
      _percentageController.text = energyProviderPercentage.toStringAsFixed(1);
      _fixedFeeController.text = energyProviderFixedFee.toStringAsFixed(2);
      _networkCostsController.text = networkCosts.toStringAsFixed(2);
      
      // Load market selection
      final marketCode = prefs.getString('price_market') ?? 'AT';
      selectedMarket = PriceMarket.values.firstWhere(
        (m) => m.code == marketCode,
        orElse: () => PriceMarket.austria,
      );
      
      // Load energy provider selection
      final providerCode = prefs.getString('energy_provider') ?? 'custom';
      selectedProvider = EnergyProvider.values.firstWhere(
        (p) => p.code == providerCode,
        orElse: () => EnergyProvider.custom,
      );
      
      // Auto-sync market with aWATTar provider selection
      _syncMarketWithProvider(false); // Don't show snackbar on load
    });
  }

  void _syncMarketWithProvider(bool showSnackbar) {
    PriceMarket? newMarket;
    
    if (selectedProvider == EnergyProvider.awattarAT) {
      newMarket = PriceMarket.austria;
    } else if (selectedProvider == EnergyProvider.awattarDE) {
      newMarket = PriceMarket.germany;
    }
    
    if (newMarket != null && newMarket != selectedMarket) {
      selectedMarket = newMarket;
      if (showSnackbar && Navigator.of(context).mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Markt automatisch auf ${selectedMarket.displayName} geändert'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _saveSettings({bool marketChanged = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('full_cost_mode', fullCostMode);
    await prefs.setDouble('energy_provider_fee', energyProviderFee);
    await prefs.setDouble('energy_provider_percentage', energyProviderPercentage);
    await prefs.setDouble('energy_provider_fixed_fee', energyProviderFixedFee);
    await prefs.setDouble('network_costs', networkCosts);
    await prefs.setBool('include_tax', includeTax);
    await prefs.setString('price_market', selectedMarket.code);
    await prefs.setString('energy_provider', selectedProvider.code);
    
    // Reschedule notifications when price settings change
    // This ensures threshold-based notifications use the correct full cost prices
    final notificationService = NotificationService();
    await notificationService.rescheduleNotifications();
    
    // Only clear cache and show snackbar when market actually changes
    if (marketChanged) {
      await _clearPriceCache();
      if (Navigator.of(context).mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Markt geändert auf ${selectedMarket.displayName}. Preise werden aktualisiert...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _clearPriceCache() async {
    final cacheService = PriceCacheService();
    await cacheService.clearCache();
  }

  double _calculateProviderFee(double spotPrice) {
    final providerCode = selectedProvider == EnergyProvider.awattarAT ? 'awattar_at' :
                        selectedProvider == EnergyProvider.awattarDE ? 'awattar_de' : 'custom';
    return PriceSettingsHelper.calculateProviderFee(spotPrice, providerCode, energyProviderPercentage, energyProviderFixedFee);
  }

  Widget _buildExampleCalculation() {
    // Zwei Beispiele: positiver und negativer SPOT-Preis
    const positiveSpot = 8.5;
    const negativeSpot = -4.0;
    
    // Berechnung für positiven Preis
    final posProviderFee = _calculateProviderFee(positiveSpot);
    final posWithProviderFee = positiveSpot + posProviderFee;
    final posWithNetworkCosts = posWithProviderFee + networkCosts;
    final taxRate = (selectedMarket == PriceMarket.austria) ? 1.20 : 1.19;
    final posFinalPrice = includeTax ? posWithNetworkCosts * taxRate : posWithNetworkCosts;
    
    // Berechnung für negativen Preis
    final negProviderFee = _calculateProviderFee(negativeSpot);
    final negWithProviderFee = negativeSpot + negProviderFee;
    final negWithNetworkCosts = negWithProviderFee + networkCosts;
    final negFinalPrice = includeTax ? negWithNetworkCosts * taxRate : negWithNetworkCosts;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Beispiel 1: Positiver SPOT-Preis
        const Text('Beispiel 1: Positiver SPOT-Preis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('SPOT-Preis: ${PriceUtils.formatPrice(positiveSpot)}', style: const TextStyle(fontSize: 14)),
        if (selectedProvider == EnergyProvider.awattarAT || selectedProvider == EnergyProvider.awattarDE)
          Text('+ Gebühr (|${positiveSpot.toStringAsFixed(1).replaceAll('.', ',')} × 3%| + 1,5ct): ${PriceUtils.formatPrice(posProviderFee)}', style: const TextStyle(fontSize: 14))
        else if (selectedProvider == EnergyProvider.custom && (energyProviderPercentage > 0 || energyProviderFixedFee > 0))
          Text('+ Gebühr (|${positiveSpot.toStringAsFixed(1).replaceAll('.', ',')} × ${energyProviderPercentage.toStringAsFixed(1)}%| + ${energyProviderFixedFee.toStringAsFixed(1)}ct): ${PriceUtils.formatPrice(posProviderFee)}', style: const TextStyle(fontSize: 14)),
        if (networkCosts > 0)
          Text('+ Netzentgelte: ${PriceUtils.formatPrice(networkCosts)}', style: const TextStyle(fontSize: 14)),
        if (includeTax) 
          Text('+ USt (${selectedMarket == PriceMarket.austria ? "20" : "19"}%): ${PriceUtils.formatPrice(posFinalPrice - posWithNetworkCosts)}', style: const TextStyle(fontSize: 14)),
        const Divider(height: 8),
        Text(
          'Endpreis: ${PriceUtils.formatPrice(posFinalPrice)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        
        const SizedBox(height: 16),
        
        // Beispiel 2: Negativer SPOT-Preis
        const Text('Beispiel 2: Negativer SPOT-Preis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('SPOT-Preis: ${PriceUtils.formatPrice(negativeSpot)}', style: const TextStyle(fontSize: 14)),
        if (selectedProvider == EnergyProvider.awattarAT || selectedProvider == EnergyProvider.awattarDE)
          Text('+ Gebühr (|${negativeSpot.toStringAsFixed(1).replaceAll('.', ',')} × 3%| + 1,5ct): ${PriceUtils.formatPrice(negProviderFee)}', style: const TextStyle(fontSize: 14))
        else if (selectedProvider == EnergyProvider.custom && energyProviderPercentage > 0)
          Text('+ Gebühr (|${negativeSpot.toStringAsFixed(1).replaceAll('.', ',')} × ${energyProviderPercentage.toStringAsFixed(1)}%| + ${energyProviderFixedFee.toStringAsFixed(1)}ct): ${PriceUtils.formatPrice(negProviderFee)}', style: const TextStyle(fontSize: 14))
        else
          Text('+ Gebühr: ${PriceUtils.formatPrice(negProviderFee)}', style: const TextStyle(fontSize: 14)),
       //Text('= Nach Gebühr: ${PriceUtils.formatPrice(negWithProviderFee)}', style: const TextStyle(fontSize: 14)),
        if (networkCosts > 0) 
          Text('+ Netzentgelte: ${PriceUtils.formatPrice(networkCosts)}', style: const TextStyle(fontSize: 14)),
        if (includeTax)
          Text('+ USt (${selectedMarket == PriceMarket.austria ? "20" : "19"}%): ${PriceUtils.formatPrice(negFinalPrice - negWithNetworkCosts)}', style: const TextStyle(fontSize: 14)),
        const Divider(height: 8),       
        Text(
          'Endpreis: ${PriceUtils.formatPrice(negFinalPrice)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        
        const SizedBox(height: 12),
        //const Divider(),
        const SizedBox(height: 8),
        
        // Erklärung
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Hinweis zum Prozentaufschlag:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Der prozentuale Aufschlag wird immer als positiver Betrag addiert, auch bei negativen SPOT-Preisen. Die Formel nutzt den Absolutwert: |SPOT × %|',
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Bei negativen Preisen erhöht die Gebühr also den Preis.',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Unfocus all text fields when tapping outside
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Preis-Einstellungen'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          // Info section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Was zeigen die Preise?',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Standardmäßig werden EPEX SPOT-Preise angezeigt:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Reine Börsenpreise (aWATTar Hourly)',
                    style: TextStyle(fontSize: 14),
                  ),
                  const Text(
                    '• Ohne Energieanbieter-Gebühren',
                    style: TextStyle(fontSize: 14),
                  ),
                  const Text(
                    '• Ohne Netzentgelte & Steuern',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Market selection section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.language, color: Theme.of(context).colorScheme.primary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Strommarkt auswählen',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Wählen Sie Ihren Strommarkt für die SPOT-Preise:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ...PriceMarket.values.map((market) => RadioListTile<PriceMarket>(
                    title: Row(
                      children: [
                        Text(
                          market == PriceMarket.austria ? '🇦🇹' : '🇩🇪',
                          style: TextStyle(fontSize: 20),
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text(market.displayName)),
                      ],
                    ),
                    subtitle: Padding(
                      padding: EdgeInsets.only(left: 32), // Align with flag
                      child: Text(
                        market == PriceMarket.austria 
                          ? 'EPEX SPOT AT (Österreichische Preiszone)'
                          : 'EPEX SPOT DE (Deutsche Preiszone)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    value: market,
                    groupValue: selectedMarket,
                    onChanged: (value) {
                      if (value != null && value != selectedMarket) {
                        final oldMarket = selectedMarket;
                        setState(() {
                          selectedMarket = value;
                        });
                        _saveSettings(marketChanged: true);
                      }
                    },
                  )).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Full cost settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Vollkosten-Modus',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Vollkosten anzeigen'),
                    subtitle: const Text('Alle Gebühren und Steuern einbeziehen'),
                    value: fullCostMode,
                    onChanged: (value) async {
                      setState(() {
                        fullCostMode = value;
                      });
                      await _saveSettings();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  
                  if (fullCostMode) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    // Energy provider selection
                    Row(
                      children: [
                        Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Energieanbieter-Gebühren',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<EnergyProvider>(
                      value: selectedProvider,
                      decoration: const InputDecoration(
                        labelText: 'Energieanbieter auswählen',
                        border: OutlineInputBorder(),
                      ),
                      items: EnergyProvider.values.map((provider) => DropdownMenuItem(
                        value: provider,
                        child: Text(provider.displayName),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          final oldProvider = selectedProvider;
                          setState(() {
                            selectedProvider = value;
                          });
                          _syncMarketWithProvider(true);
                          _saveSettings();
                        }
                      },
                    ),
                    
                    // Show formula info for non-custom providers
                    if (selectedProvider != EnergyProvider.custom) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Preisaufschlag: Epex Spot + 3% + 1,5 ct/kWh',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // Energy provider fee configuration for custom
                    if (selectedProvider == EnergyProvider.custom) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _percentageController,
                              focusNode: _percentageFocusNode,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Prozentaufschlag (%)',
                                border: OutlineInputBorder(),
                                suffixText: '%',
                              ),
                              onChanged: (value) {
                                final parsed = double.tryParse(value.replaceAll(',', '.'));
                                if (parsed != null) {
                                  setState(() {
                                    energyProviderPercentage = parsed;
                                  });
                                }
                              },
                              onFieldSubmitted: (value) {
                                _saveSettings();
                              },
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _fixedFeeController,
                              focusNode: _fixedFeeFocusNode,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Fixer Aufschlag',
                                border: OutlineInputBorder(),
                                suffixText: 'ct/kWh',
                              ),
                              onChanged: (value) {
                                final parsed = double.tryParse(value.replaceAll(',', '.'));
                                if (parsed != null) {
                                  setState(() {
                                    energyProviderFixedFee = parsed;
                                  });
                                }
                              },
                              onFieldSubmitted: (value) {
                                _saveSettings();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // Network costs
                    const Text('Netzentgelte & Abgaben', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _networkCostsController,
                      focusNode: _networkCostsFocusNode,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Netzentgelte & Abgaben',
                        border: OutlineInputBorder(),
                        suffixText: 'ct/kWh',
                      ),
                      onChanged: (value) {
                        final parsed = double.tryParse(value.replaceAll(',', '.'));
                        if (parsed != null) {
                          setState(() {
                            networkCosts = parsed;
                          });
                        }
                      },
                      onFieldSubmitted: (value) {
                        _saveSettings();
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Tax toggle
                    SwitchListTile(
                      title: Text('Umsatzsteuer (${selectedMarket == PriceMarket.austria ? "20" : "19"}%)'),
                      subtitle: const Text('Bruttopreise anzeigen'),
                      value: includeTax,
                      onChanged: (value) async {
                        setState(() {
                          includeTax = value;
                        });
                        await _saveSettings();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (fullCostMode) ...[
            const SizedBox(height: 16),
            
            // Example calculation
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Beispiel-Rechnung',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildExampleCalculation(),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }
}