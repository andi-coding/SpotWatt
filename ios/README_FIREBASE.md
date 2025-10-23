# Firebase Setup für iOS

## Aktueller Status
⚠️ Der GitHub Actions Build verwendet einen **Placeholder** für die Firebase-Konfiguration.
Die App wird builden, aber **Push-Notifications funktionieren nicht**.

## Für produktive Builds benötigt:

### 1. GoogleService-Info.plist erstellen

1. Gehe zur [Firebase Console](https://console.firebase.google.com/)
2. Wähle das Projekt: **spotwatt-900e9**
3. Gehe zu: **Project Settings** → **General**
4. Scrolle zu "Your apps" → **iOS app**
5. Falls noch nicht vorhanden: **Add app** → iOS
   - Bundle ID: `com.spotwatt.app`
6. Download **GoogleService-Info.plist**

### 2. Secrets in GitHub hinterlegen

Gehe zu: **GitHub Repository** → **Settings** → **Secrets and variables** → **Actions**

Erstelle folgendes Secret:
- **Name:** `IOS_FIREBASE_CONFIG`
- **Wert:** Kompletter Inhalt der `GoogleService-Info.plist` Datei

### 3. Workflow anpassen

Ersetze in `.github/workflows/ios-build.yml` den "Setup Firebase Config" Step:

```yaml
- name: Setup Firebase Config (iOS)
  run: |
    echo "${{ secrets.IOS_FIREBASE_CONFIG }}" > ios/Runner/GoogleService-Info.plist
```

### 4. firebase_options.dart aktualisieren

Aktualisiere `/lib/firebase_options.dart` mit den korrekten Werten aus GoogleService-Info.plist:

```dart
static const FirebaseOptions ios = FirebaseOptions(
  apiKey: '<API_KEY aus GoogleService-Info.plist>',
  appId: '<GOOGLE_APP_ID aus GoogleService-Info.plist>',
  messagingSenderId: '<GCM_SENDER_ID aus GoogleService-Info.plist>',
  projectId: 'spotwatt-900e9',
  storageBucket: 'spotwatt-900e9.firebasestorage.app',
  iosBundleId: 'com.spotwatt.app',
);
```

## Lokale Entwicklung

Für lokale Entwicklung:
1. `GoogleService-Info.plist` nach `ios/Runner/` kopieren
2. In Xcode: File → Add Files to "Runner" → GoogleService-Info.plist
3. ✅ "Copy items if needed" aktivieren
4. ✅ "Runner" Target auswählen

⚠️ **WICHTIG:** `GoogleService-Info.plist` ist in `.gitignore` und wird nicht committed!

## Überprüfung

Nach Firebase-Setup sollte funktionieren:
- ✅ FCM Push Notifications
- ✅ Firebase Cloud Messaging
- ✅ Price Alert Notifications
- ✅ Daily Summary Notifications

## Support

Bei Problemen:
- Firebase Console: https://console.firebase.google.com/project/spotwatt-900e9
- Firebase iOS Docs: https://firebase.google.com/docs/ios/setup
