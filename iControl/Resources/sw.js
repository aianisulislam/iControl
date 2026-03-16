self.addEventListener('install', () => {
  self.skipWaiting(); // activate immediately
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim()); // take control of open pages
});

// Pass-through network requests (no caching)
self.addEventListener('fetch', () => {
  // intentionally empty
});