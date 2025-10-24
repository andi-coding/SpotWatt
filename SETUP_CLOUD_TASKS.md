# ⚡ Cloud Tasks Setup - WICHTIG!

## 🚨 NÄCHSTER SCHRITT: Cloud Tasks Queue erstellen

Die Firebase Functions sind deployed, aber **Cloud Tasks kann noch keine Notifications senden**, weil die Queue fehlt!

## 📋 Setup in 2 Minuten

### Option 1: Via Google Cloud Console (empfohlen)

1. **Öffne**: https://console.cloud.google.com/cloudtasks?project=spotwatt-900e9

2. **Klicke auf** "Create Queue"

3. **Eingeben:**
   - **Name:** `notification-queue`
   - **Region:** `europe-west3`
   - **Rate limits:** (Standard-Werte lassen)

4. **Klicke auf** "Create"

✅ **Fertig!** Die Queue ist jetzt aktiv.

### Option 2: Via gcloud CLI

```bash
gcloud tasks queues create notification-queue \
  --location=europe-west3 \
  --project=spotwatt-900e9
```

## ✅ Überprüfung

Nach dem Erstellen der Queue:

1. **App öffnen** → Benachrichtigungs-Einstellungen
2. **Einstellung ändern** (z.B. Tägliche Zusammenfassung aktivieren)
3. **Warte 5 Sekunden**
4. **Cloud Console öffnen** → Cloud Tasks → notification-queue
5. **Du solltest sehen:** Tasks in der Queue!

## 📊 Logs prüfen

```bash
cd firebase
npx firebase functions:log --only onPreferencesUpdate
```

Erwartete Ausgabe:
```
[Prefs Update] Processing for token: ...
[Cloud Tasks] ✅ Created task: daily_summary at 2025-10-24T14:00:00.000Z
[Prefs Update] ✅ Rescheduled 3 notifications
```

## 🔧 Troubleshooting

### Fehler: "Queue 'notification-queue' not found"

**Lösung:** Queue wurde noch nicht erstellt → Siehe Option 1 oder 2 oben

### Fehler: "Permission denied"

**Lösung:** Setze Invoker-Berechtigung:
```bash
gcloud functions add-invoker-policy-binding executeNotificationTask \
  --region=europe-west3 \
  --member=allUsers \
  --project=spotwatt-900e9
```

## 📚 Weitere Infos

Vollständige Dokumentation: `doc/CLOUD_TASKS_MIGRATION.md`

---

**Status:** ⏳ Queue muss noch erstellt werden
**Deployed:** ✅ Firebase Functions sind live
**URL:** https://europe-west3-spotwatt-900e9.cloudfunctions.net/executeNotificationTask
