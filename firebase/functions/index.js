const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

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
    console.log('[Price Cache] ✅ Prices cached successfully');
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
async function schedulePersonalizedNotifications(atPrices, dePrices) {
  console.log('[Scheduling] Starting personalized notifications...');

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
    const batches = [];
    let currentBatch = admin.firestore().batch();
    let batchCounter = 0;

    for (const userDoc of usersSnapshot.docs) {
      const user = userDoc.data();
      const prices = user.market === 'DE' ? dePrices : atPrices;

      const notifications = calculateUserNotifications(user, prices);

      for (const notification of notifications) {
        if (batchCounter >= 500) {
          batches.push(currentBatch);
          currentBatch = admin.firestore().batch();
          batchCounter = 0;
        }

        const docRef = admin.firestore()
          .collection('scheduled_notifications')
          .doc();

        const ttlSeconds = getNotificationTTL(notification.type);
        const expireAt = new Date(notification.sendAt.getTime() + ttlSeconds * 1000);

        currentBatch.set(docRef, {
          fcm_token: user.fcm_token,
          user_market: user.market,
          notification: {
            title: notification.title,
            body: notification.body,
            type: notification.type
          },
          send_at: admin.firestore.Timestamp.fromDate(notification.sendAt),
          expireAt: admin.firestore.Timestamp.fromDate(expireAt),
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          sent: false
        });

        batchCounter++;
        scheduledCount++;
      }
    }

    if (batchCounter > 0) {
      batches.push(currentBatch);
    }

    // Commit all batches
    console.log(`[Scheduling] Committing ${batches.length} batches...`);
    await Promise.all(batches.map(b => b.commit()));

    console.log(`[Scheduling] ✅ Scheduled ${scheduledCount} notifications`);
    return { count: scheduledCount };

  } catch (error) {
    console.error('[Scheduling] ❌ Error:', error);
    return { count: 0 };
  }
}

// ========================================================================
// CRON: Send Scheduled Notifications (every 5 minutes)
// ========================================================================
exports.sendScheduledNotifications = functions
  .runWith({
    timeoutSeconds: 280, // 4min 40s (< 5min to prevent overlap!)
    memory: '1GB'
  })
  .pubsub.schedule('every 5 minutes')
  .timeZone('Europe/Vienna')
  .onRun(async (context) => {
    console.log('🔔 sendScheduledNotifications triggered');
    const startTime = Date.now();

    try {
      const now = admin.firestore.Timestamp.now();
      const fiveMinutesFromNow = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 5 * 60 * 1000)
      );

      // Query notifications due in next 5 minutes
      const snapshot = await admin.firestore()
        .collection('scheduled_notifications')
        .where('sent', '==', false)
        .where('send_at', '>=', now)
        .where('send_at', '<', fiveMinutesFromNow)
        .orderBy('send_at', 'asc')
        .limit(2000)
        .get();

      if (snapshot.empty) {
        console.log('No notifications to send');
        return null;
      }

      console.log(`📨 Processing ${snapshot.size} notifications`);

      // Build FCM messages with TTL
      const messages = snapshot.docs.map(doc => {
        const data = doc.data();
        const ttlSeconds = getNotificationTTL(data.notification.type);

        return {
          token: data.fcm_token,
          notification: {
            title: data.notification.title,
            body: data.notification.body
          },
          data: {
            type: String(data.notification.type || 'general'),
            tab_index: '0'
          },
          apns: {
            headers: {
              'apns-expiration': String(Math.floor(Date.now() / 1000) + ttlSeconds)
            },
            payload: {
              aps: {
                sound: 'default',
                badge: 1
              }
            }
          },
          android: {
            priority: 'high',
            ttl: ttlSeconds * 1000, // in Millisekunden
            notification: {
              channelId: getChannelId(data.notification.type),
              sound: 'default'
            }
          }
        };
      });

      // Send in batches of 500
      let successCount = 0;
      let failCount = 0;
      const failedTokens = [];

      for (let i = 0; i < messages.length; i += 500) {
        const batch = messages.slice(i, i + 500);

        try {
          const response = await admin.messaging().sendEach(batch);
          successCount += response.successCount;
          failCount += response.failureCount;

          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const error = resp.error;
              console.error(`❌ Failed: ${error.code}`);

              if (error.code === 'messaging/invalid-registration-token' ||
                  error.code === 'messaging/registration-token-not-registered') {
                failedTokens.push(batch[idx].token);
              }
            }
          });

        } catch (error) {
          console.error('❌ Batch send error:', error);
          failCount += batch.length;
        }
      }

      // Mark all as sent
      const updateBatches = [];
      let updateBatch = admin.firestore().batch();
      let updateCounter = 0;

      snapshot.docs.forEach(doc => {
        if (updateCounter >= 500) {
          updateBatches.push(updateBatch);
          updateBatch = admin.firestore().batch();
          updateCounter = 0;
        }

        updateBatch.update(doc.ref, {
          sent: true,
          sent_at: admin.firestore.FieldValue.serverTimestamp()
        });
        updateCounter++;
      });

      if (updateCounter > 0) {
        updateBatches.push(updateBatch);
      }

      await Promise.all(updateBatches.map(b => b.commit()));

      // Cleanup invalid tokens (mark inactive + TTL for auto-deletion)
      if (failedTokens.length > 0) {
        console.log(`🧹 Cleaning up ${failedTokens.length} invalid tokens...`);
        const cleanupBatch = admin.firestore().batch();
        const ttlExpireAt = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // Delete in 7 days
        );

        for (const token of failedTokens) {
          const tokenRef = admin.firestore().collection('fcm_tokens').doc(token);
          cleanupBatch.update(tokenRef, {
            active: false,
            invalidated_at: admin.firestore.FieldValue.serverTimestamp(),
            ttl_expire_at: ttlExpireAt
          });
        }

        await cleanupBatch.commit();
      }

      const duration = Date.now() - startTime;
      console.log(`✅ Completed in ${duration}ms - Sent: ${successCount}, Failed: ${failCount}`);

      if (duration > 240000) {
        console.warn('⚠️ Approaching timeout! Duration:', duration, 'ms');
      }

      return null;

    } catch (error) {
      console.error('❌ Fatal error:', error);
      throw error;
    }
  });

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

function getNotificationTTL(notificationType) {
  switch (notificationType) {
    case 'cheapest_hour':
      return 15 * 60; // 15 Minuten (dringend!)
    case 'threshold_alert':
      return 15 * 60; // 10 Minuten (sehr dringend!)
    case 'daily_summary':
      return 2 * 60 * 60; // 2 Stunden (nicht so kritisch)
    default:
      return 30 * 60; // 30 Minuten default
  }
}

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

  const roundToNearestFiveMinutes = (date) => {
    const rounded = new Date(date);
    const minutes = rounded.getMinutes();
    const roundedMinutes = Math.round(minutes / 5) * 5;
    rounded.setMinutes(roundedMinutes);
    rounded.setSeconds(0);
    rounded.setMilliseconds(0);
    return rounded;
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

    // Convert back to UTC for Firestore
    let sendAt = toUTC(localSendAt);
    sendAt = roundToNearestFiveMinutes(sendAt);

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
      let sendAt = new Date(hour.startTime);
      const minutesBefore = user.notification_minutes_before ?? 15;
      sendAt.setMinutes(sendAt.getMinutes() - minutesBefore);
      sendAt = roundToNearestFiveMinutes(sendAt);

      if (sendAt > now && !isInQuietTime(sendAt, user, userTimezoneOffset)) {
        const fullCost = calculateFullCost(hour.price, user);
        const priceText = user.full_cost_mode
          ? `${fullCost.toFixed(2)} ct/kWh (Vollkosten)`
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
      let sendAt = new Date(period.startTime);
      sendAt.setMinutes(sendAt.getMinutes() - 5); // ✅ Fixed 5min (urgent!)
      sendAt = roundToNearestFiveMinutes(sendAt);

      if (sendAt > now && !isInQuietTime(sendAt, user, userTimezoneOffset)) {
        const effectivePrice = calculateFullCost(period.price, user);
        const priceText = user.full_cost_mode
          ? `${effectivePrice.toFixed(2)} ct/kWh (Vollkosten)`
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

  // Group prices by day
  const pricesByDay = {};
  for (const price of prices) {
    const date = new Date(price.startTime);
    const dayKey = `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;

    if (!pricesByDay[dayKey]) {
      pricesByDay[dayKey] = [];
    }
    pricesByDay[dayKey].push(price);
  }

  // Find cheapest hour per day (only complete days with 24 hours)
  for (const [dayKey, dayPrices] of Object.entries(pricesByDay)) {
    if (dayPrices.length >= 24) {
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
// EVENT QUEUE: Process notification events (Option 3 implementation)
// Triggered when app writes to notification_events collection
// ========================================================================
exports.processNotificationEvents = functions
  .region('europe-west3')
  .runWith({
    timeoutSeconds: 120,
    memory: '512MB'
  })
  .firestore.document('notification_events/{eventId}')
  .onCreate(async (snap, context) => {
    const event = snap.data();
    const eventId = context.params.eventId;

    console.log(`📨 Processing event: ${event.event_type} for token: ${event.fcm_token}`);

    try {
      switch (event.event_type) {
        case 'settings_changed':
          await handleSettingsChanged(event.fcm_token);
          break;

        case 'reminder_added':
          // Future: Handle window reminder added
          console.log('reminder_added event - not yet implemented');
          break;

        case 'all_reminders_cancelled':
          // Future: Cancel all window reminders for user
          console.log('all_reminders_cancelled event - not yet implemented');
          break;

        default:
          console.warn(`⚠️ Unknown event type: ${event.event_type}`);
      }

      // Mark event as processed (or delete it)
      await snap.ref.delete();
      console.log(`✅ Event ${eventId} processed and deleted`);

    } catch (error) {
      console.error(`❌ Error processing event ${eventId}:`, error);

      // Mark as failed (keep for debugging)
      await snap.ref.update({
        processed: true,
        error: error.message,
        failed_at: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    return null;
  });

// ========================================================================
// Handle settings_changed event
// Cancel all scheduled notifications for user and reschedule with new settings
// ========================================================================
async function handleSettingsChanged(fcmToken) {
  console.log(`[Settings Changed] Processing for token: ${fcmToken}`);

  try {
    // STEP 1: Delete all pending notifications for this user
    const deletedCount = await cancelUserNotifications(fcmToken);
    console.log(`[Settings Changed] Cancelled ${deletedCount} pending notifications`);

    // STEP 2: Get latest user preferences
    const userDoc = await admin.firestore()
      .collection('notification_preferences')
      .doc(fcmToken)
      .get();

    if (!userDoc.exists) {
      console.log('[Settings Changed] No preferences found - user may have disabled all notifications');
      return;
    }

    const user = userDoc.data();

    // Check if any notifications are enabled
    if (!user.has_any_notification_enabled) {
      console.log('[Settings Changed] All notifications disabled - nothing to schedule');
      return;
    }

    // STEP 3: Get latest prices for user's market
    const prices = await getLatestPrices(user.market);

    if (!prices || prices.prices.length === 0) {
      console.log(`[Settings Changed] No prices available for market ${user.market}`);
      return;
    }

    // STEP 4: Calculate and schedule new notifications
    const notifications = calculateUserNotifications(user, prices);
    const scheduledCount = await scheduleNotifications(fcmToken, user.market, notifications);

    console.log(`[Settings Changed] ✅ Rescheduled ${scheduledCount} notifications`);

  } catch (error) {
    console.error('[Settings Changed] ❌ Error:', error);
    throw error;
  }
}

// Cancel all unsent notifications for a user
async function cancelUserNotifications(fcmToken) {
  const snapshot = await admin.firestore()
    .collection('scheduled_notifications')
    .where('fcm_token', '==', fcmToken)
    .where('sent', '==', false)
    .get();

  if (snapshot.empty) {
    return 0;
  }

  // Delete in batches of 500
  const batches = [];
  let currentBatch = admin.firestore().batch();
  let counter = 0;

  snapshot.docs.forEach(doc => {
    if (counter >= 500) {
      batches.push(currentBatch);
      currentBatch = admin.firestore().batch();
      counter = 0;
    }
    currentBatch.delete(doc.ref);
    counter++;
  });

  if (counter > 0) {
    batches.push(currentBatch);
  }

  await Promise.all(batches.map(b => b.commit()));
  return snapshot.size;
}

// Get latest prices from Firestore cache
async function getLatestPrices(market) {
  try {
    const pricesDoc = await admin.firestore()
      .collection('price_cache')
      .doc(market)
      .get();

    if (!pricesDoc.exists) {
      console.warn(`No cached prices found for market ${market}`);
      return null;
    }

    return pricesDoc.data();
  } catch (error) {
    console.error(`Error fetching prices for ${market}:`, error);
    return null;
  }
}

// Schedule notifications for a user
async function scheduleNotifications(fcmToken, market, notifications) {
  if (notifications.length === 0) {
    return 0;
  }

  const batches = [];
  let currentBatch = admin.firestore().batch();
  let counter = 0;

  for (const notification of notifications) {
    if (counter >= 500) {
      batches.push(currentBatch);
      currentBatch = admin.firestore().batch();
      counter = 0;
    }

    const docRef = admin.firestore()
      .collection('scheduled_notifications')
      .doc();

    const ttlSeconds = getNotificationTTL(notification.type);
    const expireAt = new Date(notification.sendAt.getTime() + ttlSeconds * 1000);

    currentBatch.set(docRef, {
      fcm_token: fcmToken,
      user_market: market,
      notification: {
        title: notification.title,
        body: notification.body,
        type: notification.type
      },
      send_at: admin.firestore.Timestamp.fromDate(notification.sendAt),
      expireAt: admin.firestore.Timestamp.fromDate(expireAt),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      sent: false
    });

    counter++;
  }

  if (counter > 0) {
    batches.push(currentBatch);
  }

  await Promise.all(batches.map(b => b.commit()));
  return notifications.length;
}
