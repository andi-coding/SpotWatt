/**
 * CloudFlare Worker for SpotWatt
 * Proxy for ENTSO-E Transparency Platform API
 */

// ENTSO-E API configuration
const ENTSOE_API_URL = 'https://web-api.tp.entsoe.eu/api';

// Market area codes (EIC codes)
const MARKET_AREAS = {
  AT: '10YAT-APG------L', // Austria
  DE: '10Y1001A1001A82H'  // Germany
};

// Document type for day-ahead prices
const DOCUMENT_TYPE = 'A44'; // Day-ahead prices

// Timezone mapping for markets
const MARKET_TIMEZONES = {
  AT: 'Europe/Vienna',
  DE: 'Europe/Berlin'
};

/**
 * Get trading day boundaries in UTC for a given market's timezone
 * Automatically handles MESZ (UTC+2) and MEZ (UTC+1)
 * @param {string} timezone - IANA timezone (e.g., 'Europe/Vienna')
 * @returns {Object} { periodStart: Date, periodEnd: Date }
 */
function getTradingDayUTC(timezone) {
  const now = new Date();

  // Get current date in the target timezone (format: "2025-10-05")
  const localDateStr = new Intl.DateTimeFormat('sv-SE', {
    timeZone: timezone
  }).format(now);
  const [year, month, day] = localDateStr.split('-').map(Number);

  // Calculate UTC offset for this timezone (handles DST automatically)
  const utcDate = new Date(now.toLocaleString('en-US', { timeZone: 'UTC' }));
  const tzDate = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
  const offsetHours = Math.abs((utcDate.getTime() - tzDate.getTime()) / (1000 * 60 * 60));

  // Trading day starts at 00:00 local time = (24 - offset) UTC on previous day
  // MESZ (UTC+2): 22:00 UTC, MEZ (UTC+1): 23:00 UTC
  const utcHour = 24 - offsetHours;

  const periodStart = new Date(Date.UTC(year, month - 1, day - 1, utcHour, 0, 0));
  const periodEnd = new Date(periodStart.getTime() + 48 * 60 * 60 * 1000);

  console.log(`[${timezone}] Local date: ${localDateStr}, Offset: UTC+${offsetHours}, Period: ${periodStart.toISOString()} to ${periodEnd.toISOString()}`);

  return { periodStart, periodEnd };
}

// Helper to fetch raw XML from ENTSO-E (for debugging or position checking)
async function fetchRawXML(market, apiToken, position = null, daysOffset = 0) {
  const areaCode = MARKET_AREAS[market];
  if (!areaCode) {
    throw new Error(`Invalid market: ${market}`);
  }

  // Get timezone for this market
  const timezone = MARKET_TIMEZONES[market] || 'Europe/Vienna';

  // Calculate trading day boundaries in UTC based on local timezone
  const { periodStart: periodStartDate, periodEnd: periodEndDate } = getTradingDayUTC(timezone);

  // Apply days offset to periodStart only (to query specific day within 48h window)
  if (daysOffset !== 0) {
    periodStartDate.setDate(periodStartDate.getDate() + daysOffset);
  }

  // Format dates as required by ENTSO-E (yyyyMMddHHmm)
  const periodStart = formatDateENTSOE(periodStartDate);
  const periodEnd = formatDateENTSOE(periodEndDate);

  const params = new URLSearchParams({
    securityToken: apiToken,
    documentType: DOCUMENT_TYPE,
    in_Domain: areaCode,
    out_Domain: areaCode,
    periodStart: periodStart,
    periodEnd: periodEnd,
    'contract_MarketAgreement.type': 'A01' // Only Day-ahead, not Intraday
  });

  // Optionally filter by position
  if (position !== null) {
    params.set('classificationSequence_AttributeInstanceComponent.position', position.toString());
  }

  const response = await fetchWithRetry(`${ENTSOE_API_URL}?${params}`);
  return await response.text();
}

// Helper to fetch from ENTSO-E
async function fetchFromENTSOE(market, apiToken) {
  const areaCode = MARKET_AREAS[market];
  if (!areaCode) {
    throw new Error(`Invalid market: ${market}`);
  }

  // Get timezone for this market
  const timezone = MARKET_TIMEZONES[market] || 'Europe/Vienna';

  // Calculate trading day boundaries in UTC based on local timezone
  // This automatically handles MESZ (UTC+2) and MEZ (UTC+1)
  const { periodStart: periodStartDate, periodEnd: periodEndDate } = getTradingDayUTC(timezone);

  // Format dates as required by ENTSO-E (yyyyMMddHHmm)
  const periodStart = formatDateENTSOE(periodStartDate);
  const periodEnd = formatDateENTSOE(periodEndDate);

  const params = new URLSearchParams({
    securityToken: apiToken,
    documentType: DOCUMENT_TYPE,
    in_Domain: areaCode,
    out_Domain: areaCode,
    periodStart: periodStart,
    periodEnd: periodEnd,
    'contract_MarketAgreement.type': 'A01' // Only Day-ahead, not Intraday
    // Note: NO position filter - we fetch all data and select Position 1 > Position 2 in parser
  });

  const apiUrl = `${ENTSOE_API_URL}?${params}`;
  console.log(`[${market}] 🌐 ENTSO-E API Request: periodStart=${periodStart}, periodEnd=${periodEnd}`);
  console.log(`[${market}] 🔗 Full URL: ${apiUrl.replace(apiToken, 'REDACTED')}`);

  try {
    const response = await fetchWithRetry(apiUrl);
    const xmlData = await response.text();
    console.log(`ENTSO-E XML Response for ${market}:`, xmlData.substring(0, 2000) + '...');
    const prices = parseENTSOEResponse(xmlData, market);

    return {
      lastUpdate: new Date().toISOString(),
      market: market,
      prices: prices
    };
  } catch (error) {
    console.error(`Error fetching from ENTSO-E ${market}:`, error);
    throw error;
  }
}

// Retry helper for ENTSO-E API calls
async function fetchWithRetry(url, retries = 2, delay = 2000) {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch(url);

      if (response.ok) {
        return response;
      }

      const errorText = await response.text();

      // Check for retryable errors
      const isRetryable = response.status === 503 ||
                          response.status === 502 || // Bad Gateway
                          response.status === 504 || // Gateway Timeout
                          (response.status === 400 && (
                            errorText.includes('<code>999</code>') ||
                            errorText.includes('Unexpected error') ||
                            errorText.includes('server error') ||
                            errorText.includes('temporary') ||
                            errorText.includes('maintenance') ||
                            errorText.includes('overload')
                          )) ||
                          (response.status === 429); // Rate Limit (should retry with backoff)

      if (isRetryable) {
        console.log(`ENTSO-E ${response.status} error (attempt ${i + 1}/${retries}), retrying in ${delay * (i + 1)}ms...`);
        if (i < retries - 1) {
          await new Promise(resolve => setTimeout(resolve, delay * (i + 1)));
          continue;
        }
      }

      // Non-retryable error or final retry attempt
      throw new Error(`ENTSO-E API error: ${response.status} - ${errorText}`);
    } catch (error) {
      if (i === retries - 1) throw error;
      console.log(`Network error (attempt ${i + 1}/${retries}), retrying in ${delay * (i + 1)}ms...`);
      await new Promise(resolve => setTimeout(resolve, delay * (i + 1)));
    }
  }
}

// Format date for ENTSO-E API (yyyyMMddHHmm in UTC)
function formatDateENTSOE(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  const hour = String(date.getUTCHours()).padStart(2, '0');
  const minute = String(date.getUTCMinutes()).padStart(2, '0');
  return `${year}${month}${day}${hour}${minute}`;
}

// Parse ENTSO-E XML response
function parseENTSOEResponse(xmlString, market) {
  const allPrices = [];

  // Step 1: Parse all TimeSeries and group by position and period
  const timeSeriesMatches = xmlString.matchAll(/<TimeSeries>([\s\S]*?)<\/TimeSeries>/g);
  const timeSeriesByPeriod = {}; // Group by period start time

  for (const timeSeriesMatch of timeSeriesMatches) {
    const timeSeriesContent = timeSeriesMatch[1];

    // Extract position (may not exist for some countries)
    const positionMatch = timeSeriesContent.match(/<classificationSequence_AttributeInstanceComponent\.position>(.*?)<\/classificationSequence_AttributeInstanceComponent\.position>/);
    const position = positionMatch ? parseInt(positionMatch[1]) : null;

    // Parse periods within this TimeSeries
    const periodMatches = timeSeriesContent.matchAll(/<Period>([\s\S]*?)<\/Period>/g);

    for (const periodMatch of periodMatches) {
      const periodContent = periodMatch[1];

      // Extract resolution
      const resolutionMatch = periodContent.match(/<resolution>(.*?)<\/resolution>/);
      if (!resolutionMatch) continue;
      const resolution = resolutionMatch[1];

      // Extract time interval start and end
      const intervalStartMatch = periodContent.match(/<start>(.*?)<\/start>/);
      if (!intervalStartMatch) continue;
      const startTime = intervalStartMatch[1];

      const intervalEndMatch = periodContent.match(/<end>(.*?)<\/end>/);
      if (!intervalEndMatch) continue;
      const endTime = intervalEndMatch[1];

      // Validate: Period should be exactly 24 hours
      const periodStart = new Date(startTime);
      const periodEnd = new Date(endTime);
      const periodHours = (periodEnd - periodStart) / (1000 * 60 * 60);

      if (periodHours > 24) {
        // CRITICAL: Skip periods >24h to prevent incorrect time-to-price mapping
        console.error(`[${market}] ❌ Period ${startTime} spans ${periodHours} hours (>24) - SKIPPING to avoid data corruption!`);
        continue; // Skip this period entirely
      } else if (periodHours < 24) {
        // Warning: Partial data, but time mapping still correct
        console.warn(`[${market}] ⚠️ Period ${startTime} has only ${periodHours} hours - processing anyway (partial data)`);
      } else if (periodHours !== 24) {
        // Unusual decimal hours
        console.warn(`[${market}] ⚠️ Period ${startTime} has unusual duration: ${periodHours.toFixed(2)} hours`);
      }

      // Create key for grouping (period start time)
      const periodKey = startTime;

      if (!timeSeriesByPeriod[periodKey]) {
        timeSeriesByPeriod[periodKey] = {};
      }

      // Store TimeSeries by position (1, 2, or null)
      const posKey = position === null ? 'noPosition' : `pos${position}`;
      if (!timeSeriesByPeriod[periodKey][posKey] || resolution === 'PT60M') {
        // Prefer PT60M over PT15M for same position
        timeSeriesByPeriod[periodKey][posKey] = {
          position,
          resolution,
          startTime: new Date(startTime),
          periodContent
        };
      }
    }
  }

  // Step 2: Process each period, selecting best TimeSeries (Position 1 > Position 2 > no position)
  for (const periodKey of Object.keys(timeSeriesByPeriod)) {
    const periodsData = timeSeriesByPeriod[periodKey];

    // Select best TimeSeries: Position 1 > Position 2 > no position
    const selectedTimeSeries = periodsData.pos1 || periodsData.pos2 || periodsData.noPosition;

    if (!selectedTimeSeries) {
      console.warn(`[${market}] ⚠️ No TimeSeries data found for period ${periodKey}`);
      continue;
    }

    // Log position selection and resolution
    if (periodsData.pos1) {
      console.log(`[${market}] ✅ Period ${periodKey}: Using Position 1, Resolution: ${selectedTimeSeries.resolution}`);
    } else if (periodsData.pos2) {
      console.warn(`[${market}] ⚠️ Period ${periodKey}: Position 1 MISSING - Using Position 2 (fallback), Resolution: ${selectedTimeSeries.resolution}`);
    } else if (periodsData.noPosition) {
      console.log(`[${market}] ℹ️ Period ${periodKey}: Using data without position classification, Resolution: ${selectedTimeSeries.resolution}`);
    }

    const { resolution, startTime, periodContent } = selectedTimeSeries;

    if (resolution === 'PT60M') {
      // Process 60-minute data directly
      allPrices.push(...parse60MinuteData(periodContent, startTime, market));
    } else if (resolution === 'PT15M') {
      // Aggregate 15-minute data to hourly
      allPrices.push(...aggregate15MinToHourly(periodContent, startTime, market));
    }
  }

  // Sort by start time
  allPrices.sort((a, b) => new Date(a.startTime) - new Date(b.startTime));

  return allPrices;
}

// Parse 60-minute data
function parse60MinuteData(periodContent, startTime, market) {
  const prices = [];
  const pointMatches = periodContent.matchAll(/<Point>([\s\S]*?)<\/Point>/g);

  for (const pointMatch of pointMatches) {
    const pointContent = pointMatch[1];
    const positionMatch = pointContent.match(/<position>(\d+)<\/position>/);
    const priceMatch = pointContent.match(/<price\.amount>(-?[\d.]+)<\/price\.amount>/);

    if (positionMatch && priceMatch) {
      const position = parseInt(positionMatch[1]);
      const price = parseFloat(priceMatch[1]);

      const pointTime = new Date(startTime);
      pointTime.setUTCHours(pointTime.getUTCHours() + position - 1);

      const endTime = new Date(pointTime);
      endTime.setUTCHours(endTime.getUTCHours() + 1);

      prices.push({
        startTime: pointTime.toISOString(),
        endTime: endTime.toISOString(),
        price: price / 10.0 // EUR/MWh → ct/kWh
      });
    }
  }

  // Validate: Should have exactly 24 prices for PT60M
  if (prices.length !== 24) {
    console.warn(`[${market}] ⚠️ PT60M data has ${prices.length} prices (expected 24)`);
  }

  return prices;
}

// Aggregate 15-minute data to hourly (with Forward Fill for missing values)
function aggregate15MinToHourly(periodContent, startTime, market) {
  const prices = [];

  // Extract all 15-minute points
  const pointsMap = {};
  const pointMatches = periodContent.matchAll(/<Point>([\s\S]*?)<\/Point>/g);

  for (const pointMatch of pointMatches) {
    const pointContent = pointMatch[1];
    const positionMatch = pointContent.match(/<position>(\d+)<\/position>/);
    const priceMatch = pointContent.match(/<price\.amount>(-?[\d.]+)<\/price\.amount>/);

    if (positionMatch && priceMatch) {
      const position = parseInt(positionMatch[1]);
      const price = parseFloat(priceMatch[1]);
      pointsMap[position] = price;
    }
  }

  // Aggregate to hourly (4 × 15min = 1 hour)
  for (let hour = 0; hour < 24; hour++) {
    const quarterHourPositions = [
      hour * 4 + 1,
      hour * 4 + 2,
      hour * 4 + 3,
      hour * 4 + 4
    ];

    const values = [];
    let missingCount = 0;
    const missingPositions = [];

    for (const pos of quarterHourPositions) {
      if (pointsMap[pos] !== undefined) {
        values.push(pointsMap[pos]);
      } else {
        // Backward Fill: Use last known value (matches EPEX SPOT behavior)
        missingCount++;
        missingPositions.push(pos);
        if (values.length > 0) {
          // Use last known value from this hour
          const filledValue = values[values.length - 1];
          values.push(filledValue);
        } else {
          // If no previous value in this hour, try to find any previous value
          let filledValue = null;
          for (let prevPos = pos - 1; prevPos >= 1; prevPos--) {
            if (pointsMap[prevPos] !== undefined) {
              filledValue = pointsMap[prevPos];
              break;
            }
          }
          if (filledValue !== null) {
            values.push(filledValue);
          }
        }
      }
    }

    if (values.length > 0) {
      const avgPrice = values.reduce((sum, val) => sum + val, 0) / values.length;

      const pointTime = new Date(startTime);
      pointTime.setUTCHours(pointTime.getUTCHours() + hour);

      const endTime = new Date(pointTime);
      endTime.setUTCHours(endTime.getUTCHours() + 1);

      prices.push({
        startTime: pointTime.toISOString(),
        endTime: endTime.toISOString(),
        price: avgPrice / 10.0 // EUR/MWh → ct/kWh
      });

      if (missingCount > 0) {
        const hourStr = pointTime.toISOString().substring(11, 16);
        console.warn(`[${market}] ⚠️ Hour ${hourStr}: ${missingCount}/4 15-min slots missing (positions: ${missingPositions.join(', ')}), used Backward Fill → avg: ${(avgPrice / 10.0).toFixed(4)} ct/kWh`);
      }
    }
  }

  // Validate: Should have exactly 24 prices for 24 hours
  if (prices.length !== 24) {
    console.warn(`[${market}] ⚠️ PT15M aggregation resulted in ${prices.length} prices (expected 24)`);
  }

  // Validate: Check for too many points (shouldn't have more than 96)
  const totalPoints = Object.keys(pointsMap).length;
  const expectedPoints = 96;
  if (totalPoints > expectedPoints) {
    console.warn(`[${market}] ⚠️ PT15M data has ${totalPoints} points (expected max ${expectedPoints}) - possible duplicate or invalid data!`);
  }

  return prices;
}

// ===== ENERGY PROVIDER ENDPOINTS =====

/**
 * Get energy providers and tax rates for a specific region
 * GET /providers?region=AT
 */
async function handleGetProviders(request, env, headers) {
  try {
    if (!env.FCM_DB) {
      return new Response(
        JSON.stringify({ error: 'Database not configured' }),
        { status: 500, headers }
      );
    }

    const url = new URL(request.url);
    const region = url.searchParams.get('region') || 'AT';

    // Validate region
    if (!['AT', 'DE'].includes(region)) {
      return new Response(
        JSON.stringify({ error: 'Invalid region (must be AT or DE)' }),
        { status: 400, headers }
      );
    }

    // Fetch providers for region
    const providers = await env.FCM_DB.prepare(`
      SELECT
        provider_name,
        markup_percentage,
        markup_fixed_ct_kwh,
        base_fee_monthly_eur
      FROM energy_providers
      WHERE region = ? AND active = 1
      ORDER BY display_order, provider_name
    `).bind(region).all();

    // Fetch tax rate for region
    const taxRateResult = await env.FCM_DB.prepare(`
      SELECT tax_percentage
      FROM tax_rates
      WHERE region = ?
    `).bind(region).first();

    const taxRate = taxRateResult?.tax_percentage || (region === 'AT' ? 20.0 : 19.0);

    console.log(`[Providers] ✅ Fetched ${providers.results.length} providers for ${region}`);

    return new Response(
      JSON.stringify({
        region: region,
        tax_rate: taxRate,
        providers: providers.results,
        version: 1,
        last_updated: new Date().toISOString()
      }),
      {
        headers: {
          ...headers,
          'Cache-Control': 'public, max-age=86400, s-maxage=86400' // 1 day cache
        }
      }
    );
  } catch (error) {
    console.error('[Providers] Error fetching providers:', error);
    return new Response(
      JSON.stringify({ error: 'Failed to fetch providers', details: error.message }),
      { status: 500, headers }
    );
  }
}

// ===== FCM ENDPOINTS =====

/**
 * Handle FCM device token registration
 */
async function handleFCMRegister(request, env, headers) {
  try {
    if (!env.FCM_DB) {
      return new Response(
        JSON.stringify({ error: 'FCM database not configured' }),
        { status: 500, headers }
      );
    }

    const body = await request.json();
    const { token, platform, region } = body;

    // Validate input
    if (!token || typeof token !== 'string' || token.length < 10) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 400, headers }
      );
    }

    if (!platform || !['android', 'ios'].includes(platform)) {
      return new Response(
        JSON.stringify({ error: 'Invalid platform (must be android or ios)' }),
        { status: 400, headers }
      );
    }

    const userRegion = region || 'AT';

    // Upsert token (insert or update if exists)
    await env.FCM_DB.prepare(`
      INSERT INTO fcm_tokens (token, platform, region, last_seen, active)
      VALUES (?, ?, ?, CURRENT_TIMESTAMP, 1)
      ON CONFLICT(token) DO UPDATE SET
        last_seen = CURRENT_TIMESTAMP,
        active = 1,
        platform = excluded.platform,
        region = excluded.region
    `).bind(token, platform, userRegion).run();

    console.log(`[FCM] ✅ Registered ${platform} token from ${userRegion}: ${token.substring(0, 20)}...`);

    return new Response(
      JSON.stringify({ success: true, message: 'Token registered' }),
      { headers }
    );
  } catch (error) {
    console.error('[FCM] Error registering token:', error);
    return new Response(
      JSON.stringify({ error: 'Failed to register token', details: error.message }),
      { status: 500, headers }
    );
  }
}

/**
 * Handle FCM device token unregistration
 */
async function handleFCMUnregister(request, env, headers) {
  try {
    if (!env.FCM_DB) {
      return new Response(
        JSON.stringify({ error: 'FCM database not configured' }),
        { status: 500, headers }
      );
    }

    const body = await request.json();
    const { token } = body;

    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Missing token' }),
        { status: 400, headers }
      );
    }

    // Mark token as inactive (soft delete)
    await env.FCM_DB.prepare(`
      UPDATE fcm_tokens
      SET active = 0, last_seen = CURRENT_TIMESTAMP
      WHERE token = ?
    `).bind(token).run();

    console.log(`[FCM] ✅ Unregistered token: ${token.substring(0, 20)}...`);

    return new Response(
      JSON.stringify({ success: true, message: 'Token unregistered' }),
      { headers }
    );
  } catch (error) {
    console.error('[FCM] Error unregistering token:', error);
    return new Response(
      JSON.stringify({ error: 'Failed to unregister token', details: error.message }),
      { status: 500, headers }
    );
  }
}

export default {
  async fetch(request, env, ctx) {
    // CORS headers
    const headers = {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Cache-Control': 'public, max-age=900, s-maxage=3600' // Browser: 15min, CDN: 1h
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers });
    }

    const url = new URL(request.url);

    // FCM Endpoints
    if (url.pathname === '/fcm/register' && request.method === 'POST') {
      return handleFCMRegister(request, env, headers);
    }

    if (url.pathname === '/fcm/unregister' && request.method === 'POST') {
      return handleFCMUnregister(request, env, headers);
    }

    // Energy Provider Endpoints
    if (url.pathname === '/providers' && request.method === 'GET') {
      return handleGetProviders(request, env, headers);
    }

    const market = url.searchParams.get('market') || 'AT';
    const adminKey = url.searchParams.get('key');
    const debug = url.searchParams.get('debug') === 'xml' && adminKey === env.ADMIN_API_KEY;
    const clearCache = url.searchParams.get('clear') === 'cache' && adminKey === env.ADMIN_API_KEY;
    const testCron = url.searchParams.get('test') === 'cron' && adminKey === env.ADMIN_API_KEY;

    // Validate market parameter
    if (!['AT', 'DE'].includes(market)) {
      return new Response(
        JSON.stringify({ error: 'Invalid market. Use AT or DE.' }),
        { status: 400, headers }
      );
    }

    // Check if ENTSO-E API token is configured
    if (!env.ENTSOE_API_TOKEN) {
      return new Response(
        JSON.stringify({ error: 'ENTSO-E API token not configured' }),
        { status: 500, headers }
      );
    }

    try {
      // Check for unauthorized admin attempts
      if ((url.searchParams.get('debug') === 'xml' || url.searchParams.get('clear') === 'cache' || url.searchParams.get('test') === 'cron') && !adminKey) {
        return new Response(
          JSON.stringify({ error: 'Admin functions require authentication' }),
          { status: 403, headers }
        );
      }

      // Handle cache clearing
      if (clearCache && env.PRICE_CACHE) {
        await Promise.all([
          env.PRICE_CACHE.delete('prices_AT'),
          env.PRICE_CACHE.delete('prices_DE')
        ]);
        return new Response(
          JSON.stringify({ message: 'Cache cleared successfully' }),
          { headers }
        );
      }

      // Handle test cron job (manual trigger for debugging)
      if (testCron) {
        console.log('🔧 Manual cron test triggered via API');
        try {
          // Run the same logic as scheduled job, but always send FCM (even if no update needed)
          await runScheduledJob(env, true);
          return new Response(
            JSON.stringify({
              message: 'Cron job executed successfully (FCM sent)',
              timestamp: new Date().toISOString()
            }),
            { headers }
          );
        } catch (error) {
          console.error('❌ Test cron failed:', error);
          return new Response(
            JSON.stringify({
              error: 'Cron job failed',
              details: error.message,
              timestamp: new Date().toISOString()
            }),
            { status: 500, headers }
          );
        }
      }

      // Try to get from cache first (skip cache in debug mode)
      if (env.PRICE_CACHE && !debug) {
        const cached = await env.PRICE_CACHE.get(`prices_${market}`);
        if (cached) {
          // Return cached data if available (even if tomorrow's prices are missing)
          // The scheduled cron job will update the cache when needed
          return new Response(cached, { headers });
        }
      }

      // Fetch fresh data from ENTSO-E
      if (debug) {
        // Debug mode: return raw XML
        const xmlData = await fetchRawXML(market, env.ENTSOE_API_TOKEN);
        return new Response(xmlData, {
          headers: { ...headers, 'Content-Type': 'text/xml' }
        });
      }

      const data = await fetchFromENTSOE(market, env.ENTSOE_API_TOKEN);

      // Cache the data for 36 hours (safety buffer if tomorrow's prices are late)
      if (env.PRICE_CACHE) {
        await env.PRICE_CACHE.put(`prices_${market}`, JSON.stringify(data), {
          expirationTtl: 172800 // Cache for 48 hours
        });
      }

      return new Response(
        JSON.stringify(data),
        { headers }
      );
    } catch (error) {
      console.error('Error in fetch handler:', error);
      return new Response(
        JSON.stringify({
          error: 'Failed to fetch prices',
          details: error.message
        }),
        { status: 500, headers }
      );
    }
  },

  // Scheduled handler - runs multiple times starting at 14:00 UTC
  async scheduled(event, env, ctx) {
    await runScheduledJob(env, false);
  }
};

// Run scheduled job logic (shared between cron and manual test trigger)
async function runScheduledJob(env, alwaysSendFCM = false) {
  const now = new Date();
  console.log('🕐 Scheduled task running at', now.toISOString());

  if (!env.ENTSOE_API_TOKEN) {
    console.error('ENTSO-E API token not configured');
    return;
  }

  // Check if we already have tomorrow's prices in cache
  const needsUpdate = await checkIfUpdateNeeded(env);

  if (needsUpdate) {
    console.log('📥 Missing tomorrow prices, fetching from ENTSO-E...');

    // Get current attempt counter (resets on successful update or at midnight UTC)
    const todayKey = `attempt_count_${now.toISOString().split('T')[0]}`;
    let attemptCount = 1;

    if (env.PRICE_CACHE) {
      const cachedCount = await env.PRICE_CACHE.get(todayKey);
      attemptCount = cachedCount ? parseInt(cachedCount) + 1 : 1;

      // Store updated count (expires in 6 hours - enough for all retries)
      await env.PRICE_CACHE.put(todayKey, attemptCount.toString(), {
        expirationTtl: 21600 // 6 hours
      });
    }

    console.log(`🔄 Attempt ${attemptCount} for today`);

    // Emergency fallback on 5th attempt (regardless of time)
    const isLastAttempt = attemptCount >= 5;

    if (isLastAttempt) {
      console.warn('⏰ Last cron attempt (5th try) - emergency fallback mode enabled');
    }

    const updateSuccess = await updatePricesFromENTSOE(env, isLastAttempt);

    // Reset counter on successful update
    if (updateSuccess && env.PRICE_CACHE) {
      await env.PRICE_CACHE.delete(todayKey);
      console.log('🔄 Counter reset - update successful');
    }

    // Send FCM push notifications if update was successful
    if (updateSuccess) {
      await sendFCMPushNotifications(env);
    }
  } else {
    console.log('✅ Already have tomorrow prices, skipping update');

    // For manual testing: always send FCM even if no update needed
    if (alwaysSendFCM) {
      console.log('🔧 Test mode: Sending FCM even though prices are up-to-date');
      await sendFCMPushNotifications(env);
    }
  }
}

// Check if we need to update prices
async function checkIfUpdateNeeded(env) {
  if (!env.PRICE_CACHE) return true;

  try {
    // Check both markets
    const [atCache, deCache] = await Promise.all([
      env.PRICE_CACHE.get('prices_AT'),
      env.PRICE_CACHE.get('prices_DE')
    ]);

    if (!atCache || !deCache) return true;

    const atData = JSON.parse(atCache);
    const deData = JSON.parse(deCache);

    // Check if both have tomorrow's prices
    return !hasTomorrowPrices(atData.prices) || !hasTomorrowPrices(deData.prices);
  } catch (error) {
    console.error('Error checking cache:', error);
    return true; // Update on error
  }
}

async function updatePricesFromENTSOE(env, isLastCronAttempt = false) {

  try {
    // Step 1: Check if AT Position 1 (EPEX) is available for tomorrow
    console.log('[AT] Checking for Position 1 (EPEX) availability for tomorrow...');
    const atPos1XML = await fetchRawXML('AT', env.ENTSOE_API_TOKEN, 1, 1); // Position 1, +1 day offset

    // Check if we have TimeSeries data (if empty = Position 1 not available yet)
    const hasTomorrowData = atPos1XML.includes('<TimeSeries>');

    if (!hasTomorrowData && !isLastCronAttempt) {
      // AT Position 1 not available yet for tomorrow - EPEX auction not finished
      console.log('⏳ AT Position 1 (EPEX) not yet available for tomorrow - skipping update, will retry later');
      return false; // Return false = update failed, keep counter running
    }

    if (!hasTomorrowData && isLastCronAttempt) {
      // Last attempt - use Position 2 as emergency fallback
      console.warn('⚠️ EMERGENCY FALLBACK: AT Position 1 still missing for tomorrow on last cron attempt - using Position 2 for both markets');
    } else {
      console.log('✅ AT Position 1 (EPEX) available for tomorrow - EPEX auction complete, proceeding with update');
    }

    // Step 2: Parse both markets (AT uses Pos1, DE uses Pos2)
    const [atData, deData] = await Promise.all([
      fetchFromENTSOE('AT', env.ENTSOE_API_TOKEN),
      fetchFromENTSOE('DE', env.ENTSOE_API_TOKEN)
    ]);

    // Log if we have tomorrow's prices (for monitoring)
    const hasATTomorrow = hasTomorrowPrices(atData.prices);
    const hasDETomorrow = hasTomorrowPrices(deData.prices);

    // Cache the data for 48 hours
    if (env.PRICE_CACHE) {
      await Promise.all([
        env.PRICE_CACHE.put('prices_AT', JSON.stringify(atData), {
          expirationTtl: 172800 // 48 hours
        }),
        env.PRICE_CACHE.put('prices_DE', JSON.stringify(deData), {
          expirationTtl: 172800 // 48 hours
        })
      ]);
    }

    console.log(`✅ Successfully updated prices - AT tomorrow: ${hasATTomorrow}, DE tomorrow: ${hasDETomorrow}`);
    return true; // Return true = update successful, reset counter
  } catch (error) {
    console.error('❌ Error updating prices from ENTSO-E:', error);
    // The cron job will retry automatically at next scheduled time
    return false; // Return false = update failed, keep counter running
  }
}

// Helper function to check if prices contain tomorrow's data
function hasTomorrowPrices(prices) {
  if (!prices || prices.length === 0) return false;

  const now = new Date();
  const tomorrowStart = new Date(now);
  tomorrowStart.setDate(tomorrowStart.getDate() + 1);
  tomorrowStart.setHours(0, 0, 0, 0); // Start of tomorrow

  const tomorrowEnd = new Date(tomorrowStart);
  tomorrowEnd.setHours(23, 59, 59, 999); // End of tomorrow

  // Check if we have at least one price point for tomorrow (between 00:00 and 23:59)
  return prices.some(price => {
    const priceTime = new Date(price.startTime);
    return priceTime >= tomorrowStart && priceTime <= tomorrowEnd;
  });
}

/**
 * Send FCM push notifications to all registered devices
 * This is a wake-up signal - the app will pull data from the worker
 */
async function sendFCMPushNotifications(env) {
  try {
    if (!env.FCM_DB) {
      console.log('[FCM] FCM database not configured, skipping push notifications');
      return;
    }

    if (!env.FIREBASE_SERVICE_ACCOUNT_KEY) {
      console.log('[FCM] Firebase service account key not configured, skipping push notifications');
      return;
    }

    // Get all active tokens from database
    const result = await env.FCM_DB.prepare(`
      SELECT token, platform, region FROM fcm_tokens WHERE active = 1
    `).all();

    if (!result.results || result.results.length === 0) {
      console.log('[FCM] No active tokens found, skipping push notifications');
      return;
    }

    console.log(`[FCM] 📤 Sending push notifications to ${result.results.length} devices...`);

    // Get Firebase access token
    const accessToken = await getFirebaseAccessToken(env.FIREBASE_SERVICE_ACCOUNT_KEY);

    if (!accessToken) {
      console.error('[FCM] Failed to get Firebase access token');
      return;
    }

    // Send FCM messages in parallel (faster for many tokens)
    const sendPromises = result.results.map(async (row) => {
      const { token, platform, region } = row;

      try {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/spotwatt-900e9/messages:send`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${accessToken}`
            },
            body: JSON.stringify({
              message: {
                token: token,
                // Data-only message with high priority for Doze Mode bypass
                // No notification key = pure background processing
                data: {
                  action: 'update_prices'
                },
                android: {
                  priority: 'high'  // Bypass Doze Mode for immediate delivery
                },
                apns: {
                  headers: {
                    'apns-priority': '5',        // Low priority for background content
                    'apns-push-type': 'background'  // Required for iOS 13+ silent push
                  },
                  payload: {
                    aps: {
                      'content-available': 1  // Wake app for background processing
                    }
                  }
                }
              }
            })
          }
        );

        if (response.ok) {
          return { success: true, token: null };
        } else {
          const errorData = await response.text();
          console.error(`[FCM] Failed to send to ${platform}/${region}: ${response.status} - ${errorData}`);

          // Check for invalid/unregistered token errors
          const isInvalid = errorData.includes('UNREGISTERED') || errorData.includes('INVALID_ARGUMENT');
          return { success: false, token: isInvalid ? token : null };
        }
      } catch (error) {
        console.error(`[FCM] Error sending to ${platform}/${region}:`, error);
        return { success: false, token: null };
      }
    });

    // Wait for all sends to complete
    const results = await Promise.allSettled(sendPromises);

    // Count results and collect invalid tokens
    const invalidTokens = [];
    let successCount = 0;
    let errorCount = 0;

    results.forEach((result) => {
      if (result.status === 'fulfilled') {
        if (result.value.success) {
          successCount++;
        } else {
          errorCount++;
          if (result.value.token) {
            invalidTokens.push(result.value.token);
          }
        }
      } else {
        errorCount++;
      }
    });

    // Mark invalid tokens as inactive and update last_seen timestamp
    if (invalidTokens.length > 0) {
      console.log(`[FCM] Marking ${invalidTokens.length} invalid tokens as inactive`);
      for (const token of invalidTokens) {
        await env.FCM_DB.prepare(`
          UPDATE fcm_tokens
          SET active = 0,
              last_seen = CURRENT_TIMESTAMP
          WHERE token = ?
        `).bind(token).run();
      }
    }

    // Auto-cleanup: Delete tokens that have been inactive for >7 days
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const deletedResult = await env.FCM_DB.prepare(`
      DELETE FROM fcm_tokens
      WHERE active = 0 AND last_seen < ?
    `).bind(sevenDaysAgo).run();

    if (deletedResult.meta?.changes > 0) {
      console.log(`[FCM] 🗑️ Cleaned up ${deletedResult.meta.changes} old inactive tokens (>7 days)`);
    }

    console.log(`[FCM] ✅ Push notifications sent: ${successCount} success, ${errorCount} errors, ${invalidTokens.length} invalid tokens removed`);
  } catch (error) {
    console.error('[FCM] Error sending push notifications:', error);
  }
}

/**
 * Get Firebase access token using service account key
 */
async function getFirebaseAccessToken(serviceAccountKeyJSON) {
  try {
    const serviceAccount = JSON.parse(serviceAccountKeyJSON);

    // Create JWT for Firebase
    const now = Math.floor(Date.now() / 1000);
    const header = {
      alg: 'RS256',
      typ: 'JWT'
    };
    const payload = {
      iss: serviceAccount.client_email,
      sub: serviceAccount.client_email,
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
      scope: 'https://www.googleapis.com/auth/firebase.messaging'
    };

    // Import private key
    const privateKey = await crypto.subtle.importKey(
      'pkcs8',
      pemToArrayBuffer(serviceAccount.private_key),
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256'
      },
      false,
      ['sign']
    );

    // Sign JWT
    const encodedHeader = base64UrlEncode(JSON.stringify(header));
    const encodedPayload = base64UrlEncode(JSON.stringify(payload));
    const unsignedToken = `${encodedHeader}.${encodedPayload}`;

    const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      privateKey,
      new TextEncoder().encode(unsignedToken)
    );

    const jwt = `${unsignedToken}.${base64UrlEncode(signature)}`;

    // Exchange JWT for access token
    const response = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('[FCM] Failed to get access token:', errorText);
      return null;
    }

    const data = await response.json();
    return data.access_token;
  } catch (error) {
    console.error('[FCM] Error getting Firebase access token:', error);
    return null;
  }
}

// Helper: Convert PEM to ArrayBuffer
function pemToArrayBuffer(pem) {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// Helper: Base64 URL encode
function base64UrlEncode(data) {
  let base64;
  if (typeof data === 'string') {
    base64 = btoa(data);
  } else if (data instanceof ArrayBuffer) {
    base64 = btoa(String.fromCharCode(...new Uint8Array(data)));
  } else {
    throw new Error('Invalid data type for base64UrlEncode');
  }
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}