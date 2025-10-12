# Development Scripts

This folder contains utility scripts for testing and development.

## test_fcm_push.js

Test script to send a Firebase Cloud Messaging (FCM) push notification to a device.

**Requirements:**
- Node.js (native modules only, no external dependencies)
- Firebase Service Account Key JSON file

**Usage:**

1. Download the Firebase Service Account Key from Firebase Console:
   - Go to: https://console.firebase.google.com/project/spotwatt-900e9/settings/serviceaccounts/adminsdk
   - Click "Generate new private key"
   - Save the JSON file

2. Update the script with:
   - Path to your service account key file
   - Device token (get from app logs or D1 database)

3. Run the script:
   ```bash
   node scripts/test_fcm_push.js
   ```

**What it does:**
- Generates OAuth2 access token using JWT
- Sends FCM data message with `action: "update_prices"`
- Wakes up the app in background to fetch latest prices

**Expected output:**
```
🔑 Getting access token...
✅ Access token obtained
📤 Sending FCM message...
Token: frHzxVhsRTikZDzJs...
✅ FCM message sent successfully!
```

**Testing in production:**

To get device token from D1 database:
```bash
cd cloudflare-worker
npx wrangler d1 execute spotwatt-fcm-tokens --remote --command "SELECT token FROM fcm_tokens WHERE active = 1 LIMIT 1"
```

**Security Note:**
- Never commit the Firebase Service Account Key JSON file to git!
- The script reads the key from your local Downloads folder
- Update the path if you store it elsewhere
