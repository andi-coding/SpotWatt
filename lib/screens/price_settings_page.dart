import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/price_utils.dart';
import '../services/awattar_service.dart';
import '../services/price_cache_service.dart';
import '../services/notification_service.dart';
import '../services/settings_cache.dart';
import '../services/energy_provider_service.dart';
import '../models/energy_provider.dart';

class PriceSettingsHelper {
  static double calculateProviderFee(double spotPrice, String providerCode, double percentage, double fixedFee) {
    // Unified formula for all providers: |Spot * percentage| + fixed fee
    return spotPrice.abs() * (percentage / 100) + fixedFee;
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
  bool includeTax = true;  // Netzkosten inkl. USt (Standard: ja)
  PriceMarket selectedMarket = PriceMarket.austria;

  // Dynamic provider data from API
  List<EnergyProvider> availableProviders = [];
  EnergyProvider? selectedProvider;
  double taxRate = 20.0; // Will be loaded from API
  bool isLoadingProviders = true;
  
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

    // Load market selection first
    final marketCode = prefs.getString('price_market') ?? 'AT';
    selectedMarket = PriceMarket.values.firstWhere(
      (m) => m.code == marketCode,
      orElse: () => PriceMarket.austria,
    );

    // Load provider data from API
    await _loadProviders();

    setState(() {
      fullCostMode = prefs.getBool('full_cost_mode') ?? false;
      energyProviderFee = prefs.getDouble('energy_provider_fee') ?? 0.0;
      energyProviderPercentage = prefs.getDouble('energy_provider_percentage') ?? 0.0;
      energyProviderFixedFee = prefs.getDouble('energy_provider_fixed_fee') ?? 0.0;
      networkCosts = prefs.getDouble('network_costs') ?? 0.0;
      includeTax = prefs.getBool('include_tax') ?? true;

      // Find selected provider by name
      final providerName = prefs.getString('energy_provider') ?? 'Benutzerdefiniert';
      selectedProvider = availableProviders.firstWhere(
        (p) => p.providerName == providerName,
        orElse: () => availableProviders.first, // Default to first (Benutzerdefiniert)
      );

      // Update text controllers
      _percentageController.text = energyProviderPercentage.toStringAsFixed(1);
      _fixedFeeController.text = energyProviderFixedFee.toStringAsFixed(2);
      _networkCostsController.text = networkCosts.toStringAsFixed(2);
    });
  }

  Future<void> _loadProviders({bool resetSelection = false}) async {
    try {
      // Reset provider selection if requested (e.g., when market changes)
      if (resetSelection) {
        setState(() {
          selectedProvider = null;
          isLoadingProviders = true;
        });
      }

      final service = EnergyProviderService();
      final providerData = await service.getProviders(selectedMarket.code);

      setState(() {
        availableProviders = providerData.providers;
        taxRate = providerData.taxRate;
        isLoadingProviders = false;

        // Set default provider (first one = Benutzerdefiniert) if none selected
        if (selectedProvider == null && availableProviders.isNotEmpty) {
          selectedProvider = availableProviders.first;
        }
      });

      debugPrint('[PriceSettings] Loaded ${availableProviders.length} providers for ${selectedMarket.code}');
    } catch (e) {
      debugPrint('[PriceSettings] Failed to load providers: $e');
      setState(() {
        isLoadingProviders = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Laden der Anbieter: $e'),
            duration: Duration(seconds: 3),
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
    await prefs.setString('energy_provider', selectedProvider?.providerName ?? 'Benutzerdefiniert');

    // Update the settings cache
    await SettingsCache().loadSettings();

    // Reschedule notifications when price settings change
    // This ensures threshold-based notifications use the correct full cost prices
    final notificationService = NotificationService();
    await notificationService.rescheduleNotifications();

    // When market changes, reload providers and ensure cache exists
    if (marketChanged) {
      await _loadProviders(resetSelection: true); // Reload providers and reset selection

      final cacheService = PriceCacheService();
      await cacheService.ensureCacheForMarket(selectedMarket.code);
      if (Navigator.of(context).mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Markt auf ${selectedMarket.displayName} geändert'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Not needed anymore - we keep both caches

  double _calculateProviderFee(double spotPrice) {
    // Einheitliche Berechnung für alle Provider
    return spotPrice.abs() * (energyProviderPercentage / 100) + energyProviderFixedFee;
  }

  Widget _buildExampleCalculation() {
    // Zwei Beispiele: positiver und negativer SPOT-Preis
    const positiveSpot = 8.5;
    const negativeSpot = -4.0;
    
    // Tax multiplier
    final taxMultiplier = 1.0 + (taxRate / 100);

    // Berechnung für positiven Preis
    // Strategy: SPOT (NETTO) × USt → + Provider (BRUTTO) + Network (BRUTTO)
    final posSpotBrutto = positiveSpot * taxMultiplier;
    final posProviderFee = _calculateProviderFee(positiveSpot); // Already BRUTTO
    final posNetworkCostsBrutto = includeTax ? networkCosts : networkCosts * taxMultiplier;
    final posFinalPrice = posSpotBrutto + posProviderFee + posNetworkCostsBrutto;

    // Berechnung für negativen Preis
    final negSpotBrutto = negativeSpot * taxMultiplier;
    final negProviderFee = _calculateProviderFee(negativeSpot); // Already BRUTTO
    final negNetworkCostsBrutto = includeTax ? networkCosts : networkCosts * taxMultiplier;
    final negFinalPrice = negSpotBrutto + negProviderFee + negNetworkCostsBrutto;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Beispiel 1: Positiver SPOT-Preis
        const Text('Beispiel 1: Positiver SPOT-Preis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('SPOT-Preis (NETTO): ${PriceUtils.formatPrice(positiveSpot)}', style: const TextStyle(fontSize: 14)),
        Text('+ USt (${taxRate.toStringAsFixed(0)}%): ${PriceUtils.formatPrice(posSpotBrutto - positiveSpot)}', style: const TextStyle(fontSize: 14)),
        Text('= SPOT inkl. USt: ${PriceUtils.formatPrice(posSpotBrutto)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        if (energyProviderPercentage > 0 || energyProviderFixedFee > 0)
          Text('+ Anbieter-Gebühr (inkl. USt): ${PriceUtils.formatPrice(posProviderFee)}', style: const TextStyle(fontSize: 14)),
        if (networkCosts > 0)
          Text('+ Netzentgelte (inkl. USt): ${PriceUtils.formatPrice(posNetworkCostsBrutto)}', style: const TextStyle(fontSize: 14)),
        const Divider(height: 8),
        Text(
          'Endpreis: ${PriceUtils.formatPrice(posFinalPrice)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 16),

        // Beispiel 2: Negativer SPOT-Preis
        const Text('Beispiel 2: Negativer SPOT-Preis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('SPOT-Preis (NETTO): ${PriceUtils.formatPrice(negativeSpot)}', style: const TextStyle(fontSize: 14)),
        Text('+ USt (${taxRate.toStringAsFixed(0)}%): ${PriceUtils.formatPrice(negSpotBrutto - negativeSpot)}', style: const TextStyle(fontSize: 14)),
        Text('= SPOT inkl. USt: ${PriceUtils.formatPrice(negSpotBrutto)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        if (energyProviderPercentage > 0 || energyProviderFixedFee > 0)
          Text('+ Anbieter-Gebühr (inkl. USt): ${PriceUtils.formatPrice(negProviderFee)}', style: const TextStyle(fontSize: 14)),
        if (networkCosts > 0)
          Text('+ Netzentgelte (inkl. USt): ${PriceUtils.formatPrice(negNetworkCostsBrutto)}', style: const TextStyle(fontSize: 14)),
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
                      Expanded(
                        child: Text(
                          'Was zeigen die Preise?',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                    '• Reine Börsenpreise',
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
                      Expanded(
                        child: Text(
                          'Strommarkt auswählen',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                      Expanded(
                        child: Text(
                          'Vollkosten-Modus',
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                        Expanded(
                          child: Text(
                            'Energieanbieter-Gebühren',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    isLoadingProviders
                      ? const CircularProgressIndicator()
                      : DropdownButtonFormField<EnergyProvider>(
                          value: selectedProvider,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Energieanbieter auswählen',
                            helperText: 'Gebühren inkl. ${taxRate.toStringAsFixed(0)}% USt',
                            border: const OutlineInputBorder(),
                          ),
                          items: availableProviders.map((provider) => DropdownMenuItem(
                            value: provider,
                            child: Text(
                              provider.providerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                selectedProvider = value;

                                // Set values from selected provider
                                energyProviderPercentage = value.markupPercentage;
                                energyProviderFixedFee = value.markupFixedCtKwh;
                                _percentageController.text = value.markupPercentage.toStringAsFixed(1);
                                _fixedFeeController.text = value.markupFixedCtKwh.toStringAsFixed(2);
                              });
                              _saveSettings();
                            }
                          },
                        ),
                    
                    // Show formula info for non-custom providers
                    if (selectedProvider != null && !selectedProvider!.isCustom) ...[
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
                            Expanded(
                              child: Text(
                                'Preisaufschlag: Epex Spot${selectedProvider!.markupPercentage > 0 ? ' + ${selectedProvider!.markupPercentage}%' : ''}${selectedProvider!.markupFixedCtKwh > 0 ? ' + ${selectedProvider!.markupFixedCtKwh} ct/kWh' : ''}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    // Energy provider fee configuration for custom
                    if (selectedProvider != null && selectedProvider!.isCustom) ...[
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Netzentgelte & Abgaben (inkl. ${taxRate.toStringAsFixed(0)}% USt)',
                        helperText: 'Bitte hier alle ct/kWh Posten Ihrer Rechnung + USt eintragen',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
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
                        Expanded(
                          child: Text(
                            'Beispiel-Rechnung',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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