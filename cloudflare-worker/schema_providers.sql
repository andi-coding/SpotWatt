-- Energy Provider Database Schema
-- Stores pricing formulas for different energy providers by region

-- Tax rates by region
CREATE TABLE IF NOT EXISTS tax_rates (
  region TEXT PRIMARY KEY,
  tax_percentage REAL NOT NULL,
  effective_from DATE DEFAULT CURRENT_DATE,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Energy providers with pricing formulas
CREATE TABLE IF NOT EXISTS energy_providers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  provider_name TEXT NOT NULL,
  region TEXT NOT NULL CHECK(region IN ('AT', 'DE')),

  -- Flexible pricing model (matches existing app formula)
  -- Formula: |spot * markup_percentage/100| + markup_fixed_ct_kwh
  markup_percentage REAL DEFAULT 0,         -- Prozentaufschlag auf SPOT (%)
  markup_fixed_ct_kwh REAL DEFAULT 0,       -- Fixer Aufschlag (ct/kWh)

  -- Optional: Monthly base fee (for display/comparison only)
  base_fee_monthly_eur REAL DEFAULT 0,      -- Grundgebühr (€/Monat)

  -- Metadata
  display_order INTEGER DEFAULT 0,
  active INTEGER DEFAULT 1,
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(provider_name, region)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_region_active
ON energy_providers(region, active, display_order);

-- ============================================
-- Initial data
-- ============================================

-- Tax rates
INSERT INTO tax_rates (region, tax_percentage, effective_from) VALUES
  ('AT', 20.0, '1984-01-01'),
  ('DE', 19.0, '2007-01-01')
ON CONFLICT(region) DO NOTHING;

-- Austrian providers (all 18 active providers + Benutzerdefiniert)
INSERT INTO energy_providers
  (provider_name, region, markup_percentage, markup_fixed_ct_kwh, base_fee_monthly_eur, display_order, active)
VALUES
  ('Benutzerdefiniert', 'AT', 0.0, 0.0, 0.0, 0, 1),
  ('aWATTar HOURLY', 'AT', 3.0, 1.8, 5.75, 1, 1),
  ('TIWAG flex privat', 'AT', 0.0, 1.44, 2.00, 2, 1),
  ('AAE Naturstrom SPOT Stunde II', 'AT', 0.0, 1.56, 2.16, 3, 1),
  ('smartENERGY smartCONTROL', 'AT', 0.0, 1.44, 2.99, 4, 1),
  ('oekostrom Spot+', 'AT', 0.0, 1.80, 2.16, 5, 1),
  ('Spotty Smart Active', 'AT', 0.0, 1.79, 2.40, 6, 1),
  ('Energie Steiermark E1 Floater', 'AT', 0.0, 1.44, 3.82, 7, 1),
  ('HOFER GRÜNSTROM SPOT', 'AT', 0.0, 1.90, 4.98, 8, 1),
  ('Verbund V-Strom SPOT', 'AT', 4.0, 1.30, 5.99, 9, 1),
  ('wüsterstrom Spot', 'AT', 0.0, 1.80, 5.75, 10, 1),
  ('Kittel Mühle Aquavento Flex Smart', 'AT', 5.0, 2.04, 4.20, 11, 1),
  ('Wien Energie OPTIMA Voll Aktiv', 'AT', 7.0, 1.42, 5.50, 12, 1),
  ('AVIA STROM PLUS STUNDENFLOATER', 'AT', 3.0, 2.34, 3.99, 13, 1),
  ('Energie AG Ökostrom Spot', 'AT', 0.0, 3.00, 3.90, 14, 1),
  ('Wels Strom Privat Strom SPOT', 'AT', 0.0, 3.48, 3.48, 15, 1),
  ('Stadtwerke Klagenfurt EKG Strom Flex', 'AT', 0.0, 3.60, 4.99, 16, 1),
  ('schlau-pv Spot', 'AT', 0.0, 5.40, 6.21, 17, 1),
  ('Energie Steiermark SteirerStrom Spot', 'AT', 0.0, 9.816, 7.19, 18, 1)
ON CONFLICT(provider_name, region) DO UPDATE SET
  markup_percentage = EXCLUDED.markup_percentage,
  markup_fixed_ct_kwh = EXCLUDED.markup_fixed_ct_kwh,
  base_fee_monthly_eur = EXCLUDED.base_fee_monthly_eur,
  display_order = EXCLUDED.display_order,
  active = EXCLUDED.active,
  last_updated = CURRENT_TIMESTAMP;

-- German providers
INSERT INTO energy_providers
  (provider_name, region, markup_percentage, markup_fixed_ct_kwh, base_fee_monthly_eur, display_order, active)
VALUES
  ('Benutzerdefiniert', 'DE', 0.0, 0.0, 0.0, 0, 1),
  ('Tibber', 'DE', 3.9, 1.0, 5.99, 1, 1),
  ('E.ON Flex', 'DE', 18.0, 2.5, 9.90, 2, 1),
  ('Vattenfall Dynamic', 'DE', 0.0, 7.8, 11.90, 3, 1)
ON CONFLICT(provider_name, region) DO NOTHING;
