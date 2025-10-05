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

// Helper to fetch raw XML from ENTSO-E (for debugging)
async function fetchRawXML(market, apiToken) {
  const areaCode = MARKET_AREAS[market];
  if (!areaCode) {
    throw new Error(`Invalid market: ${market}`);
  }

  // Get timezone for this market
  const timezone = MARKET_TIMEZONES[market] || 'Europe/Vienna';

  // Calculate trading day boundaries in UTC based on local timezone
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
    'contract_MarketAgreement.type': 'A01', // Only Day-ahead, not Intraday
    'classificationSequence_AttributeInstanceComponent.position': '1' // Only position 1 (hourly)
  });

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

export default {
  async fetch(request, env, ctx) {
    // CORS headers
    const headers = {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Cache-Control': 'public, max-age=900, s-maxage=3600' // Browser: 15min, CDN: 1h
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers });
    }

    const url = new URL(request.url);
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
          await updatePricesFromENTSOE(env);
          return new Response(
            JSON.stringify({
              message: 'Cron job executed successfully',
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
    console.log('Scheduled task running at', new Date().toISOString());

    if (!env.ENTSOE_API_TOKEN) {
      console.error('ENTSO-E API token not configured');
      return;
    }

    // Check if we already have tomorrow's prices in cache
    const needsUpdate = await checkIfUpdateNeeded(env);

    if (needsUpdate) {
      console.log('Missing tomorrow prices, fetching from ENTSO-E...');
      await updatePricesFromENTSOE(env);
    } else {
      console.log('Already have tomorrow prices, skipping update');
    }
  }
};

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

async function updatePricesFromENTSOE(env) {

  try {
    // Fetch both markets
    const [atData, deData] = await Promise.all([
      fetchFromENTSOE('AT', env.ENTSOE_API_TOKEN),
      fetchFromENTSOE('DE', env.ENTSOE_API_TOKEN)
    ]);

    // Log if we have tomorrow's prices (for monitoring)
    const hasATTomorrow = hasTomorrowPrices(atData.prices);
    const hasDETomorrow = hasTomorrowPrices(deData.prices);

    // Cache the data for 36 hours (safety buffer for late updates)
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

    console.log(`Successfully updated prices - AT tomorrow: ${hasATTomorrow}, DE tomorrow: ${hasDETomorrow}`);
  } catch (error) {
    console.error('Error updating prices from ENTSO-E:', error);
    // The cron job will retry automatically in 5 minutes
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