const CACHE = 'icontrol-cache';
const PRECACHE = [
  '/',
  '/manifest.json',
  '/favicon.svg',
  '/favicon.ico',
  '/favicon-96x96.png',
  '/apple-touch-icon.png',
  '/web-app-manifest-192x192.png',
  '/web-app-manifest-512x512.png',
];

const OFFLINE_HTML = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>iControl</title><style>*{box-sizing:border-box;margin:0;padding:0}body{background:#0b1220;color:#e5e7eb;font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:2rem}.wrap{display:flex;flex-direction:column;align-items:center;gap:1rem}.icon{font-size:2.5rem}.title{font-size:1.05rem;font-weight:500}.sub{color:#c1cbda;font-size:.85rem;line-height:1.6;max-width:260px}</style></head><body><div class="wrap"><div class="icon">📡</div><p class="title">Server not running</p><p class="sub">Open iControl on your Mac, then tap to retry.</p><button onclick="location.reload()" style="margin-top:.5rem;padding:.55rem 1.4rem;background:#18223b;color:#e5e7eb;border:1px solid rgba(71,85,105,.5);border-radius:.75rem;font:inherit;font-size:.85rem;cursor:pointer">Retry</button></div></body></html>`;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(PRECACHE))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
      )
      .then(() => self.clients.claim())
  );
});

function extractVersion(html) {
  const match = html.match(/<meta[^>]+name="version"[^>]+content="([^"]+)"/);
  return match ? match[1] : null;
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;

  const isNavigation = event.request.mode === 'navigate';
  // Strip query params from navigation cache keys so /?token=XXXX hits the cached /
  const cacheKey = isNavigation ? url.origin + '/' : event.request;

  event.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(cacheKey);

      const networkPromise = fetch(event.request)
        .then(async (response) => {
          if (!response.ok) return response;

          if (isNavigation && cached) {
            const [newText, oldText] = await Promise.all([
              response.text(),
              cached.clone().text(),
            ]);

            const newResponse = new Response(newText, {
              status: response.status,
              statusText: response.statusText,
              headers: response.headers,
            });

            if (extractVersion(newText) !== extractVersion(oldText)) {
              await cache.put(cacheKey, newResponse.clone());
              const clients = await self.clients.matchAll({ type: 'window' });
              clients.forEach((c) => c.postMessage({ type: 'UPDATE_AVAILABLE' }));
            }

            return newResponse;
          }

          await cache.put(cacheKey, response.clone());
          return response;
        })
        .catch(() => null);

      if (cached) return cached;

      const fromNetwork = await networkPromise;
      if (fromNetwork) return fromNetwork;

      // Both cache and network failed — never return null to the browser
      if (isNavigation) {
        return new Response(OFFLINE_HTML, {
          status: 200,
          headers: { 'Content-Type': 'text/html; charset=utf-8' },
        });
      }
      return new Response('', { status: 503 });
    })
  );
});
