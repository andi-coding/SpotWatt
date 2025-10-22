# Firestore TTL Setup für automatisches Notification Cleanup

## Was ist Firestore TTL?

Firestore kann Dokumente **automatisch löschen** basierend auf einem Timestamp-Feld (`expireAt`). Dies verhindert, dass alte Notifications dauerhaft gespeichert bleiben und Storage-Kosten verursachen.

## Wie funktioniert es?

1. Jede Notification bekommt ein `expireAt` Feld (basierend auf Notification-Type)
2. Firestore löscht Dokumente automatisch wenn `expireAt < now`
3. Löschung erfolgt innerhalb von **24-72 Stunden** nach Ablauf

## Setup (einmalig)

### Voraussetzungen
- Firebase CLI installiert: `npm install -g firebase-tools`
- Google Cloud SDK installiert: https://cloud.google.com/sdk/docs/install
- Eingeloggt mit Admin-Rechten

### 1. Firebase CLI Login
```bash
firebase login
```

### 2. Google Cloud SDK Login
```bash
gcloud auth login
gcloud config set project spotwatt-900e9
```

### 3. TTL Policy aktivieren
```bash
gcloud firestore fields ttls update expireAt \
  --collection-group=scheduled_notifications \
  --enable-ttl
```

**Erwartete Ausgabe:**
```
Enabling TTL policy for expireAt in scheduled_notifications...
✓ TTL policy enabled successfully
```

### 4. Verifizierung
```bash
gcloud firestore fields ttls list --collection-group=scheduled_notifications
```

**Erwartete Ausgabe:**
```
FIELD_PATH  STATE
expireAt    ACTIVE
```

## Wie lange werden Notifications aufbewahrt?

| Notification Type   | TTL nach send_at | Grund                           |
|---------------------|------------------|---------------------------------|
| `threshold_alert`   | 15 Minuten       | Sehr zeitkritisch (Preisalarm)  |
| `cheapest_hour`     | 15 Minuten       | Zeitkritisch (günstigste Stunde)|
| `daily_summary`     | 2 Stunden        | Weniger zeitkritisch            |
| Sonstige            | 30 Minuten       | Default                         |

## Beispiel

```javascript
// Notification scheduled für 15:00 Uhr (cheapest_hour)
send_at:  2025-10-22T15:00:00Z
expireAt: 2025-10-22T15:15:00Z  // +15 Minuten

// Firestore löscht automatisch zwischen:
// 2025-10-22T15:15:00Z und 2025-10-24T15:15:00Z (24-72h später)
```

## Was passiert wenn TTL nicht aktiv ist?

- ❌ Alte Notifications bleiben dauerhaft in Firestore
- ❌ Storage-Kosten steigen kontinuierlich
- ⚠️ Firestore wird mit alten Daten zugemüllt

## Troubleshooting

### "Permission denied" Fehler
```bash
# Stelle sicher, dass du Owner/Editor-Rechte hast:
gcloud projects get-iam-policy spotwatt-900e9
```

### TTL funktioniert nicht
```bash
# Prüfe ob Policy aktiv ist:
gcloud firestore fields ttls list --collection-group=scheduled_notifications

# Falls STATE=CREATING: Warte 15-30 Minuten
# Falls STATE=NEEDS_REPAIR: Kontaktiere Firebase Support
```

### TTL zu langsam (24-72h zu lang)
Das ist normal! Firestore TTL ist für Background-Cleanup gedacht, nicht für sofortige Löschung.

**Unsere Lösung:**
- FCM TTL verhindert veraltete Zustellung (10-120 Minuten)
- Firestore TTL ist nur Backup-Cleanup (24-72 Stunden)

## Monitoring

### Anzahl offener Notifications prüfen
```bash
# Firebase Console → Firestore → scheduled_notifications
# Oder via Firebase CLI:
firebase firestore:indexes
```

### Alte Notifications manuell löschen (falls nötig)
```javascript
// In Firebase Console → Firestore → Query:
// where sent == true
// where sent_at < (7 Tage alt)
// → Batch delete
```

## Status

- ✅ Code implementiert (expireAt Feld wird gesetzt)
- ⚠️ TTL Policy muss manuell aktiviert werden (siehe oben)
- ✅ FCM TTL aktiv (verhindert veraltete Zustellung)

## Nächste Schritte

1. **Jetzt:** Führe Setup-Befehle aus (siehe oben)
2. **Deployment:** `firebase deploy --only functions`
3. **Test:** Warte 24-72h und prüfe ob alte Notifications gelöscht werden
