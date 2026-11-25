// LEAGUE UV — DFMM · Fonction « rappels » (migration 0020)
// Appelée chaque minute par la base (pg_cron + pg_net, fonction rappels_reveil) quand un rappel est à envoyer.
// Elle prend les rappels (rappels_prendre), les chiffre pour chaque téléphone inscrit et les envoie au service de
// notification du téléphone (Google, Apple, Mozilla), puis note le résultat (rappels_resultats).
// Sécurité : « Verify JWT » DÉSACTIVÉ (la base n'envoie pas de jeton) ; la fonction n'accepte que l'appel qui porte
// le mot de passe tiré au hasard par la migration (en-tête x-rappels-cle), rangé dans le schéma privé.
// La clé des notifications (VAPID) est créée ici au premier appel et rangée dans le schéma privé : aucun secret à placer.
// Le code et le mot de passe de la salle ne sont jamais envoyés (choix 3a de Katana du 25/11/2026).
import { createClient } from 'npm:@supabase/supabase-js@2.117.3';

// DEBUT-AIDES (JavaScript simple, testé automatiquement par tests/rappels.test.js ; Web Push : RFC 8291 et RFC 8292)
const ENC = new TextEncoder();
function b64uEnc(octets) {
  let s = '';
  for (const o of octets) s += String.fromCharCode(o);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64uDec(texte) {
  let s = String(texte).replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  while (s.length % 4) s += '=';
  return Uint8Array.from(atob(s), c => c.charCodeAt(0));
}
function joindre(...morceaux) {
  const r = new Uint8Array(morceaux.reduce((n, m) => n + m.length, 0));
  let i = 0;
  for (const m of morceaux) { r.set(m, i); i += m.length; }
  return r;
}
async function hkdf(sel, ikm, info, n) {
  const k = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: sel, info }, k, n * 8));
}
// Nouvelle clé des notifications : publique (65 octets, base64url) et privée (JWK en texte).
async function creerClesVapid() {
  const p = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  return { publique: b64uEnc(new Uint8Array(await crypto.subtle.exportKey('raw', p.publicKey))),
           prive: JSON.stringify(await crypto.subtle.exportKey('jwk', p.privateKey)) };
}
// Jeton VAPID (JWT ES256) pour le service de notification de l'adresse « endpoint ». Valable 1 h.
async function jetonVapid(endpoint, sujet, priveJwk, maintenantS) {
  const aud = new URL(endpoint).origin;
  const h = b64uEnc(ENC.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const c = b64uEnc(ENC.encode(JSON.stringify({ aud, exp: maintenantS + 3600, sub: sujet })));
  const jwk = Object.assign({}, typeof priveJwk === 'string' ? JSON.parse(priveJwk) : priveJwk);
  delete jwk.key_ops; delete jwk.ext;
  const k = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, k, ENC.encode(h + '.' + c)));
  return h + '.' + c + '.' + b64uEnc(sig);
}
// Chiffrement du message pour un téléphone (aes128gcm). opt.sel et opt.ephemere : seulement pour les tests.
async function chiffrer(texte, p256dh, auth, opt = {}) {
  const uaPub = b64uDec(p256dh), secret = b64uDec(auth);
  const sel = opt.sel || crypto.getRandomValues(new Uint8Array(16));
  const eph = opt.ephemere || await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPub = new Uint8Array(await crypto.subtle.exportKey('raw', eph.publicKey));
  const uaCle = await crypto.subtle.importKey('raw', uaPub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const partage = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaCle }, eph.privateKey, 256));
  const ikm = await hkdf(secret, partage, joindre(ENC.encode('WebPush: info\0'), uaPub, asPub), 32);
  const cek = await hkdf(sel, ikm, ENC.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(sel, ikm, ENC.encode('Content-Encoding: nonce\0'), 12);
  const k = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const chiffre = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, k, joindre(ENC.encode(texte), new Uint8Array([2]))));
  const entete = new Uint8Array(21 + asPub.length);
  entete.set(sel, 0); new DataView(entete.buffer).setUint32(16, 4096); entete[20] = asPub.length; entete.set(asPub, 21);
  return joindre(entete, chiffre);
}
// Téléphones qui reçoivent un message : « tous » (membres actifs et Katana), « code » (actifs non suspendus et Katana),
// « essai » (les téléphones de la personne qui a demandé l'essai).
function destinataires(message, abonnements) {
  return (abonnements || []).filter(a => message.cible === 'essai' ? a.user_id === message.user_id
    : message.cible === 'code' ? a.code === true : message.cible === 'tous');
}
// Contenu affiché par le téléphone (lu par sw.js). Jamais de code ni de mot de passe de salle.
function contenu(message) {
  return JSON.stringify({ titre: message.titre, texte: message.texte, tag: message.tag || 'league-uv', url: './#evenements' });
}
// Durée de vie chez le service de notification : jusqu'à l'heure où le rappel ne sert plus (0 = trop tard).
function dureeVie(message, maintenantMs) {
  return Math.max(0, Math.floor((new Date(message.expire).getTime() - maintenantMs) / 1000));
}
// Requête complète vers le service de notification d'un téléphone.
async function preparerEnvoi(abonnement, message, cles, sujet, maintenantMs) {
  const ttl = dureeVie(message, maintenantMs);
  if (ttl <= 0) return null;
  const jeton = await jetonVapid(abonnement.endpoint, sujet, cles.prive, Math.floor(maintenantMs / 1000));
  return { url: abonnement.endpoint, init: { method: 'POST', body: await chiffrer(contenu(message), abonnement.p256dh, abonnement.auth),
    headers: { Authorization: 'vapid t=' + jeton + ', k=' + cles.publique, 'Content-Encoding': 'aes128gcm',
               'Content-Type': 'application/octet-stream', TTL: String(ttl), Urgency: 'high' } } };
}
function egal(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length || !a) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
// FIN-AIDES

const reponse = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { 'Content-Type': 'application/json; charset=utf-8' } });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reponse({ erreur: 'POST seulement' }, 405);
  const sb = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', { auth: { persistSession: false } });
  const { data: conf, error: e1 } = await sb.rpc('rappels_config');
  if (e1 || !conf) { console.error('rappels_config :', e1?.message); return reponse({ erreur: 'réglages illisibles' }, 500); }
  if (!egal(req.headers.get('x-rappels-cle') ?? '', conf.secret)) return reponse({ erreur: 'refusé' }, 401);

  let cles = conf.vapid_public ? { publique: conf.vapid_public, prive: conf.vapid_prive } : null;
  if (!cles) {
    const n = await creerClesVapid();
    const { data: c2, error: e2 } = await sb.rpc('rappels_enregistrer_cles', { p_publique: n.publique, p_prive: n.prive });
    if (e2 || !c2?.vapid_public) { console.error('rappels_enregistrer_cles :', e2?.message); return reponse({ erreur: 'clé non enregistrée' }, 500); }
    cles = { publique: c2.vapid_public, prive: c2.vapid_prive };
    console.log('Clé des notifications créée.');
  }

  const { data: lotR, error: e3 } = await sb.rpc('rappels_prendre');
  if (e3) { console.error('rappels_prendre :', e3.message); return reponse({ erreur: 'rappels illisibles' }, 500); }
  const messages = lotR?.messages ?? [], abonnements = lotR?.abonnements ?? [];
  const taches: { id: number; cle: string; prep: Promise<{ url: string; init: RequestInit } | null> }[] = [];
  const maintenant = Date.now();
  for (const m of messages) for (const a of destinataires(m, abonnements)) {
    taches.push({ id: a.id, cle: m.cle, prep: preparerEnvoi(a, m, cles, conf.sujet, maintenant) });
  }
  const envois: { id: number; http: number | null }[] = [];
  const parCle: Record<string, number> = {};
  messages.forEach((m: { cle: string }) => { parCle[m.cle] = 0; });
  // 10 envois à la fois, 10 s au plus chacun.
  for (let i = 0; i < taches.length; i += 10) {
    await Promise.all(taches.slice(i, i + 10).map(async t => {
      let http: number | null = null;
      try {
        const p = await t.prep;
        if (!p) return;
        const ctrl = new AbortController();
        const minuteur = setTimeout(() => ctrl.abort(), 10000);
        try { const r = await fetch(p.url, { ...p.init, signal: ctrl.signal }); http = r.status; await r.body?.cancel(); }
        finally { clearTimeout(minuteur); }
      } catch (_e) { http = null; }
      envois.push({ id: t.id, http });
      if (http !== null && http >= 200 && http < 300) parCle[t.cle] += 1;
    }));
  }
  const { error: e4 } = await sb.rpc('rappels_resultats', { p: { envois, cles: parCle } });
  if (e4) console.error('rappels_resultats :', e4.message);
  const ok = envois.filter(e => e.http !== null && e.http >= 200 && e.http < 300).length;
  console.log('Rappels :', messages.length, 'message(s),', envois.length, 'envoi(s),', ok, 'réussi(s).');
  return reponse({ messages: messages.length, envois: envois.length, reussis: ok });
});
