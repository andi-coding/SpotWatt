#!/bin/bash

# Quick Test Script für Firebase Notification System
# Usage: ./test-manual-trigger.sh

set -e

echo "🧪 Firebase Notification System - Quick Test"
echo "==========================================="

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found!"
    echo "Install with: npm install -g firebase-tools"
    exit 1
fi

# Get Firebase project
PROJECT_ID=$(firebase use | grep "active project" | awk '{print $NF}' | tr -d '()')
echo "✅ Project: $PROJECT_ID"

# Get function URL
echo ""
echo "📡 Getting function URL..."
FUNCTION_URL="https://europe-west3-${PROJECT_ID}.cloudfunctions.net/handlePriceUpdate"
echo "URL: $FUNCTION_URL"

# Get API Key
echo ""
echo "🔑 Getting API Key..."
API_KEY=$(firebase functions:config:get api.key 2>/dev/null || echo "development-key")
echo "API Key: ${API_KEY:0:10}..."

# Create test prices JSON
echo ""
echo "📝 Creating test prices..."
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOMORROW=$(date -u -d "+1 day" +"%Y-%m-%d")

cat > /tmp/test-prices.json <<EOF
{
  "atPrices": {
    "prices": [
      {"startTime": "${TOMORROW}T00:00:00Z", "endTime": "${TOMORROW}T01:00:00Z", "price": 10.5},
      {"startTime": "${TOMORROW}T01:00:00Z", "endTime": "${TOMORROW}T02:00:00Z", "price": 8.2},
      {"startTime": "${TOMORROW}T02:00:00Z", "endTime": "${TOMORROW}T03:00:00Z", "price": 5.1},
      {"startTime": "${TOMORROW}T03:00:00Z", "endTime": "${TOMORROW}T04:00:00Z", "price": 12.3},
      {"startTime": "${TOMORROW}T04:00:00Z", "endTime": "${TOMORROW}T05:00:00Z", "price": 15.8},
      {"startTime": "${TOMORROW}T05:00:00Z", "endTime": "${TOMORROW}T06:00:00Z", "price": 18.2},
      {"startTime": "${TOMORROW}T06:00:00Z", "endTime": "${TOMORROW}T07:00:00Z", "price": 22.1},
      {"startTime": "${TOMORROW}T07:00:00Z", "endTime": "${TOMORROW}T08:00:00Z", "price": 25.4},
      {"startTime": "${TOMORROW}T08:00:00Z", "endTime": "${TOMORROW}T09:00:00Z", "price": 28.7},
      {"startTime": "${TOMORROW}T09:00:00Z", "endTime": "${TOMORROW}T10:00:00Z", "price": 30.2},
      {"startTime": "${TOMORROW}T10:00:00Z", "endTime": "${TOMORROW}T11:00:00Z", "price": 28.9},
      {"startTime": "${TOMORROW}T11:00:00Z", "endTime": "${TOMORROW}T12:00:00Z", "price": 26.5},
      {"startTime": "${TOMORROW}T12:00:00Z", "endTime": "${TOMORROW}T13:00:00Z", "price": 24.3},
      {"startTime": "${TOMORROW}T13:00:00Z", "endTime": "${TOMORROW}T14:00:00Z", "price": 22.8},
      {"startTime": "${TOMORROW}T14:00:00Z", "endTime": "${TOMORROW}T15:00:00Z", "price": 20.5},
      {"startTime": "${TOMORROW}T15:00:00Z", "endTime": "${TOMORROW}T16:00:00Z", "price": 18.9},
      {"startTime": "${TOMORROW}T16:00:00Z", "endTime": "${TOMORROW}T17:00:00Z", "price": 21.2},
      {"startTime": "${TOMORROW}T17:00:00Z", "endTime": "${TOMORROW}T18:00:00Z", "price": 25.6},
      {"startTime": "${TOMORROW}T18:00:00Z", "endTime": "${TOMORROW}T19:00:00Z", "price": 32.1},
      {"startTime": "${TOMORROW}T19:00:00Z", "endTime": "${TOMORROW}T20:00:00Z", "price": 35.4},
      {"startTime": "${TOMORROW}T20:00:00Z", "endTime": "${TOMORROW}T21:00:00Z", "price": 28.7},
      {"startTime": "${TOMORROW}T21:00:00Z", "endTime": "${TOMORROW}T22:00:00Z", "price": 22.3},
      {"startTime": "${TOMORROW}T22:00:00Z", "endTime": "${TOMORROW}T23:00:00Z", "price": 16.8},
      {"startTime": "${TOMORROW}T23:00:00Z", "endTime": "${TOMORROW}T24:00:00Z", "price": 12.5}
    ],
    "cached_at": "$NOW"
  },
  "dePrices": {
    "prices": [
      {"startTime": "${TOMORROW}T00:00:00Z", "endTime": "${TOMORROW}T01:00:00Z", "price": 12.5},
      {"startTime": "${TOMORROW}T01:00:00Z", "endTime": "${TOMORROW}T02:00:00Z", "price": 9.8},
      {"startTime": "${TOMORROW}T02:00:00Z", "endTime": "${TOMORROW}T03:00:00Z", "price": 7.2},
      {"startTime": "${TOMORROW}T03:00:00Z", "endTime": "${TOMORROW}T04:00:00Z", "price": 14.1},
      {"startTime": "${TOMORROW}T04:00:00Z", "endTime": "${TOMORROW}T05:00:00Z", "price": 17.3},
      {"startTime": "${TOMORROW}T05:00:00Z", "endTime": "${TOMORROW}T06:00:00Z", "price": 19.9},
      {"startTime": "${TOMORROW}T06:00:00Z", "endTime": "${TOMORROW}T07:00:00Z", "price": 24.2},
      {"startTime": "${TOMORROW}T07:00:00Z", "endTime": "${TOMORROW}T08:00:00Z", "price": 27.8},
      {"startTime": "${TOMORROW}T08:00:00Z", "endTime": "${TOMORROW}T09:00:00Z", "price": 31.2},
      {"startTime": "${TOMORROW}T09:00:00Z", "endTime": "${TOMORROW}T10:00:00Z", "price": 33.5},
      {"startTime": "${TOMORROW}T10:00:00Z", "endTime": "${TOMORROW}T11:00:00Z", "price": 31.8},
      {"startTime": "${TOMORROW}T11:00:00Z", "endTime": "${TOMORROW}T12:00:00Z", "price": 29.2},
      {"startTime": "${TOMORROW}T12:00:00Z", "endTime": "${TOMORROW}T13:00:00Z", "price": 26.7},
      {"startTime": "${TOMORROW}T13:00:00Z", "endTime": "${TOMORROW}T14:00:00Z", "price": 24.9},
      {"startTime": "${TOMORROW}T14:00:00Z", "endTime": "${TOMORROW}T15:00:00Z", "price": 22.3},
      {"startTime": "${TOMORROW}T15:00:00Z", "endTime": "${TOMORROW}T16:00:00Z", "price": 20.5},
      {"startTime": "${TOMORROW}T16:00:00Z", "endTime": "${TOMORROW}T17:00:00Z", "price": 23.1},
      {"startTime": "${TOMORROW}T17:00:00Z", "endTime": "${TOMORROW}T18:00:00Z", "price": 28.2},
      {"startTime": "${TOMORROW}T18:00:00Z", "endTime": "${TOMORROW}T19:00:00Z", "price": 35.6},
      {"startTime": "${TOMORROW}T19:00:00Z", "endTime": "${TOMORROW}T20:00:00Z", "price": 38.9},
      {"startTime": "${TOMORROW}T20:00:00Z", "endTime": "${TOMORROW}T21:00:00Z", "price": 31.2},
      {"startTime": "${TOMORROW}T21:00:00Z", "endTime": "${TOMORROW}T22:00:00Z", "price": 24.8},
      {"startTime": "${TOMORROW}T22:00:00Z", "endTime": "${TOMORROW}T23:00:00Z", "price": 18.5},
      {"startTime": "${TOMORROW}T23:00:00Z", "endTime": "${TOMORROW}T24:00:00Z", "price": 14.2}
    ],
    "cached_at": "$NOW"
  },
  "timestamp": "$NOW"
}
EOF

echo "✅ Test prices created (24h for tomorrow)"

# Trigger function
echo ""
echo "🚀 Triggering Firebase Function..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d @/tmp/test-prices.json)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo ""
echo "📊 Response:"
echo "HTTP Status: $HTTP_CODE"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"

# Check result
if [ "$HTTP_CODE" = "200" ]; then
    echo ""
    echo "✅ SUCCESS! Function executed successfully"

    # Parse results
    PUSHES=$(echo "$BODY" | jq -r '.price_update_pushes // 0' 2>/dev/null || echo "0")
    SCHEDULED=$(echo "$BODY" | jq -r '.notifications_scheduled // 0' 2>/dev/null || echo "0")

    echo ""
    echo "Results:"
    echo "  - Silent pushes sent: $PUSHES"
    echo "  - Notifications scheduled: $SCHEDULED"

    if [ "$PUSHES" -gt 0 ] && [ "$SCHEDULED" -gt 0 ]; then
        echo ""
        echo "✅ All checks passed!"
        echo ""
        echo "Next steps:"
        echo "1. Check Firebase Console → Firestore → scheduled_notifications"
        echo "2. Wait 5-10 minutes for cron to send notifications"
        echo "3. Check your device for notifications"
    else
        echo ""
        echo "⚠️  Warning: Some notifications may not have been scheduled"
        echo "Check if you have test users in notification_preferences collection"
    fi
else
    echo ""
    echo "❌ FAILED! HTTP $HTTP_CODE"
    echo "Check Firebase logs: firebase functions:log --only handlePriceUpdate"
fi

# Cleanup
rm /tmp/test-prices.json

echo ""
echo "🔍 View logs:"
echo "  firebase functions:log --only handlePriceUpdate --limit 50"
echo ""
echo "🗄️  Check Firestore:"
echo "  https://console.firebase.google.com/project/${PROJECT_ID}/firestore"
