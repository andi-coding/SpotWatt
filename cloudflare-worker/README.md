# SpotWatt CloudFlare Worker - ENTSO-E Integration

Dieser CloudFlare Worker holt Strompreise direkt von der ENTSO-E Transparency Platform API für Deutschland und Österreich.

## Setup

### 1. KV Namespace erstellen (für Caching)
```bash
npx wrangler kv:namespace create "PRICE_CACHE"
```
Kopiere die generierte ID und trage sie in `wrangler.toml` bei `id = "YOUR_KV_NAMESPACE_ID"` ein.

### 2. ENTSO-E API Token hinzufügen
```bash
npx wrangler secret put ENTSOE_API_TOKEN
```
Gib deinen ENTSO-E API Token ein wenn du dazu aufgefordert wirst.

### 3. Worker deployen
```bash
npm run deploy
```

## Lokales Testen

```bash
npm run dev
```

Teste dann mit:
- http://localhost:8787?market=DE (für Deutschland)
- http://localhost:8787?market=AT (für Österreich)

## API Endpunkte

### GET /?market={AT|DE}
Gibt die aktuellen und zukünftigen Strompreise zurück.

**Response Format:**
```json
{
  "lastUpdate": "2024-01-17T14:00:00Z",
  "market": "DE",
  "prices": [
    {
      "startTime": "2024-01-17T00:00:00Z",
      "endTime": "2024-01-17T01:00:00Z",
      "price": 8.5  // in ct/kWh
    }
  ]
}
```

## ENTSO-E API Details

Der Worker nutzt folgende ENTSO-E API Parameter:
- **Document Type:** A44 (Day-ahead prices)
- **Market Areas:**
  - Deutschland: `10Y1001A1001A82H`
  - Österreich: `10YAT-APG------L`

## Caching

- Preise werden für 1 Stunde im KV Store gecacht
- Ein Cron Job läuft täglich um 14:00 UTC (15:00 MEZ) um neue Preise zu holen

## Entwicklung

```bash
# Installiere Abhängigkeiten
npm install

# Lokale Entwicklung
npm run dev

# Deploy zu CloudFlare
npm run deploy

# Logs anzeigen
npm run tail
```