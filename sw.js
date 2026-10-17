// Service worker for Inno Chem Bangladesh ERP.
// Caches the app shell (network-first) so the app can OPEN without internet.
// Supabase API calls are never intercepted or cached — business data always
// comes live from the server (offline data handling lives in the app itself).
const CACHE = 'innochem-shell-v2';

self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE).then(function(c){ return c.addAll(['./', 'index.html', 'manifest.json']).catch(function(){}); })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.filter(function(k){ return k !== CACHE; }).map(function(k){ return caches.delete(k); }));
    }).then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function(event) {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
  if (url.hostname.endsWith('supabase.co')) return; // live data: never touch

  event.respondWith(
    fetch(req).then(function(res){
      if (res && (res.ok || res.type === 'opaque')) {
        const copy = res.clone();
        caches.open(CACHE).then(function(c){ c.put(req, copy); }).catch(function(){});
      }
      return res;
    }).catch(function(){
      return caches.match(req, { ignoreSearch: true }).then(function(hit){
        if (hit) return hit;
        if (req.mode === 'navigate') return caches.match('index.html').then(function(r){ return r || caches.match('./'); });
        return Response.error();
      });
    })
  );
});
