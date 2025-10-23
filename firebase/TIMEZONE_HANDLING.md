# Timezone Handling in Firebase Notifications

## Problem

Cloud Functions laufen in **UTC**, aber User erwarten Notifications in ihrer **lokalen Timezone** (z.B. Vienna Time = UTC+1 oder UTC+2).

**Ohne Timezone-Handling:**
- User stellt "7:00 Uhr" Daily Summary ein
- Function plant für 7:00 Uhr UTC
- Notification kommt 1-2 Stunden zu spät! ❌

## Lösung

### 1. **Timezone in User Preferences speichern**

`lib/services/firebase_notification_service.dart`:

```dart
'timezone': DateTime.now().timeZoneOffset.inMinutes, // z.B. +60 für UTC+1
'timezone_name': DateTime.now().timeZoneName, // z.B. "CEST"
```

**Beispiele:**
- Vienna Winter (CET): `timezone: 60` (UTC+1)
- Vienna Summer (CEST): `timezone: 120` (UTC+2)
- Berlin: Gleich wie Vienna
- London Winter (GMT): `timezone: 0` (UTC+0)
- London Summer (BST): `timezone: 60` (UTC+1)

### 2. **Cloud Function konvertiert Zeiten**

`firebase/functions/index.js`:

```javascript
// User Timezone Offset aus Preferences
const userTimezoneOffset = user.timezone || 60; // Default: UTC+1

// UTC → User Local Time
const toUserLocalTime = (utcDate) => {
  const date = new Date(utcDate);
  date.setMinutes(date.getMinutes() + userTimezoneOffset);
  return date;
};

// User Local Time → UTC (für Firestore)
const toUTC = (localDate) => {
  const date = new Date(localDate);
  date.setMinutes(date.getMinutes() - userTimezoneOffset);
  return date;
};
```

### 3. **Daily Summary Beispiel**

User stellt "7:00 Uhr" ein, Timezone ist Vienna (UTC+1 = +60 min):

```javascript
// User input: 7:00 Uhr Vienna Time
const [hour, minute] = '07:00'.split(':');

// 1. Erstelle Zeit in User Local Time
let localSendAt = toUserLocalTime(now); // Now in Vienna Time
localSendAt.setHours(7, 0, 0, 0); // 7:00 Vienna Time

// 2. Konvertiere zu UTC für Firestore
let sendAt = toUTC(localSendAt); // = 6:00 UTC
sendAt = roundToNearestFiveMinutes(sendAt); // = 6:00 UTC

// 3. Speichere in Firestore
// send_at: 6:00 UTC (wird um 7:00 Vienna Time versendet) ✅
```

### 4. **Quiet Time Beispiel**

User stellt "22:00 - 06:00 Uhr" Quiet Time ein:

```javascript
function isInQuietTime(utcDate, user, userTimezoneOffset) {
  // 1. Konvertiere UTC zu User Local Time
  const localDate = new Date(utcDate);
  localDate.setMinutes(localDate.getMinutes() + userTimezoneOffset);

  // 2. Prüfe gegen User's Quiet Time
  const minutes = localDate.getHours() * 60 + localDate.getMinutes();
  const startMinutes = 22 * 60; // 22:00
  const endMinutes = 6 * 60;    // 06:00

  // 3. Check if in quiet time (in user's local time)
  return minutes >= startMinutes || minutes < endMinutes;
}
```

**Beispiel:**
- Notification geplant für: 5:30 UTC
- Vienna Time (UTC+1): 5:30 + 60min = 6:30 Vienna Time
- Quiet Time: 22:00 - 06:00
- 6:30 ist NICHT in Quiet Time → Notification wird versendet ✅

## Wichtige Punkte

### ✅ **Was wird in User Local Time berechnet:**
1. Daily Summary Zeit (z.B. "7:00 Uhr")
2. Quiet Time Start/End (z.B. "22:00 - 06:00")
3. Tag-Vergleiche für Daily Summary (welcher Tag ist "heute"?)

### ✅ **Was bleibt in UTC:**
1. Preise `startTime/endTime` (kommen schon in UTC vom API)
2. `send_at` Timestamp in Firestore (für Cron Job)
3. `now` = `new Date()` in Cloud Function

### ✅ **Konvertierungs-Regeln:**
- **User Input → Function:** Local Time → UTC (subtract offset)
- **Function → Firestore:** UTC
- **Firestore → Versenden:** UTC (Cron Job versendet zur richtigen Zeit)
- **Function → User Display:** UTC → Local Time (add offset)

## Testing

### Test 1: Daily Summary zur richtigen Zeit

```
User Settings:
- Timezone: Vienna (UTC+1 = +60 min)
- Daily Summary: 7:00 Uhr

Expected:
- Firestore send_at: 6:00 UTC
- Notification arrives: 7:00 Vienna Time ✅
```

### Test 2: Quiet Time funktioniert

```
User Settings:
- Timezone: Vienna (UTC+1)
- Quiet Time: 22:00 - 06:00

Notification geplant für:
- 5:30 UTC = 6:30 Vienna → NOT in quiet time ✅
- 4:30 UTC = 5:30 Vienna → IN quiet time ❌ (wird übersprungen)
```

### Test 3: Cheapest Hour zur richtigen Zeit

```
Cheapest Hour:
- Start Time: 14:00 UTC (= 15:00 Vienna)
- Notification Minutes Before: 15min
- Expected Notification: 14:45 Vienna Time

Calculation:
- startTime: 14:00 UTC
- minus 15min: 13:45 UTC
- In Vienna: 14:45 ✅
```

## Sommerzeit / Winterzeit

Das System funktioniert automatisch mit DST (Daylight Saving Time):

- **App speichert:** `DateTime.now().timeZoneOffset.inMinutes`
- **Wert ändert sich automatisch:**
  - Winter (CET): +60 min
  - Sommer (CEST): +120 min
- **Bei jedem Settings-Update** wird neuer Offset gespeichert
- **Cloud Function verwendet** immer den aktuellen Offset

**User muss NICHTS tun!** ✅

## Firestore Schema

```json
{
  "notification_preferences": {
    "<fcm_token>": {
      "timezone": 60,           // Offset in Minuten
      "timezone_name": "CEST",  // Für Debugging
      "daily_summary_time": "07:00", // In User Local Time!
      "quiet_time_start_hour": 22,   // In User Local Time!
      "quiet_time_end_hour": 6,      // In User Local Time!
      ...
    }
  }
}
```

## Deployment

```bash
# Deploy Functions mit Timezone-Handling
cd firebase
firebase deploy --only functions:handlePriceUpdate,functions:processNotificationEvents
```

## Troubleshooting

### Notification kommt zur falschen Zeit

1. Check User Preferences in Firestore:
   ```javascript
   // Erwarteter Wert für Vienna:
   timezone: 60  // Winter (CET)
   timezone: 120 // Sommer (CEST)
   ```

2. Check `send_at` in `scheduled_notifications`:
   ```javascript
   // Für "7:00 Vienna" sollte send_at sein:
   send_at: 6:00 UTC (Winter)
   send_at: 5:00 UTC (Sommer)
   ```

3. Check Function Logs:
   ```bash
   firebase functions:log --only handlePriceUpdate
   ```

### User in anderer Timezone (z.B. Deutschland → Portugal)

1. User öffnet App in neuer Timezone
2. Bei nächstem Settings-Update: Neuer Offset wird gespeichert
3. Notifications werden automatisch für neue Timezone geplant ✅

**WICHTIG:** Wenn User nicht die Settings öffnet, bleibt alter Offset!
- Lösung: App könnte Timezone bei jedem App-Start updaten (optional)
