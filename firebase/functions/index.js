const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { CloudTasksClient } = require('@google-cloud/tasks');

admin.initializeApp();

// Cloud Tasks Configuration
const tasksClient = new CloudTasksClient();
const PROJECT_ID = 'spotwatt-900e9';
const LOCATION = 'europe-west3';
const QUEUE_NAME = 'notification-queue';

// ========================================================================
// IN-MEMORY CACHE: Price Cache (survives between warm function invocations)
// This dramatically reduces Firestore reads when multiple users change settings
// Cache is invalidated only when new prices are written via cachePrices()
// ========================================================================
const inMemoryPriceCache = {}; // Format: { market: { data: {...} } }

// ========================================================================
// MAIN: Handle Price Update from Cloudflare Worker
// This function does EVERYTHING:
// 1. Send silent push to all devices (wake up for price update)
// 2. Schedule personalized notifications for next 24h
// ========================================================================
exports.handlePriceUpdate = functions
  .region('europe-west3')
  .runWith({
    timeoutSeconds: 540,
    memory: '2GB'
  })
  .https.onRequest(async (req, res) => {
    console.log('📬 handlePriceUpdate triggered by Cloudflare Worker');

    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'POST');
      res.set('Access-Control-Allow-Headers', 'Content-Type, X-Api-Key');
      return res.status(204).send('');
    }

    // Security check
    const apiKey = req.headers['x-api-key'];
    const expectedApiKey = process.env.API_KEY;

    if (expectedApiKey && apiKey !== expectedApiKey) {
      console.error('❌ Invalid API key');
      return res.status(403).json({ error: 'Unauthorized' });
    }

    try {
      const { atPrices, dePrices, timestamp } = req.body;

      if (!atPrices || !dePrices) {
        return res.status(400).json({ error: 'Missing price data' });
      }

      console.log(`Received prices: AT=${atPrices.prices?.length || 0}, DE=${dePrices.prices?.length || 0}`);

      // STEP 0: Cache prices in Firestore (for settings_changed events)
      await cachePrices(atPrices, dePrices);

      // STEP 1: Send silent "price update" push to ALL devices
      const priceUpdateResult = await sendPriceUpdatePushToAll();

      // STEP 2: Schedule personalized notifications for next 24h
      const schedulingResult = await schedulePersonalizedNotifications(atPrices, dePrices);

      return res.json({
        success: true,
        price_update_pushes: priceUpdateResult.sent,
        notifications_scheduled: schedulingResult.count,
        timestamp: timestamp
      });

    } catch (error) {
      console.error('❌ Error in handlePriceUpdate:', error);
      return res.status(500).json({ error: error.message });
    }
  });

// ========================================================================
// STEP 0: Cache prices in Firestore for later use
// ========================================================================
async function cachePrices(atPrices, dePrices) {
  console.log('[Price Cache] Updating price cache...');

  try {
    const batch = admin.firestore().batch();
    
    // ✅ Invalidate in-memory cache so functions fetch fresh data immediately
    console.log('[Price Cache] Invalidating in-memory cache...');
    delete inMemoryPriceCache['AT'];
    delete inMemoryPriceCache['DE'];

    // Cache AT prices
    const atRef = admin.firestore().collection('price_cache').doc('AT');
    batch.set(atRef, {
      prices: atPrices.prices || [],
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    // Cache DE prices
    const deRef = admin.firestore().collection('price_cache').doc('DE');
    batch.set(deRef, {
      prices: dePrices.prices || [],
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    await batch.commit();
    console.log('[Price Cache] ✅ Prices cached successfully and in-memory cache invalidated');
  } catch (error) {
    console.error('[Price Cache] ❌ Error:', error);
    // Don't throw - caching is optional
  }
}

// ========================================================================
// STEP 1: Send "Price Update" Push to ALL Devices
// ========================================================================
async function sendPriceUpdatePushToAll() {
  console.log('[Price Update Push] Starting...');

  try {
    // Get all FCM tokens from Firestore
    const tokensSnapshot = await admin.firestore()
      .collection('fcm_tokens')
      .where('active', '==', true)
      .get();

    if (tokensSnapshot.empty) {
      console.log('[Price Update Push] No tokens found');
      return { sent: 0 };
    }

    console.log(`[Price Update Push] Sending to ${tokensSnapshot.size} devices...`);

    // Build messages and track token references for updating
    const tokenRefs = [];
    const messages = tokensSnapshot.docs.map(doc => {
      const data = doc.data();
      tokenRefs.push(doc.ref); // Store ref for updating last_seen later

      return {
        token: data.token,
        data: {
          action: 'update_prices' // Silent push signal
        },
        android: {
          priority: 'high' // Bypass Doze Mode
        },
        apns: {
          headers: {
            'apns-priority': '5',
            'apns-push-type': 'background'
          },
          payload: {
            aps: {
              'content-available': 1 // Wake app
            }
          }
        }
      };
    });

    // Send in batches of 500 (FCM limit)
    let successCount = 0;
    let failCount = 0;
    const invalidTokens = [];
    const successfulTokens = [];

    for (let i = 0; i < messages.length; i += 500) {
      const batch = messages.slice(i, i + 500);
      const batchRefs = tokenRefs.slice(i, i + 500);

      try {
        const response = await admin.messaging().sendEach(batch);
        successCount += response.successCount;
        failCount += response.failureCount;

        // Track successful and invalid tokens
        response.responses.forEach((resp, idx) => {
          if (resp.success) {
            successfulTokens.push(batchRefs[idx]);
          } else {
            const error = resp.error;
            if (error.code === 'messaging/invalid-registration-token' ||
                error.code === 'messaging/registration-token-not-registered') {
              invalidTokens.push(batch[idx].token);
            }
          }
        });

      } catch (error) {
        console.error('[Price Update Push] Batch error:', error);
        failCount += batch.length;
      }
    }

    // Update last_seen for successful tokens (optional, for analytics)
    if (successfulTokens.length > 0) {
      const updateBatch = admin.firestore().batch();

      successfulTokens.forEach(ref => {
        updateBatch.update(ref, {
          last_seen: admin.firestore.FieldValue.serverTimestamp()
        });
      });

      await updateBatch.commit();
    }

    // Cleanup invalid tokens (mark inactive + TTL for auto-deletion after 7 days)
    if (invalidTokens.length > 0) {
      console.log(`[Price Update Push] Cleaning up ${invalidTokens.length} invalid tokens...`);
      const cleanupBatch = admin.firestore().batch();
      const ttlExpireAt = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // Delete in 7 days
      );

      for (const token of invalidTokens) {
        const tokenRef = admin.firestore().collection('fcm_tokens').doc(token);
        cleanupBatch.update(tokenRef, {
          active: false,
          invalidated_at: admin.firestore.FieldValue.serverTimestamp(),
          ttl_expire_at: ttlExpireAt
        });
      }

      await cleanupBatch.commit();
    }

    console.log(`[Price Update Push] ✅ Sent: ${successCount}, Failed: ${failCount}`);
    return { sent: successCount, failed: failCount };

  } catch (error) {
    console.error('[Price Update Push] ❌ Error:', error);
    return { sent: 0, failed: 0 };
  }
}

// ========================================================================
// STEP 2: Schedule Personalized Notifications
// ========================================================================
/**
 * Schedule personalized notifications for ALL users (called daily on price update)
 * Uses Cloud Tasks to send notifications at exact times
 */
async function schedulePersonalizedNotifications(atPrices, dePrices) {
  console.log('[Scheduling] Starting personalized notifications with Cloud Tasks...');

  try {
    // Get users with notification preferences
    const usersSnapshot = await admin.firestore()
      .collection('notification_preferences')
      .where('has_any_notification_enabled', '==', true)
      .get();

    console.log(`[Scheduling] Found ${usersSnapshot.size} users with active notifications`);

    if (usersSnapshot.empty) {
      return { count: 0 };
    }

    let scheduledCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const user = userDoc.data();
      const fcmToken = user.fcm_token;
      const prices = user.market === 'DE' ? dePrices : atPrices;

      try {
        // Calculate notifications for this user
        const notifications = calculateUserNotifications(user, prices);

        if (notifications.length === 0) {
          continue;
        }

        // Cancel old recurring tasks (NOT window reminders!)
        if (user.recurring_tasks) {
          const oldTaskNames = Object.values(user.recurring_tasks).flat();
          if (oldTaskNames.length > 0) {
            await cancelCloudTasksByName(oldTaskNames);
          }
        }

        // Create new Cloud Tasks
        const createdTasks = await scheduleNotificationsWithCloudTasks(fcmToken, notifications);

        // Build task map (handle multiple tasks per type)
        const taskMap = {};
        createdTasks.forEach(task => {
          if (!taskMap[task.type]) {
            taskMap[task.type] = [];
          }
          taskMap[task.type].push(task.name);
        });

        // Update recurring_tasks field (window reminders stay intact)
        await admin.firestore()
          .collection('notification_preferences')
          .doc(fcmToken)
          .update({
            recurring_tasks: taskMap
          });

        scheduledCount += createdTasks.length;

      } catch (userError) {
        const tokenPreview = fcmToken.substring(0, 20) + '...';
        console.error(`[Scheduling] ❌ Failed for user ${tokenPreview}:`, userError);
        // Continue with next user
      }
    }

    console.log(`[Scheduling] ✅ Scheduled ${scheduledCount} notifications for ${usersSnapshot.size} users`);
    return { count: scheduledCount };

  } catch (error) {
    console.error('[Scheduling] ❌ Error:', error);
    return { count: 0 };
  }
}

// ========================================================================
// DELETED OLD FUNCTIONS (replaced by Cloud Tasks)
// ========================================================================
// - sendScheduledNotifications: Polling-based system (replaced by Cloud Tasks)
// - getNotificationTTL: TTL for Firestore docs (Cloud Tasks auto-delete after execution)
// ========================================================================

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

function calculateUserNotifications(user, priceData) {
  const notifications = [];
  const now = new Date();
  const prices = priceData.prices || [];

  if (prices.length === 0) {
    return notifications;
  }

  // Get user timezone offset (in minutes, e.g. +60 for UTC+1)
  const userTimezoneOffset = user.timezone ?? 60; // Default: UTC+1 (Austria/Germany)

  // Convert UTC date to user's local time
  const toUserLocalTime = (utcDate) => {
    const date = new Date(utcDate);
    // Add user's timezone offset
    date.setMinutes(date.getMinutes() + userTimezoneOffset);
    return date;
  };

  // Convert user's local time to UTC for Firestore
  const toUTC = (localDate) => {
    const date = new Date(localDate);
    // Subtract user's timezone offset
    date.setMinutes(date.getMinutes() - userTimezoneOffset);
    return date;
  };

  // 1. Daily Summary (matching app logic with hour count + high price warning)
  if (user.daily_summary_enabled) {
    const [hour, minute] = (user.daily_summary_time ?? '07:00').split(':');

    // Create time in user's local timezone
    let localSendAt = toUserLocalTime(now);
    localSendAt.setHours(parseInt(hour), parseInt(minute), 0, 0);

    // If time has passed today, schedule for tomorrow
    if (localSendAt <= toUserLocalTime(now)) {
      localSendAt.setDate(localSendAt.getDate() + 1);
    }

    // Convert back to UTC for Cloud Tasks (exact time, no rounding needed!)
    const sendAt = toUTC(localSendAt);

    if (sendAt > now && !isInQuietTime(sendAt, user, userTimezoneOffset)) {
      const summaryBody = generateDailySummaryWithHours(prices, user, sendAt, userTimezoneOffset);

      if (summaryBody) {
        notifications.push({
          type: 'daily_summary',
          sendAt: sendAt, // UTC time for Firestore
          title: '📊 Tägliche Übersicht',
          body: summaryBody
        });
      }
    }
  }

  // 2. Cheapest Time (1 per day, matching app logic)
  if (user.cheapest_time_enabled) {
    const cheapestHoursPerDay = findCheapestHourPerDay(prices, user);

    for (const hour of cheapestHoursPerDay) {
      const sendAt = new Date(hour.startTime);
      const minutesBefore = user.notification_minutes_before ?? 15;
      sendAt.setMinutes(sendAt.getMinutes() - minutesBefore);

      if (sendAt > now && !isInQuietTime(sendAt, user, userTimezoneOffset)) {
        const fullCost = calculateFullCost(hour.price, user);
        const priceText = user.full_cost_mode
          ? `${fullCost.toFixed(2)} ct/kWh`
          : `${hour.price.toFixed(2)} ct/kWh`;

        const startTime = formatTime(hour.startTime, userTimezoneOffset);

        notifications.push({
          type: 'cheapest_hour',
          sendAt: sendAt,
          title: '⚡ Günstigster Zeitpunkt!',
          body: `Um ${startTime} Uhr beginnt der günstigste Zeitpunkt des Tages (${priceText})`
        });
      }
    }
  }

  // 3. Price Threshold (fixed 5min before, matching app logic)
  if (user.price_threshold_enabled) {
    const threshold = user.notification_threshold ?? 10.0; // Use ?? instead of || to allow 0

    const belowThreshold = prices.filter(p => {
      const effectivePrice = calculateFullCost(p.price, user);
      const priceTime = new Date(p.startTime);
      return effectivePrice <= threshold && priceTime > now;
    });

    for (const period of belowThreshold) {
      const sendAt = new Date(period.startTime);
      sendAt.setMinutes(sendAt.getMinutes() - 5); // Fixed 5min before (urgent!)

      if (sendAt > now && !isInQuietTime(sendAt, user, userTimezoneOffset)) {
        const effectivePrice = calculateFullCost(period.price, user);
        const priceText = user.full_cost_mode
          ? `${effectivePrice.toFixed(2)} ct/kWh`
          : `${period.price.toFixed(2)} ct/kWh`;

        notifications.push({
          type: 'threshold_alert',
          sendAt: sendAt,
          title: '💡 Günstiger Strompreis!',
          body: `Ab ${formatTime(period.startTime, userTimezoneOffset)} nur ${priceText} - Perfekt für energieintensive Geräte!`
        });
      }
    }
  }

  return notifications;
}

function calculateFullCost(spotPrice, user) {
  if (!user.full_cost_mode) return spotPrice;

  const taxRate = user.tax_rate ?? 20.0;
  const taxMultiplier = 1.0 + (taxRate / 100);

  // Strategy: Convert SPOT to BRUTTO, then add BRUTTO fees
  // SPOT price is NETTO (exkl. USt) from EPEX
  // Provider fees are BRUTTO (inkl. USt) from DB
  // Network costs are BRUTTO (inkl. USt) by default (standard)

  // 1. Apply tax to SPOT first (NETTO → BRUTTO)
  const spotBrutto = spotPrice * taxMultiplier;

  // 2. Provider fee is already BRUTTO
  const percentage = user.energy_provider_percentage ?? 0;
  const fixedFee = user.energy_provider_fixed_fee ?? 0;
  const providerFeeBrutto = Math.abs(spotPrice) * (percentage / 100) + fixedFee;

  // 3. Network costs are BRUTTO by default (include_tax=true)
  //    If user entered NETTO (include_tax=false), apply tax
  const networkCosts = user.network_costs ?? 0;
  const networkCostsBrutto = user.include_tax ? networkCosts : networkCosts * taxMultiplier;

  // 4. Sum all BRUTTO values
  const total = spotBrutto + providerFeeBrutto + networkCostsBrutto;

  return total;
}

function generateDailySummaryWithHours(prices, user, notificationTime, userTimezoneOffset) {
  if (prices.length === 0) return null;

  // Convert UTC notification time to user's local time for day comparison
  const localNotificationTime = new Date(notificationTime);
  localNotificationTime.setMinutes(localNotificationTime.getMinutes() + (userTimezoneOffset ?? 60));

  // Filter: Only FUTURE hours of target day (after notification time) in user's timezone
  const futurePrices = prices.filter(p => {
    const utcPriceDate = new Date(p.startTime);
    const localPriceDate = new Date(utcPriceDate);
    localPriceDate.setMinutes(localPriceDate.getMinutes() + (userTimezoneOffset ?? 60));

    return localPriceDate.getDate() === localNotificationTime.getDate() &&
           localPriceDate.getMonth() === localNotificationTime.getMonth() &&
           localPriceDate.getFullYear() === localNotificationTime.getFullYear() &&
           utcPriceDate > notificationTime;
  });

  if (futurePrices.length === 0) return null;

  // Get hour count from user preferences
  const hoursCount = user.daily_summary_hours ?? 3;

  // Find cheapest hours (with full cost if enabled)
  const pricesWithCost = futurePrices.map(p => ({
    ...p,
    effectivePrice: calculateFullCost(p.price, user)
  }));

  const cheapestHours = pricesWithCost
    .sort((a, b) => a.effectivePrice - b.effectivePrice)
    .slice(0, hoursCount)
    .sort((a, b) => new Date(a.startTime) - new Date(b.startTime)); // Sort by time for display

  let message = '';

  // High price warning (if enabled)
  const highPriceThreshold = user.high_price_threshold ?? 50.0;
  const highPrices = pricesWithCost.filter(p => p.effectivePrice > highPriceThreshold);

  if (highPrices.length > 0) {
    message += '⚠️ WARNUNG: Heute sehr hohe Preise!\n\n';
    highPrices.sort((a, b) => new Date(a.startTime) - new Date(b.startTime));

    for (const price of highPrices) {
      const start = new Date(price.startTime);
      const end = new Date(price.endTime);
      const priceText = user.full_cost_mode
        ? `${price.effectivePrice.toFixed(2)} ct/kWh`
        : `${price.price.toFixed(2)} ct/kWh`;

      message += `• ${formatTime(price.startTime, userTimezoneOffset)}-${formatTime(price.endTime, userTimezoneOffset)}: ${priceText}\n`;
    }
    message += '\n';
  }

  // Cheapest hours section
  message += `💡 Die ${hoursCount} günstigsten Stunden heute:\n\n`;

  for (const hour of cheapestHours) {
    const priceText = user.full_cost_mode
      ? `${hour.effectivePrice.toFixed(2)} ct/kWh`
      : `${hour.price.toFixed(2)} ct/kWh`;

    message += `• ${formatTime(hour.startTime, userTimezoneOffset)}-${formatTime(hour.endTime, userTimezoneOffset)}: ${priceText}\n`;
  }

  return message.trim();
}

function findCheapestHourPerDay(prices, user) {
  const cheapestPerDay = [];

  console.log(`[findCheapestHourPerDay] Processing ${prices.length} prices`);

  // Get user timezone offset
  const userTimezoneOffset = user.timezone ?? 60; // Default: UTC+1

  // Group prices by day (in user's LOCAL timezone!)
  const pricesByDay = {};
  for (const price of prices) {
    // Convert UTC to user's local time for grouping
    const utcDate = new Date(price.startTime);
    const localDate = new Date(utcDate);
    localDate.setMinutes(localDate.getMinutes() + userTimezoneOffset);

    const dayKey = `${localDate.getFullYear()}-${localDate.getMonth() + 1}-${localDate.getDate()}`;

    if (!pricesByDay[dayKey]) {
      pricesByDay[dayKey] = [];
    }
    pricesByDay[dayKey].push(price);
  }

  console.log(`[findCheapestHourPerDay] Grouped into ${Object.keys(pricesByDay).length} days:`,
    Object.entries(pricesByDay).map(([day, prices]) => `${day}=${prices.length}h`).join(', '));

  // Find cheapest hour per day (accept incomplete days - future filtering happens in caller)
  for (const [dayKey, dayPrices] of Object.entries(pricesByDay)) {
    console.log(`[findCheapestHourPerDay] Day ${dayKey}: ${dayPrices.length} hours`);
    if (dayPrices.length > 0) {
      // Calculate effective price (with full cost if enabled)
      const pricesWithCost = dayPrices.map(p => ({
        ...p,
        effectivePrice: calculateFullCost(p.price, user)
      }));

      // Find cheapest of the day
      const cheapest = pricesWithCost.reduce((a, b) =>
        a.effectivePrice < b.effectivePrice ? a : b
      );

      cheapestPerDay.push(cheapest);
    }
  }

  return cheapestPerDay;
}

function isInQuietTime(utcDate, user, userTimezoneOffset) {
  if (!user.quiet_time_enabled) return false;

  // Convert UTC to user's local time for quiet time check
  const localDate = new Date(utcDate);
  localDate.setMinutes(localDate.getMinutes() + (userTimezoneOffset ?? 60));

  const minutes = localDate.getHours() * 60 + localDate.getMinutes();
  const startMinutes = (user.quiet_time_start_hour ?? 22) * 60 + (user.quiet_time_start_minute ?? 0);
  const endMinutes = (user.quiet_time_end_hour ?? 6) * 60 + (user.quiet_time_end_minute ?? 0);

  if (startMinutes <= endMinutes) {
    return minutes >= startMinutes && minutes < endMinutes;
  } else {
    return minutes >= startMinutes || minutes < endMinutes;
  }
}

function formatTime(dateString, userTimezoneOffset = 60) {
  const date = new Date(dateString);
  // Convert UTC to user's local time
  const localDate = new Date(date);
  localDate.setMinutes(localDate.getMinutes() + userTimezoneOffset);
  return `${localDate.getUTCHours().toString().padStart(2, '0')}:${localDate.getUTCMinutes().toString().padStart(2, '0')}`;
}

function getChannelId(type) {
  switch (type) {
    case 'daily_summary':
      return 'daily_summary';
    case 'cheapest_hour':
      return 'cheapest_time';
    case 'threshold_alert':
      return 'price_alerts';
    default:
      return 'default';
  }
}

// ========================================================================
// DELETED: Event Queue System (replaced by onPreferencesUpdate trigger)
// The following functions have been removed:
// - processNotificationEvents: Replaced by onPreferencesUpdate (direct Firestore trigger)
// - handleSettingsChanged: Logic moved into onPreferencesUpdate
// - cancelUserNotifications: Replaced by cancelCloudTasksByName (Cloud Tasks)
//
// Benefits of new system:
// - 0 extra writes (no notification_events collection needed)
// - 0 extra reads (change.before/after provides data)
// - Instant triggering (no event queue delay)
// ========================================================================

/**
 * Get latest prices from Firestore cache WITH in-memory caching
 * This function uses a 2-tier cache system:
 * 1. In-Memory Cache (instant, survives between warm function calls)
 * 2. Firestore Cache (fast, persistent)
 */
async function getLatestPrices(market) {
  // TIER 1: Check in-memory cache (no TTL - only invalidated by cachePrices())
  const cachedEntry = inMemoryPriceCache[market];
  if (cachedEntry) {
    console.log(`[Price Cache] ✅ HIT (in-memory) for market ${market}`);
    return cachedEntry.data;
  }

  // TIER 2: Cache miss - fetch from Firestore
  console.log(`[Price Cache] ⚠️ MISS (in-memory) for market ${market} - fetching from Firestore...`);

  try {
    const pricesDoc = await admin.firestore()
      .collection('price_cache')
      .doc(market)
      .get();

    if (!pricesDoc.exists) {
      console.warn(`[Price Cache] ❌ No cached prices found in Firestore for market ${market}`);
      return null;
    }

    const pricesData = pricesDoc.data();

    // Store in in-memory cache (persists until invalidated or cold start)
    inMemoryPriceCache[market] = {
      data: pricesData
    };

    console.log(`[Price Cache] ✅ Loaded from Firestore and cached in memory for ${market}`);

    return pricesData;

  } catch (error) {
    console.error(`[Price Cache] ❌ Error fetching prices for ${market}:`, error);
    return null;
  }
}

// Schedule notifications for a user
// ========================================================================
// DELETED: scheduleNotifications (Firestore-based)
// Replaced by: scheduleNotificationsWithCloudTasks (see below)
// ========================================================================

// ========================================================================
// CLOUD TASKS: New notification scheduling system
// ========================================================================

/**
 * HTTP Function: Execute Notification Task
 * Called by Cloud Tasks at the exact scheduled time
 */
exports.executeNotificationTask = functions
  .region(LOCATION)
  .runWith({
    memory: '256MB',
    timeoutSeconds: 60
  })
  .https.onRequest(async (req, res) => {
    // Security: Only allow POST requests
    if (req.method !== 'POST') {
      console.warn('[Execute Task] Method not allowed:', req.method);
      return res.status(405).send('Method Not Allowed');
    }

    try {
      const payload = req.body;
      const tokenPreview = payload.fcm_token ? payload.fcm_token.substring(0, 20) + '...' : 'unknown';
      console.log(`[Execute Task] Processing notification for token: ${tokenPreview}`);

      if (!payload.fcm_token || !payload.title || !payload.body) {
        console.error('[Execute Task] Missing required fields');
        return res.status(400).send('Bad Request');
      }

      // Send FCM notification
      await admin.messaging().send({
        token: payload.fcm_token,
        notification: {
          title: payload.title,
          body: payload.body
        },
        data: {
          type: String(payload.type || 'general'),
          tab_index: '0'
        },
        android: {
          priority: 'high',
          notification: {
            channelId: getChannelId(payload.type),
            priority: 'high'
          }
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-expiration': String(Math.floor(Date.now() / 1000) + 3600)
          },
          payload: {
            aps: {
              alert: {
                title: payload.title,
                body: payload.body
              },
              sound: 'default'
            }
          }
        }
      });

      console.log(`[Execute Task] ✅ Notification sent successfully`);
      return res.status(200).send('OK');

    } catch (error) {
      console.error('[Execute Task] ❌ Error:', error);
      return res.status(500).send('Internal Server Error');
    }
  });

/**
 * HTTP Function: Process Notification Preferences (Debounced)
 * Called by Cloud Tasks after 10s delay to handle burst updates
 * Reads fresh state from Firestore and schedules notifications
 */
exports.processNotificationPreferences = functions
  .region(LOCATION)
  .runWith({
    timeoutSeconds: 120,
    memory: '512MB'
  })
  .https.onRequest(async (req, res) => {
    try {
      const { fcmToken, updateTimestamp } = req.body;

      if (!fcmToken) {
        return res.status(400).send('Missing fcmToken');
      }

      const tokenPreview = fcmToken.substring(0, 20) + '...';
      console.log(`[Process Prefs] Processing for token: ${tokenPreview} (ts: ${updateTimestamp})`);

      // Read CURRENT state from Firestore (10s after last change!)
      const doc = await admin.firestore()
        .collection('notification_preferences')
        .doc(fcmToken)
        .get();

      if (!doc.exists) {
        console.log(`[Process Prefs] Preferences deleted for ${tokenPreview}`);
        return res.status(200).send('OK - preferences deleted');
      }

      const prefs = doc.data();

      // Check if this task is outdated (a newer update happened after this task was created)
      const currentTimestamp = prefs.updated_at?.toMillis() || 0;
      if (currentTimestamp > updateTimestamp) {
        console.log(`[Process Prefs] ⏭️ Skipping outdated task (current: ${currentTimestamp}, task: ${updateTimestamp})`);
        return res.status(200).send('OK - skipped (outdated)');
      }

      console.log(`[Process Prefs] ✅ Task is current, processing...`);

      // STEP 1: Cancel ALL old recurring tasks
      if (prefs.recurring_tasks) {
        const oldTaskNames = Object.values(prefs.recurring_tasks).flat();
        if (oldTaskNames.length > 0) {
          console.log(`[Process Prefs] Cancelling ${oldTaskNames.length} old recurring tasks...`);
          await cancelCloudTasksByName(oldTaskNames);
        }
      }

      // STEP 2: Check if all notifications are disabled
      if (!prefs.has_any_notification_enabled) {
        console.log(`[Process Prefs] All notifications disabled for ${tokenPreview}`);

        // Clear recurring_tasks field
        await admin.firestore()
          .collection('notification_preferences')
          .doc(fcmToken)
          .update({
            recurring_tasks: admin.firestore.FieldValue.delete()
          });

        return res.status(200).send('OK - all disabled');
      }

      // STEP 3: Get latest prices
      const prices = await getLatestPrices(prefs.market);

      if (!prices || !prices.prices || prices.prices.length === 0) {
        console.log(`[Process Prefs] No prices available for market ${prefs.market}`);
        return res.status(200).send('OK - no prices');
      }

      // STEP 4: Calculate new notifications
      const notifications = calculateUserNotifications(prefs, prices);

      if (notifications.length === 0) {
        console.log(`[Process Prefs] No notifications to schedule for ${tokenPreview}`);
        return res.status(200).send('OK - no notifications');
      }

      // STEP 5: Create Cloud Tasks
      console.log(`[Process Prefs] Creating ${notifications.length} Cloud Tasks...`);
      const createdTasks = await scheduleNotificationsWithCloudTasks(fcmToken, notifications);

      // STEP 6: Save task names (using arrays for multiple tasks per type)
      const taskMap = {};
      createdTasks.forEach(task => {
        if (!taskMap[task.type]) {
          taskMap[task.type] = [];
        }
        taskMap[task.type].push(task.name);
      });

      await admin.firestore()
        .collection('notification_preferences')
        .doc(fcmToken)
        .update({
          recurring_tasks: taskMap
        });

      console.log(`[Process Prefs] ✅ Rescheduled ${notifications.length} recurring notifications for ${tokenPreview}`);

      return res.status(200).send('OK');
    } catch (error) {
      console.error('[Process Prefs] Error:', error);
      return res.status(500).send('Internal Server Error');
    }
  });

/**
 * Firestore Trigger: On Preferences Update (Debounce Trigger)
 * Triggered when user preferences change
 * Creates/updates a debounce task with 10s delay (idempotent by fcmToken)
 */
exports.onPreferencesUpdate = functions
  .region(LOCATION)
  .runWith({
    timeoutSeconds: 30,
    memory: '256MB'
  })
  .firestore.document('notification_preferences/{fcmToken}')
  .onWrite(async (change, context) => {
    const fcmToken = context.params.fcmToken;
    const oldPreferences = change.before.data();
    const newPreferences = change.after.data();

    const tokenPreview = fcmToken.substring(0, 20) + '...';

    // CRITICAL: Prevent infinite loop!
    // If ONLY recurring_tasks changed, this is our own update
    // Skip processing to avoid trigger loop
    if (oldPreferences && newPreferences) {
      const oldWithoutTasks = { ...oldPreferences };
      const newWithoutTasks = { ...newPreferences };
      delete oldWithoutTasks.recurring_tasks;
      delete newWithoutTasks.recurring_tasks;

      if (JSON.stringify(oldWithoutTasks) === JSON.stringify(newWithoutTasks)) {
        console.log(`[Prefs Update] Skipping - only recurring_tasks changed (avoiding loop)`);
        return;
      }
    }

    console.log(`[Prefs Update] Scheduling debounced processing for ${tokenPreview} (+10s)`);

    // Create debounce task with unique timestamp (multi-task approach)
    // Each update creates a new task, but only the latest will actually process
    const parent = tasksClient.queuePath(PROJECT_ID, LOCATION, QUEUE_NAME);

    // Generate safe task ID (fcmToken contains : which is not allowed)
    const safeTokenId = Buffer.from(fcmToken)
      .toString('base64')
      .replace(/\+/g, '-')   // Replace + with -
      .replace(/\//g, '_')   // Replace / with _
      .replace(/=/g, '')     // Remove padding =
      .substring(0, 40);     // Max 40 chars (leave room for timestamp)

    // Add timestamp to make each task unique (avoids Cloud Tasks tombstone conflicts)
    const updateTimestamp = Date.now();
    const taskName = tasksClient.taskPath(
      PROJECT_ID,
      LOCATION,
      QUEUE_NAME,
      `debounce-${safeTokenId}-${updateTimestamp}`
    );

    const targetUrl = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/processNotificationPreferences`;
    const taskPayload = {
      fcmToken,
      updateTimestamp  // Task will check if it's the latest before processing
    };

    // Create task (no deletion needed - timestamp check handles deduplication)
    try {
      await tasksClient.createTask({
        parent,
        task: {
          name: taskName,
          scheduleTime: {
            seconds: Math.floor(Date.now() / 1000) + 10  // 10 seconds delay
          },
          httpRequest: {
            httpMethod: 'POST',
            url: targetUrl,
            body: Buffer.from(JSON.stringify(taskPayload)).toString('base64'),
            headers: {
              'Content-Type': 'application/json'
            }
          }
        }
      });

      console.log(`[Prefs Update] ✅ Debounce task scheduled for ${tokenPreview} (+10s, ts: ${updateTimestamp})`);
    } catch (error) {
      console.error(`[Prefs Update] ❌ Failed to create debounce task:`, error);
    }
  });


// ========================================================================
// FIRESTORE TRIGGER: Window Reminder Created/Updated
// Manages Cloud Tasks for window reminders (Spartipps feature)
// ========================================================================
exports.onWindowReminderUpdate = functions
  .region(LOCATION)
  .runWith({
    timeoutSeconds: 60,
    memory: '256MB'
  })
  .firestore.document('window_reminders/{reminderId}')
  .onWrite(async (change, context) => {
    const reminderId = context.params.reminderId;
    const oldData = change.before.data();
    const newData = change.after.data();

    console.log(`[Window Reminder] Processing ${reminderId}`);

    // CASE 1: Reminder was deleted
    if (!newData) {
      console.log(`[Window Reminder] Deleted - cancelling Cloud Task if exists`);
      if (oldData && oldData.task_name) {
        await cancelCloudTasksByName([oldData.task_name]);
      }
      return;
    }

    // CASE 2: Reminder was cancelled
    if (newData.status === 'cancelled') {
      console.log(`[Window Reminder] Cancelled - deleting Cloud Task`);
      if (newData.task_name) {
        await cancelCloudTasksByName([newData.task_name]);
      }
      return;
    }

    // CASE 3: Reminder was created or rescheduled (status: 'pending')
    if (newData.status === 'pending') {
      console.log(`[Window Reminder] Creating Cloud Task...`);

      // Cancel old task if exists
      if (oldData && oldData.task_name) {
        await cancelCloudTasksByName([oldData.task_name]);
      }

      // Create Cloud Task
      const targetUrl = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/executeNotificationTask`;

      const taskPayload = {
        fcm_token: newData.fcm_token,
        title: newData.title,
        body: newData.body,
        type: 'window_reminder'
      };

      // Sanitize reminderId to only contain valid characters [A-Za-z0-9-_]
      const safeReminderId = reminderId.replace(/[^A-Za-z0-9-_]/g, '_');
      const taskId = `window-${safeReminderId}-${Date.now()}`;
      const taskName = tasksClient.taskPath(PROJECT_ID, LOCATION, QUEUE_NAME, taskId);

      const task = {
        name: taskName,
        httpRequest: {
          httpMethod: 'POST',
          url: targetUrl,
          body: Buffer.from(JSON.stringify(taskPayload)).toString('base64'),
          headers: {
            'Content-Type': 'application/json',
          },
        },
        scheduleTime: {
          seconds: newData.send_at.seconds
        }
      };

      try {
        await tasksClient.createTask({
          parent: tasksClient.queuePath(PROJECT_ID, LOCATION, QUEUE_NAME),
          task
        });

        // Update reminder with task_name and status
        await admin.firestore()
          .collection('window_reminders')
          .doc(reminderId)
          .update({
            task_name: taskName,
            status: 'scheduled'
          });

        console.log(`[Window Reminder] ✅ Cloud Task created: ${taskId}`);
      } catch (error) {
        console.error(`[Window Reminder] ❌ Failed to create task:`, error);

        // Mark as failed
        await admin.firestore()
          .collection('window_reminders')
          .doc(reminderId)
          .update({
            status: 'failed',
            error: error.message
          });
      }
    }

    // CASE 4: Task already scheduled - no action needed
    if (newData.status === 'scheduled') {
      console.log(`[Window Reminder] Already scheduled - no action needed`);
    }
  });

/**
 * Create Cloud Tasks for scheduled notifications
 */
async function scheduleNotificationsWithCloudTasks(fcmToken, notifications) {
  const targetUrl = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/executeNotificationTask`;
  const createdTasks = [];

  for (const notification of notifications) {
    try {
      const taskPayload = {
        fcm_token: fcmToken,
        title: notification.title,
        body: notification.body,
        type: notification.type
      };

      // Create unique task name
      const timestamp = Date.now();
      const random = Math.random().toString(36).substring(7);
      const taskId = `notif-${notification.type}-${fcmToken.substring(0, 16)}-${timestamp}-${random}`;
      const taskName = tasksClient.taskPath(PROJECT_ID, LOCATION, QUEUE_NAME, taskId);

      const task = {
        name: taskName,
        httpRequest: {
          httpMethod: 'POST',
          url: targetUrl,
          body: Buffer.from(JSON.stringify(taskPayload)).toString('base64'),
          headers: {
            'Content-Type': 'application/json'
          }
        },
        scheduleTime: {
          seconds: Math.floor(notification.sendAt.getTime() / 1000)
        }
      };

      await tasksClient.createTask({
        parent: tasksClient.queuePath(PROJECT_ID, LOCATION, QUEUE_NAME),
        task
      });

      createdTasks.push({
        type: notification.type,
        name: taskName
      });

      console.log(`[Cloud Tasks] ✅ Created task: ${notification.type} at ${notification.sendAt.toISOString()}`);

    } catch (error) {
      console.error(`[Cloud Tasks] ❌ Failed to create task for ${notification.type}:`, error);
      // Continue with other tasks even if one fails
    }
  }

  return createdTasks;
}

/**
 * Cancel Cloud Tasks by their names
 */
async function cancelCloudTasksByName(taskNames) {
  const cancelPromises = taskNames.map(async (taskName) => {
    try {
      await tasksClient.deleteTask({ name: taskName });
      const taskId = taskName.split('/').pop();
      console.log(`[Cloud Tasks] ✅ Cancelled task: ${taskId}`);
    } catch (error) {
      if (error.code === 5) { // NOT_FOUND
        const taskId = taskName.split('/').pop();
        console.log(`[Cloud Tasks] ⚠️ Task already executed: ${taskId}`);
      } else {
        console.error(`[Cloud Tasks] ❌ Failed to cancel task:`, error);
      }
    }
  });

  await Promise.all(cancelPromises);
}
