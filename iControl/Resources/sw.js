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

  const { protocol } = new URL(event.request.url);
  if (protocol !== 'http:' && protocol !== 'https:') return;

  const isNavigation = event.request.mode === 'navigate';

  event.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(event.request);

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
              await cache.put(event.request, newResponse.clone());
              const clients = await self.clients.matchAll({ type: 'window' });
              clients.forEach((c) => c.postMessage({ type: 'UPDATE_AVAILABLE' }));
            }

            return newResponse;
          }

          await cache.put(event.request, response.clone());
          return response;
        })
        .catch(() => null);

      // Serve cache immediately; fall through to network if no cache yet.
      return cached ?? await networkPromise;
    })
  );
});
