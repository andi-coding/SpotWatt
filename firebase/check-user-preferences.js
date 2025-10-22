// Quick script to check user notification preferences in Firestore
const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./spotwatt-900e9-firebase-adminsdk.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkPreferences() {
  console.log('📋 Fetching notification preferences...\n');

  const snapshot = await db.collection('notification_preferences').get();

  if (snapshot.empty) {
    console.log('❌ No users found');
    return;
  }

  snapshot.forEach(doc => {
    const data = doc.data();
    console.log(`User: ${doc.id.substring(0, 20)}...`);
    console.log(`  daily_summary_enabled: ${data.daily_summary_enabled}`);
    console.log(`  cheapest_time_enabled: ${data.cheapest_time_enabled}`);
    console.log(`  price_threshold_enabled: ${data.price_threshold_enabled}`);
    console.log(`  notification_threshold: ${data.notification_threshold} ct/kWh`);
    console.log(`  has_any_notification_enabled: ${data.has_any_notification_enabled}`);
    console.log(`  market: ${data.market}`);
    console.log(`  full_cost_mode: ${data.full_cost_mode || false}`);
    console.log('');
  });

  process.exit(0);
}

checkPreferences().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
