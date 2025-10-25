# iOS Firebase & Push Notifications Setup Guide

## Current Status

### ✅ Already Configured
- **Flutter Dependencies**: Firebase packages are already in `pubspec.yaml`:
  - `firebase_core: ^3.8.1`
  - `firebase_messaging: ^15.1.5`
  - `cloud_firestore: ^5.6.0`
- **Info.plist**: Background modes for remote notifications already configured (line 49-52)
- **App Groups**: Configured in `Runner.entitlements` for widget communication
- **Development Team**: Set to `74X9LPL7NY` in Xcode project
- **Bundle ID**: `com.spotwatt.app`

### ❌ Missing for iOS

1. **GoogleService-Info.plist** - iOS Firebase configuration file (Android version exists)
2. **Firebase initialization in AppDelegate.swift**
3. **APNs certificate/authentication key** configured in Firebase Console
4. **Push notification entitlements** in Runner.entitlements
5. **iOS app registered** in Firebase Console

---

## Step-by-Step Setup

### 1. Download GoogleService-Info.plist

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `spotwatt-900e9`
3. Click the **gear icon** → **Project Settings**
4. Scroll down to **Your apps** section
5. If iOS app exists:
   - Click on the iOS app (`com.spotwatt.app`)
   - Download `GoogleService-Info.plist`
6. If iOS app doesn't exist:
   - Click **Add app** → **iOS**
   - Enter Bundle ID: `com.spotwatt.app`
   - Enter App nickname: `SpotWatt iOS`
   - Download `GoogleService-Info.plist`
7. Save the file to: `D:\SpottWatt\ios\Runner\GoogleService-Info.plist`

### 2. Add GoogleService-Info.plist to Xcode

**Option A: Using Xcode (Recommended)**
1. Open `ios/Runner.xcworkspace` in Xcode (NOT `.xcodeproj`)
2. Right-click on `Runner` folder in Project Navigator
3. Select **Add Files to "Runner"...**
4. Select `GoogleService-Info.plist`
5. Check **Copy items if needed**
6. Check **Runner** target
7. Click **Add**

**Option B: Manual (if Xcode unavailable)**
The file will be automatically picked up by CocoaPods when you run `pod install`.

### 3. Update AppDelegate.swift

Current AppDelegate.swift is minimal and missing Firebase initialization.

**File: `ios/Runner/AppDelegate.swift`**

Replace the current content with:

```swift
import Flutter
import UIKit
import Firebase  // Add this import

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase
    FirebaseApp.configure()

    // Register Flutter plugins
    GeneratedPluginRegistrant.register(with: self)

    // Request notification permissions (iOS 10+)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }

    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle FCM token refresh
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Pass device token to Firebase
    // The firebase_messaging plugin handles this automatically
  }

  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register for remote notifications: \(error)")
  }
}
```

### 4. Update Runner.entitlements

**File: `ios/Runner/Runner.entitlements`**

Add push notification capabilities:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.spotwatt.app</string>
	</array>
	<!-- Add these lines for push notifications -->
	<key>aps-environment</key>
	<string>development</string>  <!-- Change to 'production' for App Store builds -->
</dict>
</plist>
```

### 5. Configure APNs in Firebase Console

Firebase requires an APNs authentication key or certificate to send push notifications to iOS.

**Option A: APNs Authentication Key (Recommended - easier)**

1. Go to [Apple Developer Account](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Select **Keys** from the sidebar
4. Click **+** to create a new key
5. Enter a name: `SpotWatt APNs Key`
6. Check **Apple Push Notifications service (APNs)**
7. Click **Continue** → **Register**
8. Download the `.p8` file (save it securely - you can only download once!)
9. Note the **Key ID** (10 characters)
10. Note your **Team ID** (found in Membership page): `74X9LPL7NY`

**Upload to Firebase:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: `spotwatt-900e9`
3. Go to **Project Settings** → **Cloud Messaging** tab
4. Scroll to **Apple app configuration**
5. Click **Upload** under **APNs authentication key**
6. Upload the `.p8` file
7. Enter **Key ID**
8. Enter **Team ID**: `74X9LPL7NY`
9. Click **Upload**

**Option B: APNs Certificate (Legacy)**
Not recommended - use Authentication Key instead.

### 6. Install CocoaPods Dependencies

```bash
cd ios
pod install
```

This will:
- Install Firebase iOS SDKs
- Configure Xcode project with Firebase dependencies
- Link all Flutter plugins

### 7. Update Info.plist (Optional but Recommended)

Add notification permission description for better UX:

**File: `ios/Runner/Info.plist`**

Add before `</dict>`:

```xml
<key>NSUserNotificationUsageDescription</key>
<string>SpotWatt benötigt Benachrichtigungen, um Sie über günstige Strompreise zu informieren.</string>
```

### 8. Build and Test

```bash
# From project root
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter build ios --debug
```

---

## Verification Checklist

- [ ] `GoogleService-Info.plist` exists in `ios/Runner/`
- [ ] `GoogleService-Info.plist` added to Xcode project (Runner target)
- [ ] `AppDelegate.swift` imports Firebase and calls `FirebaseApp.configure()`
- [ ] `Runner.entitlements` includes `aps-environment`
- [ ] APNs authentication key uploaded to Firebase Console
- [ ] `pod install` completed successfully
- [ ] iOS app builds without errors
- [ ] FCM token is generated on app launch (check logs)
- [ ] Test notification received on device

---

## Testing Push Notifications

### Test via Firebase Console

1. Go to Firebase Console → **Messaging** (previously Cloud Messaging)
2. Click **Create your first campaign** or **New campaign**
3. Select **Firebase Notification messages**
4. Enter test notification:
   - **Title**: `Test`
   - **Body**: `This is a test notification`
5. Click **Send test message**
6. Enter the FCM token from your iOS device
7. Click **Test**

### Get FCM Token from iOS Device

Add this to your Flutter app temporarily to get the token:

```dart
// In lib/main.dart or wherever Firebase is initialized
FirebaseMessaging.instance.getToken().then((token) {
  print("FCM Token: $token");
});
```

Check Xcode console for the token when app launches.

### Test via Cloud Tasks

Once notifications work, test via the actual Cloud Tasks system:
1. Change a notification preference in the app
2. Check Firebase Functions logs for task creation
3. Wait for scheduled time
4. Verify notification arrives

---

## Common Issues & Solutions

### Issue: "Firebase not configured"
**Solution**: Ensure `FirebaseApp.configure()` is called in `AppDelegate.swift` before `GeneratedPluginRegistrant.register()`

### Issue: "No APNs token"
**Solution**:
- Ensure device is physical (not simulator)
- Check that APNs key is uploaded to Firebase
- Verify bundle ID matches: `com.spotwatt.app`
- Check `aps-environment` in entitlements

### Issue: Notifications not received
**Solution**:
- Check notification permissions are granted
- Verify FCM token is generated (check logs)
- Test with Firebase Console first
- Check Firebase Functions logs for errors
- Ensure APNs key is valid and uploaded

### Issue: Build fails with Firebase errors
**Solution**:
```bash
cd ios
pod deintegrate
pod install
```

### Issue: "App is not authorized to use APNs"
**Solution**:
- Create App ID in Apple Developer Portal with Push Notifications enabled
- Regenerate provisioning profile
- Ensure APNs key has correct Team ID

---

## Differences from Android

| Feature | Android | iOS |
|---------|---------|-----|
| Config file | `google-services.json` | `GoogleService-Info.plist` |
| Location | `android/app/` | `ios/Runner/` |
| Push service | FCM only | FCM → APNs |
| Auth required | No (FCM handles it) | Yes (APNs key/cert) |
| Test on emulator | ✅ Yes | ❌ No (physical device only) |
| Background refresh | ✅ Reliable | ⚠️ Limited by iOS |
| Notification permission | Auto-granted | User must explicitly grant |

---

## Production Checklist

Before App Store release:

- [ ] Change `aps-environment` from `development` to `production` in `Runner.entitlements`
- [ ] Upload production APNs certificate (if using certificates instead of keys)
- [ ] Test on TestFlight
- [ ] Verify background notifications work
- [ ] Test notification actions (if implemented)
- [ ] Ensure all privacy descriptions are in Info.plist
- [ ] Test on multiple iOS versions (iOS 13+)

---

## Next Steps

1. Download `GoogleService-Info.plist` from Firebase Console
2. Update `AppDelegate.swift` with Firebase initialization
3. Update `Runner.entitlements` with APNs environment
4. Create and upload APNs authentication key to Firebase
5. Run `pod install`
6. Build and test on physical iOS device

---

## Resources

- [Firebase iOS Setup](https://firebase.google.com/docs/ios/setup)
- [FCM iOS Setup](https://firebase.google.com/docs/cloud-messaging/ios/client)
- [APNs Overview](https://developer.apple.com/documentation/usernotifications)
- [Flutter Firebase Messaging](https://firebase.flutter.dev/docs/messaging/overview/)
