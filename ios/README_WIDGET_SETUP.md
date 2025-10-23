# iOS Widget Setup Anleitung

## Übersicht

Das iOS Widget ist eine **native Swift WidgetKit Extension**, die unabhängig von der Flutter App läuft.

**Architektur:**
- Widget Extension macht eigene API-Calls zu Cloudflare Worker
- Berechnet Vollkosten, 3h-Trend und Status selbst (Swift-Logik)
- Funktioniert auch nach App Force Quit
- Timeline wird alle 24-48h im Voraus berechnet
- Auto-Reload täglich um 17:30 Uhr (neue Preise für morgen)

## Schritt 1: Widget Extension Target in Xcode erstellen

1. Öffne `ios/Runner.xcworkspace` in Xcode
2. File → New → Target
3. Wähle **Widget Extension**
4. Name: `PriceWidget`
5. Bundle ID: `com.spotwatt.app.PriceWidget`
6. ✅ **Include Configuration Intent** - NICHT aktivieren!
7. Klicke **Finish**
8. Wenn gefragt "Activate scheme?" → **Cancel** (wir aktivieren es später)

## Schritt 2: Widget Extension Dateien hinzufügen

### Option A: Über Xcode (empfohlen)

1. Im Xcode Project Navigator, wähle den **PriceWidget** Ordner
2. Lösche die von Xcode generierten Dateien:
   - `PriceWidget.swift` (wird ersetzt)
   - `AppIntent.swift` (nicht benötigt)
3. Rechtsklick auf **PriceWidget** Ordner → **Add Files to "Runner"...**
4. Navigiere zu `ios/PriceWidget/`
5. Wähle ALLE `.swift` Dateien aus:
   - `PriceWidget.swift`
   - `PriceEntry.swift`
   - `Provider.swift`
   - `PriceCalculator.swift`
   - `CloudflarePriceService.swift`
   - `WidgetView.swift`
6. ✅ **Copy items if needed** aktivieren
7. ✅ Target: **PriceWidget** auswählen
8. Klicke **Add**

### Option B: Manuell (falls Option A nicht funktioniert)

Die Dateien sind bereits unter `ios/PriceWidget/` erstellt.
Du musst sie nur noch in Xcode zum Target hinzufügen (siehe Option A).

## Schritt 3: App Group konfigurieren

**WICHTIG:** App Group ermöglicht Datenaustausch zwischen App und Widget.

### 3.1 App Group ID erstellen (Apple Developer Portal)

1. Gehe zu [Apple Developer Portal](https://developer.apple.com/account/)
2. Certificates, Identifiers & Profiles → Identifiers
3. Klicke **+** (neue Identifier)
4. Wähle **App Groups** → Continue
5. Description: `SpotWatt App Group`
6. Identifier: `group.com.spotwatt.app`
7. Klicke **Register**

### 3.2 App Group in Xcode aktivieren

#### Für Main App (Runner):
1. Wähle **Runner** Target
2. Signing & Capabilities Tab
3. Klicke **+ Capability**
4. Wähle **App Groups**
5. ✅ Aktiviere: `group.com.spotwatt.app`
   - Falls nicht vorhanden: Klicke **+** und füge hinzu

#### Für Widget Extension (PriceWidget):
1. Wähle **PriceWidget** Target
2. Signing & Capabilities Tab
3. Klicke **+ Capability**
4. Wähle **App Groups**
5. ✅ Aktiviere: `group.com.spotwatt.app`

## Schritt 4: Bundle IDs und Signing konfigurieren

### Main App (Runner):
- Bundle ID: `com.spotwatt.app`
- Team: **Dein Team auswählen**
- Signing: Automatically manage signing ✅

### Widget Extension (PriceWidget):
- Bundle ID: `com.spotwatt.app.PriceWidget`
- Team: **Gleiche wie Main App**
- Signing: Automatically manage signing ✅

## Schritt 5: Info.plist prüfen

Die `Info.plist` für das Widget ist bereits erstellt unter:
`ios/PriceWidget/Info.plist`

Falls nicht vorhanden, erstelle sie mit diesem Inhalt:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>SpotWatt</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

## Schritt 6: Build Settings überprüfen

### PriceWidget Target:
1. Build Settings Tab
2. Suche nach **iOS Deployment Target**
3. Setze auf: **iOS 14.0** (gleich wie Main App)

## Schritt 7: Build & Run

1. Wähle **Runner** scheme (nicht PriceWidget!)
2. Wähle Simulator oder echtes Gerät
3. Klicke **Run** (⌘R)
4. App sollte ohne Fehler builden

### Widget testen:

#### Im Simulator:
1. Starte die App
2. Drücke Home Button
3. Long-Press auf Home Screen
4. Klicke **+** (oben links)
5. Suche nach "SpotWatt"
6. Wähle **SpotWatt Preis** Widget
7. Wähle Medium Size
8. Klicke **Add Widget**

#### Auf echtem Gerät:
- Gleiche Schritte wie Simulator

## Troubleshooting

### "No such module 'WidgetKit'"
→ **Lösung:** PriceWidget Target → Build Settings → iOS Deployment Target auf 14.0+

### "App Group nicht gefunden"
→ **Lösung:**
1. Apple Developer Portal: App Group erstellen
2. Xcode: Beide Targets müssen App Group aktiviert haben
3. Clean Build Folder (⇧⌘K) und neu builden

### Widget zeigt nur Placeholder
→ **Lösung:**
1. App starten (Widget Config wird synchronisiert)
2. Pull-to-Refresh in der App (lädt Preise)
3. Widget sollte nach ~30 Sekunden updaten

### Widget zeigt Fehler
→ **Lösung:**
1. Xcode Console öffnen
2. Filter: "PriceWidget" oder "Provider"
3. Logs zeigen Fehlerdetails

### Build Fehler: "Signing for PriceWidget requires a development team"
→ **Lösung:** PriceWidget Target → Signing → Team auswählen

## Widget Funktionsweise

### Timeline-Strategie:
```
17:30 Uhr: Widget Extension wacht auf
           ↓
       API-Call zu Cloudflare Worker
           ↓
       Berechne Vollkosten (wenn aktiviert)
           ↓
       Berechne Timeline für nächste 24-48h
       (Ein Entry pro Stunde mit Preis, Trend, Status)
           ↓
       Timeline an WidgetKit übergeben
           ↓
18:00 Uhr: WidgetKit zeigt Entry für 18:00
19:00 Uhr: WidgetKit zeigt Entry für 19:00
... (ohne dass Code läuft)
           ↓
17:30 Uhr (nächster Tag): Neuer Reload
```

### Datenfluss:
```
Flutter App (Dart)
    ↓ (via home_widget plugin)
App Group Container (UserDefaults)
    ├─ energy_provider_percentage
    ├─ energy_provider_fixed_fee
    ├─ network_costs
    ├─ include_tax
    ├─ region (AT/DE)
    ├─ full_cost_mode
    └─ theme_mode
    ↓ (gelesen von Widget Extension)
Widget Extension (Swift)
    ↓ (macht API-Call)
Cloudflare Worker
    ↓ (liefert SPOT-Preise)
Widget Extension (Swift)
    ├─ Berechnet Vollkosten
    ├─ Berechnet 3h-Trend
    ├─ Berechnet Status (Median)
    ├─ Erstellt Timeline
    └─ Zeigt Widget UI
```

## Nächste Schritte

1. ✅ Widget Extension in Xcode erstellen
2. ✅ App Group konfigurieren
3. ✅ Build & Run testen
4. 📱 Auf echtem Gerät testen
5. 🚀 Widget im App Store (automatisch mit App)

## Support

Bei Problemen:
- Xcode Console Logs prüfen (Filter: "PriceWidget")
- Flutter Logs prüfen: `flutter run` (Widget Config Sync)
- GitHub Issues: [SpotWatt Repo](https://github.com/andi-coding/SpotWatt)
