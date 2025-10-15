/// Energy Provider model matching API response
class EnergyProvider {
  final String providerName;
  final double markupPercentage;      // % auf SPOT-Preis
  final double markupFixedCtKwh;      // Fixer Aufschlag ct/kWh
  final double baseFeeMonthlyEur;     // Grundgebühr €/Monat (optional)

  const EnergyProvider({
    required this.providerName,
    required this.markupPercentage,
    required this.markupFixedCtKwh,
    required this.baseFeeMonthlyEur,
  });

  factory EnergyProvider.fromJson(Map<String, dynamic> json) {
    return EnergyProvider(
      providerName: json['provider_name'] as String,
      markupPercentage: (json['markup_percentage'] as num).toDouble(),
      markupFixedCtKwh: (json['markup_fixed_ct_kwh'] as num).toDouble(),
      baseFeeMonthlyEur: (json['base_fee_monthly_eur'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_name': providerName,
      'markup_percentage': markupPercentage,
      'markup_fixed_ct_kwh': markupFixedCtKwh,
      'base_fee_monthly_eur': baseFeeMonthlyEur,
    };
  }

  /// Check if this is the custom provider
  bool get isCustom => providerName == 'Benutzerdefiniert';
}

/// Provider data response from API (includes tax rate)
class ProviderDataResponse {
  final String region;
  final double taxRate;
  final List<EnergyProvider> providers;
  final int version;
  final DateTime lastUpdated;

  const ProviderDataResponse({
    required this.region,
    required this.taxRate,
    required this.providers,
    required this.version,
    required this.lastUpdated,
  });

  factory ProviderDataResponse.fromJson(Map<String, dynamic> json) {
    return ProviderDataResponse(
      region: json['region'] as String,
      taxRate: (json['tax_rate'] as num).toDouble(),
      providers: (json['providers'] as List)
          .map((p) => EnergyProvider.fromJson(p as Map<String, dynamic>))
          .toList(),
      version: json['version'] as int,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'region': region,
      'tax_rate': taxRate,
      'providers': providers.map((p) => p.toJson()).toList(),
      'version': version,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}
