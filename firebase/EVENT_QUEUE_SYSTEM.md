# Event Queue System (Option 3 Implementation)

## Übersicht

Das Event-Queue-System ermöglicht es, dass bei Änderungen der Notification Settings in der App alle bereits geplanten Firebase Notifications sofort gecancelt und mit den neuen Settings neu geplant werden.

## Architektur

```
App (Flutter)                    Firestore                    Cloud Function
     |                               |                              |
     | Settings ändern               |                              |
     |------------------------------>|                              |
     | syncPreferences()             |                              |
     |                               |                              |
     | Event schreiben               |                              |
     |------------------------------>|                              |
     | notification_events           |                              |
     |                               |---trigger------------------>|
     |                               | onCreate                    |
     |                               |                             |
     |                               |<--delete pending---------- |
     |                               |   notifications            |
     |                               |                            |
     |                               |<--reschedule-------------- |
     |                               |   with new settings        |
```

## Komponenten

### 1. App-seitig (Flutter)

**File:** `lib/services/firebase_notification_service.dart`

- **Debouncing:** Verhindert, dass bei schnellen Änderungen (z.B. Slider bewegen) zu viele Events geschrieben werden
- **Delay:** 90 Sekunden (1.5 Minuten) nach der **letzten** Änderung
- **Trailing Edge:** Timer wird bei jeder Änderung neu gestartet
- **Event-Typ:** `settings_changed`

```dart
// Wird automatisch nach syncPreferences() aufgerufen
await _triggerSettingsChangedEvent(fcmToken);

// Beispiel 1: User ändert Settings und wartet
// 0:00 - Threshold ändern → Timer startet (90s)
// 0:30 - Cheapest Time aktivieren → Timer neu starten (90s)
// 1:00 - Daily Summary Zeit ändern → Timer neu starten (90s)
// 1:30 - Quiet Time einstellen → Timer neu starten (90s)
// 3:00 - Timer läuft ab → 1 Event wird getriggert ✅

// Beispiel 2: User verlässt Settings-Page
// 0:00 - Threshold ändern → Timer startet (90s)
// 0:30 - Cheapest Time aktivieren → Timer neu starten (90s)
// 1:00 - User verlässt Settings → Event wird SOFORT getriggert ✅
```

**Flush on Page Leave:**
- `dispose()` in NotificationSettingsPage ruft `flushPendingEvents()` auf
- Pending Timer wird gecancelt und Event sofort getriggert
- User muss nicht 90s warten!

### 2. Cloud Function (Firebase)

**File:** `firebase/functions/index.js`

**Function:** `processNotificationEvents`
- **Trigger:** Firestore onCreate auf `notification_events/{eventId}`
- **Timeout:** 120 Sekunden
- **Memory:** 512MB

**Workflow:**
1. Event wird empfangen
2. Je nach `event_type` wird der entsprechende Handler aufgerufen
3. Bei Erfolg: Event wird gelöscht
4. Bei Fehler: Event wird mit Fehlerinfo markiert (für Debugging)

**Handler: `handleSettingsChanged(fcmToken)`**
1. Alle ungeplanten Notifications für User löschen
2. User Preferences aus Firestore holen
3. Aktuelle Preise aus Cache holen (`price_cache` collection)
4. Neue Notifications berechnen
5. Neue Notifications in `scheduled_notifications` schreiben

## Event Types

| Event Type | Beschreibung | Status |
|------------|--------------|--------|
| `settings_changed` | User hat Notification Settings geändert | ✅ Implementiert |
| `reminder_added` | User hat Window Reminder hinzugefügt | 🔮 Geplant |
| `all_reminders_cancelled` | User hat alle Reminders gelöscht | 🔮 Geplant |

## Firestore Collections

### `notification_events`

Temporäre Collection für Events.

```json
{
  "fcm_token": "string",
  "event_type": "settings_changed",
  "timestamp": "timestamp",
  "processed": false
}
```

Events werden nach erfolgreicher Verarbeitung **gelöscht**.
Bei Fehler werden sie mit `processed: true` und `error` markiert.

### `price_cache`

Cache für die neuesten Preise (für Rescheduling).

```json
{
  "prices": [...],
  "updated_at": "timestamp"
}
```

Documents: `AT`, `DE`

## Firestore Indexes

**Benötigt für:**
```javascript
// Query in cancelUserNotifications()
.where('fcm_token', '==', fcmToken)
.where('sent', '==', false)

// Query in cancelAllWindowReminders()
.where('fcm_token', '==', fcmToken)
.where('notification.type', '==', 'window_reminder')
.where('sent', '==', false)
```

**Index-Konfiguration:** Siehe `firebase/firestore.indexes.json`

## Deployment

```bash
# Deploy nur die neue Function
cd firebase/functions
firebase deploy --only functions:processNotificationEvents

# Deploy Indexes
cd firebase
firebase deploy --only firestore:indexes
```

## Testing

### 1. Manual Test

```bash
# In App: Settings ändern
# In Firebase Console: notification_events ansehen
# Expected: Event erscheint und wird sofort gelöscht
# Expected: scheduled_notifications werden neu erstellt
```

### 2. Logs ansehen

```bash
firebase functions:log --only processNotificationEvents
```

**Expected Output:**
```
📨 Processing event: settings_changed for token: xxx
[Settings Changed] Cancelled 12 pending notifications
[Settings Changed] ✅ Rescheduled 15 notifications
✅ Event xxx processed and deleted
```

## Performance

- **Debouncing:** 90s trailing edge - User kann alle Settings in Ruhe ändern
- **Batching:** Firestore writes in batches of 500
- **Timeout:** 120s ist ausreichend für tausende Notifications
- **Cost:** ~1 Event pro Settings-Session (nicht pro einzelnem Setting)
- **Beispiel:** User ändert 10 Settings in 5 Minuten → Nur 1 Event (statt 10)

## Vorteile gegenüber Option 1 (Firestore Trigger)

✅ **Kosteneffizienz:** Nur Events bei echten Änderungen
✅ **Debugging:** Events sind sichtbar in Firestore
✅ **Erweiterbar:** Einfach neue Event-Typen hinzufügen
✅ **Batching:** Mehrere Settings-Änderungen = 1 Event
✅ **Audit-Trail:** Historische Events (optional)

## Troubleshooting

### Event wird nicht verarbeitet

1. Check Firebase Console → Functions → Logs
2. Check Firestore → `notification_events` → Sind Events mit `processed: true, error: ...` da?
3. Check Firestore Rules → Muss Cloud Function Zugriff haben

### Notifications werden nicht neu geplant

1. Check: Sind Preise im Cache? (`price_cache/AT` und `price_cache/DE`)
2. Check: Hat User `has_any_notification_enabled: true`?
3. Check: Logs der Cloud Function ansehen

### Zu viele Events

1. Check: Ist Debouncing aktiv? (2 Sekunden Delay)
2. Check: Wird `syncPreferences()` zu oft aufgerufen?
