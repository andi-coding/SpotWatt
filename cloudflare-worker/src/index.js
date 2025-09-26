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

// Helper to fetch raw XML from ENTSO-E (for debugging)
async function fetchRawXML(market, apiToken) {
  const areaCode = MARKET_AREAS[market];
  if (!areaCode) {
    throw new Error(`Invalid market: ${market}`);
  }

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const dayAfterTomorrow = new Date(today);
  dayAfterTomorrow.setDate(dayAfterTomorrow.getDate() + 2);

  const periodStart = formatDateENTSOE(today);
  const periodEnd = formatDateENTSOE(dayAfterTomorrow);

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

  const response = await fetch(`${ENTSOE_API_URL}?${params}`);
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`ENTSO-E API error: ${response.status} - ${errorText}`);
  }

  return await response.text();
}

// Helper to fetch from ENTSO-E
async function fetchFromENTSOE(market, apiToken) {
  const areaCode = MARKET_AREAS[market];
  if (!areaCode) {
    throw new Error(`Invalid market: ${market}`);
  }

  // Get current date and day after tomorrow for full coverage
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const dayAfterTomorrow = new Date(today);
  dayAfterTomorrow.setDate(dayAfterTomorrow.getDate() + 2); // Get 48 hours of data

  // Format dates as required by ENTSO-E (yyyyMMddHHmm)
  const periodStart = formatDateENTSOE(today);
  const periodEnd = formatDateENTSOE(dayAfterTomorrow);

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

  try {
    const response = await fetch(`${ENTSOE_API_URL}?${params}`);
    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`ENTSO-E API error: ${response.status} - ${errorText}`);
    }

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

// Format date for ENTSO-E API
function formatDateENTSOE(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}${month}${day}0000`; // Always start at 00:00
}

// Parse ENTSO-E XML response
function parseENTSOEResponse(xmlString, market) {
  const prices = [];

  // Parse all TimeSeries (API already filters for position 1 and A01)
  const timeSeriesMatches = xmlString.matchAll(/<TimeSeries>([\s\S]*?)<\/TimeSeries>/g);

  for (const timeSeriesMatch of timeSeriesMatches) {
    const timeSeriesContent = timeSeriesMatch[1];

    // Parse periods within this TimeSeries
    const periodMatches = timeSeriesContent.matchAll(/<Period>([\s\S]*?)<\/Period>/g);

    for (const periodMatch of periodMatches) {
      const periodContent = periodMatch[1];

      // Extract time interval start
      const intervalStartMatch = periodContent.match(/<start>(.*?)<\/start>/);
      if (!intervalStartMatch) continue;

      const startTime = new Date(intervalStartMatch[1]);

      // Extract all points in this period
      const pointMatches = periodContent.matchAll(/<Point>([\s\S]*?)<\/Point>/g);

      for (const pointMatch of pointMatches) {
        const pointContent = pointMatch[1];

        // Extract position and price
        const positionMatch = pointContent.match(/<position>(\d+)<\/position>/);
        const priceMatch = pointContent.match(/<price\.amount>([\d.]+)<\/price\.amount>/);

        if (positionMatch && priceMatch) {
          const position = parseInt(positionMatch[1]);
          const price = parseFloat(priceMatch[1]);

          // Calculate actual time for this point (position is hour of day, 1-based)
          const pointTime = new Date(startTime);
          pointTime.setHours(pointTime.getHours() + position - 1);

          const endTime = new Date(pointTime);
          endTime.setHours(endTime.getHours() + 1);

          prices.push({
            startTime: pointTime.toISOString(),
            endTime: endTime.toISOString(),
            price: price / 10.0 // Convert from EUR/MWh to ct/kWh
          });
        }
      }
    }
  }

  // Sort by start time
  prices.sort((a, b) => new Date(a.startTime) - new Date(b.startTime));

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
      if ((url.searchParams.get('debug') === 'xml' || url.searchParams.get('clear') === 'cache') && !adminKey) {
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