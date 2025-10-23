# SpotWatt Firebase Functions

Firebase Functions für die SpotWatt App - Handhabt alle Notification-Logik.

## Setup

### 1. Firebase CLI installieren

```bash
npm install -g firebase-tools
```

### 2. Firebase Login

```bash
firebase login
```

### 3. Firebase Project initialisieren

```bash
cd firebase
firebase use spotwatt-900e9  # Oder deine Project ID
```

### 4. Dependencies installieren

```bash
cd functions
npm install
```

### 5. Environment Variables konfigurieren

```bash
# API Key für Cloudflare Worker Communication
firebase functions:config:set api.key="your-secret-api-key-here"

# Check config
firebase functions:config:get
```

### 6. Firestore Indexes erstellen

Die Indexes werden automatisch aus `firestore.indexes.json` deployed.

```bash
firebase deploy --only firestore:indexes
```

### 7. Functions deployen

```bash
firebase deploy --only functions
```

## Architektur

### Functions

#### 1. `handlePriceUpdate` (HTTP Triggered)
- **Trigger**: HTTP POST von Cloudflare Worker
- **Frequency**: 1x täglich (nach Preis-Update um ~14:00)
- **Tasks**:
  - Sendet Silent Push zu allen Geräten (Price Update Signal)
  - Plant personalisierte Notifications für nächste 24h

#### 2. `sendScheduledNotifications` (Cron Triggered)
- **Trigger**: Cron `every 5 minutes`
- **Timeout**: 280 Sekunden (< 5min um Overlapping zu verhindern!)
- **Tasks**:
  - Sendet fällige Notifications aus Firestore
  - Markiert gesendete als `sent: true`
  - Cleanup invalid FCM tokens

## Firestore Collections

### `fcm_tokens`
Alle registrierten FCM Tokens für Silent Push.

```json
{
  "token": "fcm_token_string",
  "platform": "android" | "ios",
  "active": true,
  "last_seen": timestamp,
  "created_at": timestamp
}
```

### `notification_preferences`
User Notification Einstellungen.

```json
{
  "fcm_token": "fcm_token_string",
  "market": "AT" | "DE",
  "has_any_notification_enabled": true,

  // Daily Summary
  "daily_summary_enabled": true,
  "daily_summary_time": "14:00",

  // Cheapest Hour
  "cheapest_time_enabled": true,
  "notification_minutes_before": 15,

  // Price Threshold
  "price_threshold_enabled": true,
  "notification_threshold": 10.0,

  // Full Cost Mode
  "full_cost_mode": false,
  "energy_provider_percentage": 3.5,
  "energy_provider_fixed_fee": 1.2,
  "network_costs": 8.5,
  "include_tax": true,
  "tax_rate": 20.0,

  // Quiet Time
  "quiet_time_enabled": false,
  "quiet_time_start_hour": 22,
  "quiet_time_start_minute": 0,
  "quiet_time_end_hour": 6,
  "quiet_time_end_minute": 0
}
```

### `scheduled_notifications`
Geplante Notifications (werden alle 5min abgearbeitet).

```json
{
  "fcm_token": "fcm_token_string",
  "user_market": "AT",
  "notification": {
    "title": "💡 Günstige Stunde naht!",
    "body": "Um 14:30: 8.5 ct/kWh",
    "type": "cheapest_hour" | "daily_summary" | "threshold_alert"
  },
  "send_at": timestamp,
  "sent": false,
  "sent_at": timestamp | null,
  "created_at": timestamp
}
```

## Testing

### Local Emulator

```bash
cd functions
npm run serve
```

### Trigger handlePriceUpdate manuell

```bash
curl -X POST http://localhost:5001/spotwatt-900e9/europe-west3/handlePriceUpdate \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: development-key" \
  -d '{
    "atPrices": { "prices": [...] },
    "dePrices": { "prices": [...] },
    "timestamp": "2025-10-22T14:00:00Z"
  }'
```

### Logs ansehen

```bash
firebase functions:log
```

## Monitoring

### Cloud Console
https://console.firebase.google.com/project/spotwatt-900e9/functions

### Metrics
- Function invocations
- Execution time
- Error rate
- FCM success rate

## Kosten (Free Tier Limits)

- **Functions**: 2M Invocations/month ✅
- **Firestore Reads**: 50k/day ✅
- **Firestore Writes**: 20k/day ✅
- **FCM Messages**: Unlimited ✅

**Geschätzte Kosten bei 10k Usern**: $0/month (im Free Tier)

## Troubleshooting

### "Permission denied" Fehler
```bash
firebase login --reauth
```

### Function timeout
- Erhöhe `timeoutSeconds` in `runWith()`
- Check Memory: `memory: '1GB'` → `'2GB'`

### FCM Token invalide
- Tokens werden automatisch auf `active: false` gesetzt
- App registriert sich neu beim nächsten Start

### Firestore Index fehlt
```bash
firebase deploy --only firestore:indexes
```
