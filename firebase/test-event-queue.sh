#!/bin/bash

# Test script for Event Queue System
# Tests the settings_changed event flow

echo "🧪 Testing Event Queue System"
echo "=============================="
echo ""

# Get Firebase project ID
PROJECT_ID=$(firebase use | grep -oP '\(([^)]+)\)' | tr -d '()')

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Could not determine Firebase project ID"
    exit 1
fi

echo "📋 Project: $PROJECT_ID"
echo ""

# Test FCM token (replace with real token from your device)
FCM_TOKEN="test_token_12345"

echo "⚠️  IMPORTANT: Replace FCM_TOKEN in this script with a real token from your device!"
echo "   You can find it in the app logs when it starts up."
echo ""

read -p "Do you want to continue with test token '$FCM_TOKEN'? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted"
    exit 1
fi

echo ""
echo "📝 Step 1: Writing test event to Firestore..."
echo ""

# Write test event
firebase firestore:set "notification_events/test_event_$(date +%s)" \
  --project "$PROJECT_ID" \
  --data '{
    "fcm_token": "'"$FCM_TOKEN"'",
    "event_type": "settings_changed",
    "timestamp": {"_seconds": '$(date +%s)', "_nanoseconds": 0},
    "processed": false
  }'

echo ""
echo "✅ Test event written!"
echo ""
echo "📊 Step 2: Checking if event is processed..."
echo "   (Cloud Function should trigger automatically)"
echo ""

sleep 5

echo "📋 Recent logs from processNotificationEvents:"
echo "================================================"
firebase functions:log --only processNotificationEvents -n 10

echo ""
echo "🔍 Step 3: Verify in Firebase Console:"
echo "   1. Check if event was deleted from notification_events"
echo "   2. Check if notifications were created in scheduled_notifications"
echo "   3. Check Function logs for success message"
echo ""
echo "🌐 Open Firebase Console:"
echo "   https://console.firebase.google.com/project/$PROJECT_ID/firestore/data"
echo ""
