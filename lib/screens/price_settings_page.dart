import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/price_utils.dart';

class PriceSettingsPage extends StatefulWidget {
  const PriceSettingsPage({Key? key}) : super(key: key);

  @override
  State<PriceSettingsPage> createState() => _PriceSettingsPageState();
}

class _PriceSettingsPageState extends State<PriceSettingsPage> {
  bool fullCostMode = false;
  double energyProviderFee = 2.5;
  double networkCosts = 8.5;
  bool includeTax = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      fullCostMode = prefs.getBool('full_cost_mode') ?? false;
      energyProviderFee = prefs.getDouble('energy_provider_fee') ?? 2.5;
      networkCosts = prefs.getDouble('network_costs') ?? 8.5;
      includeTax = prefs.getBool('include_tax') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('full_cost_mode', fullCostMode);
    await prefs.setDouble('energy_provider_fee', energyProviderFee);
    await prefs.setDouble('network_costs', networkCosts);
    await prefs.setBool('include_tax', includeTax);
  }

  Widget _buildExampleCalculation() {
    const spotPrice = 8.5; // Example spot price
    final withProviderFee = spotPrice + energyProviderFee;
    final withNetworkCosts = withProviderFee + networkCosts;
    final finalPrice = includeTax ? withNetworkCosts * 1.19 : withNetworkCosts;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SPOT-Preis: ${PriceUtils.formatPrice(spotPrice)}', style: const TextStyle(fontSize: 14)),
        Text('+ Anbieter-Gebühr: ${PriceUtils.formatPrice(withProviderFee)}', style: const TextStyle(fontSize: 14)),
        Text('+ Netzentgelte: ${PriceUtils.formatPrice(withNetworkCosts)}', style: const TextStyle(fontSize: 14)),
        if (includeTax)
          Text('+ USt (19%): ${PriceUtils.formatPrice(finalPrice)}', style: const TextStyle(fontSize: 14)),
        const Divider(height: 16),
        Text(
          'Endpreis: ${PriceUtils.formatPrice(finalPrice)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Diese Preise sind ideal für den Vergleich der günstigsten Stunden',
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      Icon(Icons.calculate, color: Theme.of(context).colorScheme.primary),
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
                    
                    // Energy provider fee
                    Text('Energieanbieter-Gebühr: ${PriceUtils.formatPrice(energyProviderFee)}'),
                    Slider(
                      value: energyProviderFee,
                      min: 0,
                      max: 10,
                      divisions: 20,
                      label: PriceUtils.formatPrice(energyProviderFee).replaceAll(' ct/kWh', ''),
                      onChanged: (value) async {
                        setState(() {
                          energyProviderFee = value;
                        });
                        await _saveSettings();
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Network costs
                    Text('Netzentgelte & Abgaben: ${PriceUtils.formatPrice(networkCosts)}'),
                    Slider(
                      value: networkCosts,
                      min: 5,
                      max: 15,
                      divisions: 20,
                      label: PriceUtils.formatPrice(networkCosts).replaceAll(' ct/kWh', ''),
                      onChanged: (value) async {
                        setState(() {
                          networkCosts = value;
                        });
                        await _saveSettings();
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Tax toggle
                    SwitchListTile(
                      title: const Text('Umsatzsteuer (20%)'),
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
                    const Row(
                      children: [
                        Icon(Icons.receipt_long, color: Colors.green, size: 20),
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
    );
  }
}