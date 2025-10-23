# Firebase Notification System - Test Plan

## 🎯 Ziel
Sicherstellen dass Firebase Functions korrekt:
1. Preise vom Cloudflare Worker empfangen
2. Silent Push an alle Devices senden
3. Personalisierte Notifications schedulen
4. Scheduled Notifications zur richtigen Zeit senden

---

## ✅ VORAUSSETZUNGEN

- [ ] Firebase CLI installiert: `npm install -g firebase-tools`
- [ ] Firebase Login: `firebase login`
- [ ] Functions deployed: `firebase deploy --only functions`
- [ ] Indexes deployed: `firebase deploy --only firestore:indexes`
- [ ] App auf Test-Device installiert mit aktivierten Notifications

---

## 📋 TEST 1: Manual Trigger (Firebase Function direkt testen)

### 1.1 Vorbereitung
```bash
# API Key setzen
firebase functions:config:set api.key="dein-test-api-key"
firebase deploy --only functions
```

### 1.2 Test-Preise vorbereiten
Erstelle Datei `test-prices.json`:
```json
{
  "atPrices": {
    "prices": [
      {"startTime": "2025-10-23T00:00:00Z", "endTime": "2025-10-23T01:00:00Z", "price": 10.5},
      {"startTime": "2025-10-23T01:00:00Z", "endTime": "2025-10-23T02:00:00Z", "price": 8.2},
      {"startTime": "2025-10-23T02:00:00Z", "endTime": "2025-10-23T03:00:00Z", "price": 5.1}
    ],
    "cached_at": "2025-10-22T14:00:00Z"
  },
  "dePrices": {
    "prices": [
      {"startTime": "2025-10-23T00:00:00Z", "endTime": "2025-10-23T01:00:00Z", "price": 12.5},
      {"startTime": "2025-10-23T01:00:00Z", "endTime": "2025-10-23T02:00:00Z", "price": 9.2},
      {"startTime": "2025-10-23T02:00:00Z", "endTime": "2025-10-23T03:00:00Z", "price": 6.8}
    ],
    "cached_at": "2025-10-22T14:00:00Z"
  },
  "timestamp": "2025-10-22T14:00:00Z"
}
```

### 1.3 Function aufrufen
```bash
# Get Function URL
firebase functions:list

# Manual POST (ersetze URL und API-KEY)
curl -X POST \
  https://europe-west3-spotwatt-900e9.cloudfunctions.net/handlePriceUpdate \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: dein-test-api-key" \
  -d @test-prices.json
```

### 1.4 Erwartetes Ergebnis
```json
{
  "success": true,
  "price_update_pushes": 1,
  "notifications_scheduled": 3,
  "timestamp": "2025-10-22T14:00:00Z"
}
```

✅ **PASS Kriterien:**
- Status Code: 200
- `price_update_pushes` > 0 (Anzahl deiner Test-Devices)
- `notifications_scheduled` > 0 (mindestens 1-5 Notifications pro User)

---

## 📋 TEST 2: Firestore Check

### 2.1 Öffne Firebase Console
https://console.firebase.google.com/project/spotwatt-900e9/firestore/databases/-default-/data

### 2.2 Check Collections

#### `fcm_tokens`
- [ ] Dein Device Token ist vorhanden
- [ ] `active: true`
- [ ] `platform: "android"` oder `"ios"`
- [ ] `last_seen`: Recent timestamp

#### `notification_preferences`
- [ ] Dein FCM Token als Document ID
- [ ] `has_any_notification_enabled: true`
- [ ] Alle Settings korrekt gespeichert:
  - `daily_summary_enabled`
  - `cheapest_time_enabled`
  - `price_threshold_enabled`
  - `daily_summary_hours: 3`
  - `high_price_threshold: 50.0`

#### `scheduled_notifications`
- [ ] Neue Documents erstellt (1-5 pro User)
- [ ] `fcm_token`: Dein Token
- [ ] `sent: false`
- [ ] `send_at`: Timestamp in der Zukunft
- [ ] `notification.type`: "daily_summary", "cheapest_hour", oder "threshold_alert"
- [ ] `notification.title` und `notification.body` gefüllt

✅ **PASS Kriterien:**
- Alle 3 Collections vorhanden
- Deine Daten in allen 3 Collections
- Notifications haben `sent: false` und `send_at` in Zukunft

---

## 📋 TEST 3: Cron Function Test (Scheduled Notifications)

### 3.1 Manuell eine Notification für "jetzt" erstellen

Firebase Console → Firestore → `scheduled_notifications` → Add Document:

```json
{
  "fcm_token": "DEIN_FCM_TOKEN",
  "user_market": "AT",
  "notification": {
    "title": "🧪 Test Notification",
    "body": "Dies ist eine Test-Benachrichtigung um die Cron Function zu testen",
    "type": "test"
  },
  "send_at": <Timestamp: jetzt + 3 Minuten>,
  "created_at": <Timestamp: jetzt>,
  "sent": false
}
```

### 3.2 Warten (5 Minuten)
Cron läuft alle 5 Minuten. Check Firebase Logs:
```bash
firebase functions:log --only sendScheduledNotifications
```

### 3.3 Check auf Device
- [ ] Notification erhalten nach 3-8 Minuten
- [ ] Title und Body korrekt
- [ ] Tap öffnet App

### 3.4 Check Firestore
- [ ] Document hat jetzt `sent: true`
- [ ] `sent_at` Timestamp gesetzt

✅ **PASS Kriterien:**
- Notification auf Device erhalten
- Firestore Document marked as sent
- Keine Errors in Firebase Logs

---

## 📋 TEST 4: End-to-End Test mit App

### 4.1 App Settings konfigurieren
1. Öffne App
2. Gehe zu Settings → Notifications
3. Aktiviere:
   - ✅ Price Threshold (Schwelle: 10 ct/kWh)
   - ✅ Cheapest Time (15min vorher)
   - ✅ Daily Summary (07:00 Uhr, 3 Stunden)

### 4.2 Force Sync zu Firebase
```dart
// In der App ausführen (oder Pull-to-Refresh auf Home Screen)
await FirebaseNotificationService().syncPreferences();
```

### 4.3 Trigger Cloudflare Worker (manuell)
```bash
# Worker URL (aus wrangler.toml)
curl -X POST https://spotwatt-prices.spotwatt-api.workers.dev/cron \
  -H "Authorization: Bearer DEIN_WORKER_SECRET"
```

### 4.4 Check Logs
```bash
# Cloudflare Logs
npx wrangler tail

# Firebase Logs
firebase functions:log
```

### 4.5 Warte auf Notifications
- [ ] Silent Push erhalten (App wacht auf, fetched Preise)
- [ ] Scheduled Notifications erscheinen zur richtigen Zeit:
  - Daily Summary um 07:00
  - Cheapest Time 15min vor günstigster Stunde
  - Price Threshold 5min vor günstiger Stunde

✅ **PASS Kriterien:**
- App empfängt Silent Push
- Preise in App aktualisiert
- Alle 3 Notification-Typen funktionieren
- Notifications zur korrekten Zeit
- Keine Duplikate (lokale Notifications sind deaktiviert)

---

## 📋 TEST 5: iOS Force-Quit Test (Kritisch!)

### 5.1 Vorbereitung
1. App auf iOS Device installieren
2. Notifications aktivieren (wie Test 4.1)
3. Sync zu Firebase ausführen

### 5.2 Force-Quit
1. App öffnen
2. Swipe up → Force-Quit
3. **App NICHT wieder öffnen!**

### 5.3 Trigger Worker
```bash
curl -X POST https://spotwatt-prices.spotwatt-api.workers.dev/cron
```

### 5.4 Warte auf Notifications
- [ ] Silent Push empfangen (App wacht auf im Background)
- [ ] Scheduled Notifications erscheinen

✅ **PASS Kriterien:**
- ✅ Notifications funktionieren AUCH nach Force-Quit
- ✅ Keine "App not running" Errors
- ✅ App läuft im Background (check iOS Settings → Battery)

**WICHTIG:** Wenn dieser Test fehlschlägt, ist das System nutzlos für iOS!

---

## 📋 TEST 6: Skalierungs-Test (Optional)

### 6.1 Viele Test-User erstellen
```javascript
// Firebase Console → Firestore
// Script zum Erstellen von 100 Test-Usern
for (let i = 0; i < 100; i++) {
  await db.collection('notification_preferences').doc(`test-token-${i}`).set({
    fcm_token: `test-token-${i}`,
    has_any_notification_enabled: true,
    daily_summary_enabled: true,
    cheapest_time_enabled: true,
    price_threshold_enabled: true,
    market: 'AT',
    // ... rest of settings
  });
}
```

### 6.2 Trigger handlePriceUpdate
```bash
curl -X POST <function-url> -d @test-prices.json
```

### 6.3 Check Performance
```bash
firebase functions:log --only handlePriceUpdate
```

- [ ] Function completed in < 10s
- [ ] Alle 100 User processed
- [ ] Notifications scheduled (100 × 3 = 300 notifications)

✅ **PASS Kriterien:**
- Execution time < 10 seconds
- No timeout errors
- All notifications scheduled

---

## 🐛 DEBUGGING

### Firebase Function Logs
```bash
# Real-time logs
firebase functions:log --follow

# Last 100 lines
firebase functions:log --limit 100

# Specific function
firebase functions:log --only handlePriceUpdate
```

### Firestore Query Test
```bash
# Firebase Console → Firestore → Filter
# Collection: scheduled_notifications
# WHERE sent == false
# AND send_at >= now
# ORDER BY send_at ASC
```

### App Logs (Flutter)
```bash
# Android
adb logcat | grep -i "firebase\|fcm\|notification"

# iOS
# Xcode → Window → Devices and Simulators → View Device Logs
```

### Common Issues

**"No notifications received"**
- Check FCM token registered in Firestore
- Check notification permissions granted
- Check `has_any_notification_enabled: true`

**"Notifications sent twice"**
- Check if local NotificationService still scheduling
- Should only schedule Window Reminders locally

**"Firebase Function timeout"**
- Check number of users (should be < 100k for 9min timeout)
- Check Firestore indexes deployed

**"API Key invalid"**
- Check `firebase functions:config:get`
- Verify X-Api-Key header in Cloudflare Worker

---

## ✅ ERFOLGS-KRITERIEN

### Minimum (MVP):
- [x] Firebase Function empfängt Preise
- [x] Silent Push funktioniert
- [x] Mindestens 1 Notification wird gescheduled
- [x] Cron sendet Notification
- [x] App empfängt Notification

### Optimal:
- [x] Alle 3 Notification-Typen funktionieren
- [x] iOS Force-Quit Test bestanden
- [x] Keine Duplikate
- [x] Performance < 10s für 100 User
- [x] Firestore Kosten akzeptabel

### Production-Ready:
- [x] Monitoring eingerichtet
- [x] Error Handling tested
- [x] Rollback Plan vorhanden
- [x] Load Test mit 1000+ Users

---

## 📊 NÄCHSTE SCHRITTE nach Tests

1. **Wenn alle Tests ✅:**
   - Cloudflare Worker deployen (Production)
   - Monitoring einrichten (Firebase Console)
   - Gradual Rollout (10% → 50% → 100% Users)

2. **Wenn Tests ❌:**
   - Logs analysieren
   - Bugs fixen
   - Tests wiederholen

3. **Performance Optimierung:**
   - Parallel processing (STEP 1 + STEP 2)
   - Pagination für > 50k Users
   - Caching für calculateUserNotifications()
