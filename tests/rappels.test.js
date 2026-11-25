// Tests de la fonction serveur « rappels » (partie JavaScript simple) : chiffrement Web Push (RFC 8291),
// jeton VAPID (RFC 8292), choix des téléphones. Le déchiffrement du test est écrit à part, avec node:crypto.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const nc = require('node:crypto');

const src = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'rappels', 'index.ts'), 'utf8');
const aides = src.slice(src.indexOf('// DEBUT-AIDES'), src.indexOf('// FIN-AIDES'));
const A = new Function(aides + '; return { b64uEnc, b64uDec, creerClesVapid, jetonVapid, chiffrer, destinataires, contenu, dureeVie, preparerEnvoi, egal };')();

// Téléphone imité : clé ECDH P-256 et secret de 16 octets, comme un navigateur.
function fauxTelephone() {
  const ecdh = nc.createECDH('prime256v1'); ecdh.generateKeys();
  const auth = nc.randomBytes(16);
  return { ecdh, auth, p256dh: A.b64uEnc(ecdh.getPublicKey()), authB64: A.b64uEnc(auth) };
}
// Déchiffrement côté téléphone (RFC 8291 / RFC 8188), indépendant du code testé.
function dechiffrer(corps, tel) {
  const b = Buffer.from(corps);
  const sel = b.subarray(0, 16), rs = b.readUInt32BE(16), idlen = b[20], asPub = b.subarray(21, 21 + idlen), chiffre = b.subarray(21 + idlen);
  assert.equal(rs, 4096); assert.equal(idlen, 65);
  const partage = tel.ecdh.computeSecret(asPub);
  const info = Buffer.concat([Buffer.from('WebPush: info\0'), tel.ecdh.getPublicKey(), asPub]);
  const ikm = Buffer.from(nc.hkdfSync('sha256', partage, tel.auth, info, 32));
  const cek = Buffer.from(nc.hkdfSync('sha256', ikm, sel, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(nc.hkdfSync('sha256', ikm, sel, Buffer.from('Content-Encoding: nonce\0'), 12));
  const d = nc.createDecipheriv('aes-128-gcm', cek, nonce);
  d.setAuthTag(chiffre.subarray(chiffre.length - 16));
  const clair = Buffer.concat([d.update(chiffre.subarray(0, chiffre.length - 16)), d.final()]);
  assert.equal(clair[clair.length - 1], 2, 'délimiteur du dernier bloc');
  return clair.subarray(0, clair.length - 1).toString('utf8');
}

test('base64url : aller-retour sans « = »', () => {
  for (const n of [0, 1, 2, 3, 16, 65]) {
    const o = nc.randomBytes(n), t = A.b64uEnc(o);
    assert.ok(!/[=+/]/.test(t));
    assert.deepEqual(Buffer.from(A.b64uDec(t)), o);
  }
});

test('le message chiffré se déchiffre sur le téléphone (accents compris)', async () => {
  const tel = fauxTelephone();
  const texte = JSON.stringify({ titre: 'LEAGUE UV — match aujourd’hui', texte: 'Début à 16 h 05 · carte Canal d’Akh · salle ouverte à 15 h 45.' });
  const corps = await A.chiffrer(texte, tel.p256dh, tel.authB64);
  assert.equal(dechiffrer(corps, tel), texte);
  // Deux envois du même message ne se ressemblent pas (sel et clé éphémère au hasard).
  const corps2 = await A.chiffrer(texte, tel.p256dh, tel.authB64);
  assert.notDeepEqual(Buffer.from(corps), Buffer.from(corps2));
});

test('clé des notifications : publique de 65 octets, jeton VAPID ES256 vérifiable', async () => {
  const cles = await A.creerClesVapid();
  const pub = Buffer.from(A.b64uDec(cles.publique));
  assert.equal(pub.length, 65); assert.equal(pub[0], 4);
  assert.match(cles.publique, /^[A-Za-z0-9_-]{80,100}$/); // format accepté par rappels_enregistrer_cles
  const maint = 1795000000;
  const jwt = await A.jetonVapid('https://fcm.googleapis.com/fcm/send/abc', 'https://zoomdaddykatana-sudo.github.io/dfmm-site/', cles.prive, maint);
  const [h, c, s] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(A.b64uDec(h)).toString()), { typ: 'JWT', alg: 'ES256' });
  const claims = JSON.parse(Buffer.from(A.b64uDec(c)).toString());
  assert.equal(claims.aud, 'https://fcm.googleapis.com');
  assert.equal(claims.exp, maint + 3600);
  assert.match(claims.sub, /^https:\/\//);
  const cle = nc.createPublicKey({ key: { kty: 'EC', crv: 'P-256', x: A.b64uEnc(pub.subarray(1, 33)), y: A.b64uEnc(pub.subarray(33)) }, format: 'jwk' });
  assert.ok(nc.verify('sha256', Buffer.from(h + '.' + c), { key: cle, dsaEncoding: 'ieee-p1363' }, Buffer.from(A.b64uDec(s))));
});

test('choix des téléphones : tous, code (actifs non suspendus), essai (une personne)', () => {
  const abos = [{ id: 1, user_id: 'a', code: true }, { id: 2, user_id: 'b', code: false }, { id: 3, user_id: 'k', code: true }];
  assert.deepEqual(A.destinataires({ cible: 'tous' }, abos).map(x => x.id), [1, 2, 3]);
  assert.deepEqual(A.destinataires({ cible: 'code' }, abos).map(x => x.id), [1, 3]);
  assert.deepEqual(A.destinataires({ cible: 'essai', user_id: 'b' }, abos).map(x => x.id), [2]);
  assert.deepEqual(A.destinataires({ cible: 'autre' }, abos), []);
});

test('requête d’envoi : en-têtes Web Push, durée de vie, rien si le rappel est périmé', async () => {
  const tel = fauxTelephone(), cles = await A.creerClesVapid(), maint = Date.UTC(2026, 10, 25, 12, 0, 0);
  const msg = { cle: 'j1:avant', cible: 'tous', titre: 'LEAGUE UV — match à 16 h 05', texte: 'Carte Ascension', tag: 'j1', expire: new Date(maint + 600000).toISOString() };
  const p = await A.preparerEnvoi({ endpoint: 'https://web.push.apple.com/QWERTY', p256dh: tel.p256dh, auth: tel.authB64 }, msg, cles, 'https://exemple.test/', maint);
  assert.equal(p.url, 'https://web.push.apple.com/QWERTY');
  assert.equal(p.init.headers.TTL, '600');
  assert.equal(p.init.headers['Content-Encoding'], 'aes128gcm');
  assert.equal(p.init.headers.Urgency, 'high');
  assert.match(p.init.headers.Authorization, new RegExp('^vapid t=[^.]+\\.[^.]+\\.[^.]+, k=' + cles.publique + '$'));
  const recu = JSON.parse(dechiffrer(p.init.body, tel));
  assert.deepEqual(recu, { titre: msg.titre, texte: msg.texte, tag: 'j1', url: './#evenements' });
  assert.equal(await A.preparerEnvoi({ endpoint: 'https://x.test/1', p256dh: tel.p256dh, auth: tel.authB64 }, Object.assign({}, msg, { expire: new Date(maint - 1).toISOString() }), cles, 's', maint), null);
});

test('mot de passe base ↔ fonction : comparaison exacte', () => {
  assert.ok(A.egal('abc123', 'abc123'));
  assert.ok(!A.egal('abc123', 'abc124'));
  assert.ok(!A.egal('', ''));
  assert.ok(!A.egal('abc', 'abcd'));
  assert.ok(!A.egal(undefined, 'abc'));
});

// ---------- Agenda du téléphone (js/regles.js) ----------
const L = require('../js/regles.js');
const JOURS = [
  { id: 1, debut: '2026-11-25T13:05:00Z', carte: 'Ascension', statut: 'prevu' },
  { id: 2, debut: '2026-11-28T13:05:00Z', carte: 'Ligne de tranchées', statut: 'annule' },
  { id: 3, debut: '2026-12-02T13:05:00Z', carte: 'Canal d’Akh, côté sud', statut: 'prevu' },
  { id: 4, debut: '2026-11-21T13:05:00Z', carte: 'Craqué', statut: 'prevu' }
];
const OPTS = { maintenant: '2026-11-25T08:00:00Z', avantMin: 35, heureMatin: '10:00', ouvertureMin: 20, plageMin: 60, url: 'https://exemple.test/dfmm-site/' };

test('agenda : seulement les dates prévues à venir, deux alarmes (10 h et 15 h 30)', () => {
  const ics = L.agendaIcs(JOURS, OPTS);
  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n') && ics.endsWith('END:VCALENDAR\r\n'));
  assert.equal((ics.match(/BEGIN:VEVENT/g) || []).length, 2);
  assert.match(ics, /UID:jour-1@dfmm-league-uv\r\n/);
  assert.match(ics, /UID:jour-3@dfmm-league-uv\r\n/);
  assert.doesNotMatch(ics, /jour-2@|jour-4@/);
  assert.match(ics, /DTSTART:20261125T130500Z\r\nDTEND:20261125T140500Z/);
  assert.equal((ics.match(/TRIGGER:-PT365M/g) || []).length, 2); // 16 h 05 − 10 h 00
  assert.equal((ics.match(/TRIGGER:-PT35M/g) || []).length, 2);  // 15 h 30
});
test('agenda : virgules échappées, lignes de 75 octets au plus, jamais de code de salle', () => {
  const ics = L.agendaIcs(JOURS, OPTS);
  assert.match(ics, /SUMMARY:LEAGUE UV — match \(carte Canal d’Akh\\, côté sud\)/);
  ics.split('\r\n').forEach(l => assert.ok(Buffer.byteLength(l) <= 75, l));
  const deplie = ics.replace(/\r\n /g, '');
  assert.match(deplie, /salle ouverte à 15 h 45/);
  assert.doesNotMatch(deplie.toLowerCase(), /mot de passe/);
});
test('agenda : pas d’alarme du matin si le match commence avant le rappel d’avant', () => {
  assert.equal(L.minutesMatin('2026-11-25T13:05:00Z', '10:00'), 365);
  assert.equal(L.minutesMatin('2026-11-25T06:20:00Z', '10:00'), 0); // 9 h 20 à Madagascar
  const ics = L.agendaIcs([{ id: 5, debut: '2026-11-26T07:20:00Z', carte: 'Faille', statut: 'prevu' }], OPTS); // 10 h 20
  assert.doesNotMatch(ics, /TRIGGER:-PT20M/);
  assert.equal((ics.match(/BEGIN:VALARM/g) || []).length, 1);
});
test('lien Google Agenda : heure et carte', () => {
  const u = new URL(L.lienGoogleAgenda(JOURS[0], OPTS));
  assert.equal(u.searchParams.get('action'), 'TEMPLATE');
  assert.equal(u.searchParams.get('dates'), '20261125T130500Z/20261125T140500Z');
  assert.equal(u.searchParams.get('text'), 'LEAGUE UV — match (carte Ascension)');
});
