// Said Nazzal shop – offline support. Pages: network first; photos and libraries: cache first.
const V = 'sn-v2';
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(
  caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())
));
self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== 'GET') return;
  if (u.hostname.endsWith('supabase.co')) return;            // live data and logins: never cached
  const isPage = r.mode === 'navigate' || u.pathname.endsWith('.html') || u.pathname.endsWith('config.js');
  if (isPage) {
    e.respondWith(fetch(r).then(res => { const c = res.clone(); caches.open(V).then(x => x.put(r, c)); return res; })
      .catch(() => caches.match(r)));
    return;
  }
  const cacheFirst = u.pathname.startsWith('/photos/') || u.pathname.startsWith('/icons/') ||
    u.hostname === 'cdn.jsdelivr.net' || u.hostname.endsWith('gstatic.com') || u.hostname === 'fonts.googleapis.com';
  if (cacheFirst) {
    e.respondWith(caches.match(r).then(hit => hit || fetch(r).then(res => {
      if (res.ok || res.type === 'opaque') { const c = res.clone(); caches.open(V).then(x => x.put(r, c)); }
      return res;
    })));
  }
});
