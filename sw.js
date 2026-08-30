// Minimal service worker for Inno Chem Bangladesh ERP.
// Intentionally does NOT cache anything — this app talks to a live Supabase
// backend, and caching responses here could serve stale business data.
// Its only job is to exist as a real, fetchable file so Android/Chrome can
// install this as a proper app (WebAPK) instead of getting stuck on a
// blank splash screen.

self.addEventListener('install', function(event) {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', function(event) {
  // Always just pass through to the network — no caching, no interception.
});
