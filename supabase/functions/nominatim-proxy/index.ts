// Nearest-place lookup proxy for the My Addresses form ("Use My Current Location").
//
// The app calls this function, not the geocoding provider directly:
//   - One shared response cache, so repeated lookups do not hit the provider again.
//   - The provider key is a Supabase secret (LOCATIONIQ_API_KEY). It never reaches the app.
//   - The provider base URL is configurable (LOCATIONIQ_BASE_URL), so it can be changed
//     without an app release.
//   - Calls to the provider are spaced at least 1.1 s apart within an instance.
//   - Browser permission headers (CORS) are sent, so the web build can call it.
//
// Provider: LocationIQ, free plan. Its free-plan terms require the "Search by
// LocationIQ.com" attribution (shown in the app), allow caching of request and
// response pairs for up to 48 hours (this proxy uses 24), and allow 5,000 requests
// per day and 2 per second (the 1.1 s spacing keeps us under the per-second limit).
//
// Only reverse lookups (a map pin to its nearest place name) reach this function.
// The address search was removed from the app, so the search action is gone too.
// Callers must be signed in (default Supabase verify_jwt), so anonymous callers are
// rejected.
//
// Responses keep the Nominatim-compatible shape the app already parses (display_name),
// so the Flutter service does not change.

const BASE = Deno.env.get("LOCATIONIQ_BASE_URL") ?? "https://us1.locationiq.com/v1";
const API_KEY = Deno.env.get("LOCATIONIQ_API_KEY") ?? "";

const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours (free-plan limit is 48 hours)
const CACHE_MAX_ENTRIES = 500;
const MIN_GAP_MS = 1100;

// Browser permission headers. Without them, a web build running on another
// origin (for example localhost) is blocked before it can read any reply.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type CacheEntry = { body: string; expires: number };
const cache = new Map<string, CacheEntry>();

// Provider calls in this instance run one at a time, at least MIN_GAP_MS apart.
let chain: Promise<unknown> = Promise.resolve();
let lastUpstreamAt = 0;

function throttled<T>(task: () => Promise<T>): Promise<T> {
  const run = chain.then(async () => {
    const wait = MIN_GAP_MS - (Date.now() - lastUpstreamAt);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    lastUpstreamAt = Date.now();
    return task();
  });
  chain = run.catch(() => undefined);
  return run;
}

function cacheGet(key: string): string | null {
  const hit = cache.get(key);
  if (!hit) return null;
  if (hit.expires < Date.now()) {
    cache.delete(key);
    return null;
  }
  return hit.body;
}

function cacheSet(key: string, body: string) {
  if (cache.size >= CACHE_MAX_ENTRIES) {
    // Maps keep insertion order, so the first key is the oldest entry.
    cache.delete(cache.keys().next().value as string);
  }
  cache.set(key, { body, expires: Date.now() + CACHE_TTL_MS });
}

function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

type Input = { action: string; lat?: number; lon?: number };

function buildRequest(
  input: Input,
): { key: string; url: string } | { error: string } {
  if (input.action === "reverse") {
    const lat = Number(input.lat);
    const lon = Number(input.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) ||
        lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return { error: "Coordinates are out of range." };
    }
    // Five decimals is about 1 metre: nearby taps share one cache entry.
    const key = `reverse:${lat.toFixed(5)},${lon.toFixed(5)}`;
    const params = new URLSearchParams({
      key: API_KEY,
      format: "json",
      lat: lat.toFixed(5),
      lon: lon.toFixed(5),
    });
    return { key, url: `${BASE}/reverse?${params}` };
  }
  return { error: "Unknown action." };
}

Deno.serve(async (req) => {
  // Browser permission check, sent before the real request. Answer it first.
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json(405, { error: "POST only." });
  }
  if (!API_KEY) {
    // Configuration error, reported without any secret value.
    return json(500, { error: "Address lookup is not configured." });
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return json(400, { error: "Body must be JSON." });
  }

  const built = buildRequest(input);
  if ("error" in built) return json(400, { error: built.error });

  const cached = cacheGet(built.key);
  if (cached !== null) {
    return new Response(cached, {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json", "X-Cache": "HIT" },
    });
  }

  try {
    const body = await throttled(async () => {
      const res = await fetch(built.url);
      if (!res.ok) throw new Error(`Provider responded ${res.status}`);
      return res.text();
    });
    cacheSet(built.key, body);
    return new Response(body, {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json", "X-Cache": "MISS" },
    });
  } catch (err) {
    // The message names the status only; it never contains the request URL or the key.
    return json(502, {
      error: err instanceof Error ? err.message : "Provider request failed.",
    });
  }
});
