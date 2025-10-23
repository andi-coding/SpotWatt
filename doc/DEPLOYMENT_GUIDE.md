# SpotWatt Deployment Guide
## Firebase Notifications Migration

Diese Anleitung beschreibt den Deployment-Prozess für das neue Firebase-basierte Notification-System.

---

## 📋 Übersicht

**Was wurde geändert:**
- ✅ Cloudflare Worker: Nur noch 1 HTTP Call zu Firebase (statt N FCM calls)
- ✅ Firebase Functions: Handhabt alle Notifications (Silent Push + Scheduled)
- ✅ App: Synct Preferences zu Firestore
- ✅ Timeout-basiertes Overlapping Prevention (< 5min)

**Vorteile:**
- ✅ Skaliert unbegrenzt (nicht mehr limitiert auf 49 User)
- ✅ iOS Force-Quit Problem gelöst
- ✅ Vollkosten-Berechnung server-side
- ✅ 5-Minuten Präzision (ausreichend für Strompreise)

---

## 🚀 Deployment Schritte

### 1. Firebase Functions Deploy

```bash
cd firebase/functions

# Dependencies installieren
npm install

# Zurück ins firebase Verzeichnis
cd ..

# API Key konfigurieren (für Cloudflare→Firebase Communication)
firebase functions:config:set api.key="IHR-GEHEIMER-API-KEY-HIER"

# Config prüfen
firebase functions:config:get

# Firestore Indexes deployen
firebase deploy --only firestore:indexes

# Functions deployen
firebase deploy --only functions

# Deployed Functions URL notieren:
# https://europe-west3-spotwatt-900e9.cloudfunctions.net/handlePriceUpdate
```

### 2. Cloudflare Worker Deploy

```bash
cd cloudflare-worker

# Secrets konfigurieren
npx wrangler secret put FIREBASE_API_KEY
# Eingeben: (gleicher Key wie oben)

# Optional: Custom Firebase URL (falls anders)
# Füge zu wrangler.toml hinzu:
# [vars]
# FIREBASE_FUNCTION_URL = "https://europe-west3-YOUR-PROJECT.cloudfunctions.net/handlePriceUpdate"

# Deploy
npx wrangler deploy

# Test: Manual trigger
npx wrangler tail  # In separatem Terminal
# Dann in Dashboard: Quick Edit > "Test" Button
```

### 3. App Build & Deploy

```bash
# pubspec.yaml: cloud_firestore dependency hinzufügen (falls nicht vorhanden)
# dependencies:
#   cloud_firestore: ^4.13.6

# Dependencies installieren
flutter pub get

# Build für Android
flutter build apk --release

# Build für iOS (auf Mac)
flutter build ios --release

# Play Store / App Store Upload
# (Normale Prozedur)
```

---

## 🧪 Testing

### Test 1: Firebase Functions Local Emulator

```bash
cd firebase/functions

# Emulator starten
npm run serve

# In separatem Terminal: Test Request
curl -X POST http://localhost:5001/spotwatt-900e9/europe-west3/handlePriceUpdate \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: development-key" \
  -d '{
    "atPrices": {
      "prices": [
        {"startTime": "2025-10-22T00:00:00Z", "price": 8.5},
        {"startTime": "2025-10-22T01:00:00Z", "price": 7.2}
      ]
    },
    "dePrices": {
      "prices": [
        {"startTime": "2025-10-22T00:00:00Z", "price": 9.1},
        {"startTime": "2025-10-22T01:00:00Z", "price": 8.3}
      ]
    },
    "timestamp": "2025-10-22T14:00:00Z"
  }'

# Expected Response:
# {
#   "success": true,
#   "price_update_pushes": 0,  # (keine Tokens im Emulator)
#   "notifications_scheduled": 0
# }
```

### Test 2: Production Test (Single User)

**Voraussetzung:** Mindestens 1 User mit aktiven Notifications

```bash
# 1. App installieren und Notifications aktivieren

# 2. Firestore Console öffnen:
# https://console.firebase.google.com/project/spotwatt-900e9/firestore

# 3. Prüfen ob User in `notification_preferences` existiert

# 4. Manual trigger via Cloudflare Worker:
# https://dash.cloudflare.com/
# → Workers → spotwatt-prices → Quick Edit → Trigger

# 5. Firebase Functions Logs ansehen:
firebase functions:log --only handlePriceUpdate

# 6. Check ob Notification empfangen wurde (auf Device)
```

### Test 3: Scheduled Notifications (5-Minuten Cron)

```bash
# 1. Warte 5 Minuten (oder trigger manuell via Cloud Scheduler)

# 2. Logs ansehen:
firebase functions:log --only sendScheduledNotifications

# Expected Output:
# "Processing X notifications"
# "Sent: X, Failed: Y"
```

---

## 📊 Monitoring

### Firebase Console
https://console.firebase.google.com/project/spotwatt-900e9

**Wichtige Metriken:**
- Functions → Invocations (sollte ~288/day für sendScheduledNotifications sein)
- Functions → Execution Time (sollte < 60s sein, max 280s)
- Functions → Errors (sollte 0 sein)

### Cloudflare Dashboard
https://dash.cloudflare.com/

**Worker Logs:**
```bash
npx wrangler tail
```

**Wichtige Metriken:**
- Requests (sollte ~5 Cron Jobs/day sein)
- Errors (sollte 0 sein)
- Subrequests (sollte ~5-10/request sein, nicht 50+!)

### Firestore Usage
https://console.firebase.google.com/project/spotwatt-900e9/usage

**Free Tier Limits:**
- Reads: 50k/day ✅ (sollte < 10k sein bei 1000 Usern)
- Writes: 20k/day ✅ (sollte < 5k sein)
- Storage: 1GB ✅

---

## 🔧 Troubleshooting

### Problem: "Failed to send to XXX: UNREGISTERED"
**Lösung:** Token ist invalide, wird automatisch auf `active: false` gesetzt

### Problem: Function Timeout nach 280s
**Lösung:**
- Check Firestore Query Performance
- Erhöhe Memory: `memory: '2GB'`
- Reduziere Limit: `limit(1000)` statt `limit(2000)`

### Problem: Duplicate Notifications
**Ursache:** Overlapping Functions (beide laufen gleichzeitig)
**Lösung:** Bereits implementiert! Timeout < 5min verhindert Overlapping

### Problem: Keine Notifications auf iOS nach Force-Quit
**Check:**
1. Silent Push erfolgreich? (Logs: "Price Update Push: Sent: X")
2. App wacht auf? (App Logs)
3. Scheduled Notifications geplant? (Firestore: `scheduled_notifications`)

### Problem: Firestore "Index required" Error
**Lösung:**
```bash
firebase deploy --only firestore:indexes
```

---

## 🔄 Rollback Plan

Falls Probleme auftreten:

### Option 1: Zurück zu altem System

```dart
// In cloudflare-worker/src/index.js
// Kommentiere aus:
// await triggerFirebaseNotifications(env);

// Kommentiere ein:
await sendFCMPushNotifications(env);
```

```bash
# Redeploy
npx wrangler deploy
```

### Option 2: Hybrid Mode

Beide Systeme parallel laufen lassen:

```javascript
// Cloudflare Worker
await triggerFirebaseNotifications(env);  // NEW
await sendFCMPushNotifications(env);      // OLD (Fallback)
```

**Nachteil:** Duplicate Silent Pushes (aber funktioniert)

---

## 📈 Migration Timeline

### Phase 1: Testing (1-2 Tage)
- Deploy zu Production
- Teste mit eigenen Devices
- Monitor Logs

### Phase 2: Beta User (3-7 Tage)
- Aktiviere für Beta-Tester
- Sammle Feedback
- Fix Bugs

### Phase 3: Full Rollout
- Aktiviere für alle User
- Remove old FCM system aus Worker
- Cleanup alte D1 Database

---

## 💰 Kosten Kalkulation

### Bei 1,000 Usern
- Firebase Functions: **$0** (Free Tier)
- Firestore: **$0** (Free Tier)
- Cloudflare: **$0** (Free Tier)
- **TOTAL: $0/Monat**

### Bei 10,000 Usern
- Firebase Functions: **$0** (noch im Free Tier)
- Firestore: **$0.60/Monat** (60k reads/day)
- Cloudflare: **$0** (Free Tier)
- **TOTAL: $0.60/Monat**

### Bei 50,000 Usern
- Firebase Functions: **$3/Monat**
- Firestore: **$10/Monat**
- Cloudflare: **$0** (oder $5 Paid Plan)
- **TOTAL: $13-18/Monat**

---

## 📞 Support

Bei Fragen oder Problemen:
- Firebase Console: https://console.firebase.google.com/project/spotwatt-900e9
- Cloudflare Dashboard: https://dash.cloudflare.com/
- Logs: `firebase functions:log` oder `npx wrangler tail`
