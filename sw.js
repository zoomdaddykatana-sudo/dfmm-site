/* LEAGUE UV — DFMM · service worker (application installable).
   Règle simple et sûre : on demande toujours d'abord au réseau ; la copie
   n'est utilisée que hors connexion. Seuls les fichiers du site sont gardés :
   jamais les échanges avec Supabase ni les données. */
const VERSION = 'dfmm-rappels-1';
const FICHIERS = ['./', './index.html', './config.js', './js/regles.js', './manifest.webmanifest',
  './icons/icone-192.png', './icons/icone-512.png', './icons/apple-touch-icon.png', './icons/badge-96.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(FICHIERS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(cles => Promise.all(cles.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(fetch(req).then(rep => {
    if (rep.ok) { const copie = rep.clone(); caches.open(VERSION).then(c => c.put(req, copie)); }
    return rep;
  }).catch(() => caches.match(req).then(r => r || caches.match('./index.html'))));
});

/* Rappels (migration 0020) : notification envoyée par la fonction « rappels », même site fermé.
   Le message ne contient jamais le code ni le mot de passe de la salle. */
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { texte: e.data ? e.data.text() : '' }; }
  const titre = d.titre || 'LEAGUE UV';
  e.waitUntil(self.registration.showNotification(titre, {
    body: d.texte || '', tag: d.tag || 'league-uv', renotify: true, lang: 'fr',
    icon: './icons/icone-192.png', badge: './icons/badge-96.png', data: { url: d.url || './#evenements' }
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const cible = new URL((e.notification.data && e.notification.data.url) || './#evenements', self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(fen => {
    for (const f of fen) if (f.url.startsWith(self.registration.scope) && 'focus' in f) { f.navigate(cible).catch(() => {}); return f.focus(); }
    return self.clients.openWindow(cible);
  }));
});
