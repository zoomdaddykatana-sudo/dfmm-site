/* LEAGUE UV — DFMM · service worker (application installable).
   Règle simple et sûre : on demande toujours d'abord au réseau ; la copie
   n'est utilisée que hors connexion. Seuls les fichiers du site sont gardés :
   jamais les échanges avec Supabase ni les données. */
const VERSION = 'dfmm-textes-3';
const FICHIERS = ['./', './index.html', './config.js', './js/regles.js', './manifest.webmanifest',
  './icons/icone-192.png', './icons/icone-512.png', './icons/apple-touch-icon.png'];

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
