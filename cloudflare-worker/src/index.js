/**
 * CloudFlare Worker for SpotWatt
 * Proxy for aWATTar API (will switch to ENTSO-E later)
 */

// aWATTar API endpoints
const AWATTAR_ENDPOINTS = {
  AT: 'https://api.awattar.at/v1/marketdata',
  DE: 'https://api.awattar.de/v1/marketdata'
};

// Helper to fetch from aWATTar
async function fetchFromAwattar(market) {
  const endpoint = AWATTAR_ENDPOINTS[market];
  if (!endpoint) {
    throw new Error(`Invalid market: ${market}`);
  }

  try {
    const response = await fetch(endpoint);
    if (!response.ok) {
      throw new Error(`aWATTar API error: ${response.status}`);
    }

    const data = await response.json();

    // Transform aWATTar format to our format
    return {
      lastUpdate: new Date().toISOString(),
      market: market,
      prices: data.data.map(item => ({
        startTime: new Date(item.start_timestamp).toISOString(),
        endTime: new Date(item.end_timestamp).toISOString(),
        price: item.marketprice / 10.0 // Convert to ct/kWh
      }))
    };
  } catch (error) {
    console.error(`Error fetching from aWATTar ${market}:`, error);
    throw error;
  }
}

export default {
  async fetch(request, env, ctx) {
    // CORS headers
    const headers = {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Cache-Control': 'public, max-age=3600' // Cache for 1 hour
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers });
    }

    const url = new URL(request.url);
    const market = url.searchParams.get('market') || 'AT';

    // Validate market parameter
    if (!['AT', 'DE'].includes(market)) {
      return new Response(
        JSON.stringify({ error: 'Invalid market. Use AT or DE.' }),
        { status: 400, headers }
      );
    }

    try {
      // Try to get from cache first (when KV is set up)
      // const cached = await env.PRICE_CACHE?.get(`prices_${market}`);
      // if (cached) {
      //   const cachedData = JSON.parse(cached);
      //   // Check if cache is still fresh (less than 1 hour old)
      //   const cacheAge = Date.now() - new Date(cachedData.lastUpdate).getTime();
      //   if (cacheAge < 3600000) { // 1 hour
      //     return new Response(cached, { headers });
      //   }
      // }

      // Fetch fresh data from aWATTar
      const data = await fetchFromAwattar(market);

      // Cache the data (when KV is set up)
      // await env.PRICE_CACHE?.put(`prices_${market}`, JSON.stringify(data));

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

  // Scheduled handler - runs daily at 14:00 UTC
  async scheduled(event, env, ctx) {
    console.log('Scheduled task running at', new Date().toISOString());

    // This will fetch from ENTSO-E and update cache
    await updatePricesFromENTSOE(env);
  }
};

async function updatePricesFromENTSOE(env) {
  // For now, fetch from aWATTar and cache
  // Later: Replace with ENTSO-E implementation

  try {
    // Fetch both markets
    const [atData, deData] = await Promise.all([
      fetchFromAwattar('AT'),
      fetchFromAwattar('DE')
    ]);

    // Cache the data (when KV is set up)
    // await env.PRICE_CACHE?.put('prices_AT', JSON.stringify(atData));
    // await env.PRICE_CACHE?.put('prices_DE', JSON.stringify(deData));

    console.log('Successfully updated prices for AT and DE');
  } catch (error) {
    console.error('Error updating prices:', error);
  }
}