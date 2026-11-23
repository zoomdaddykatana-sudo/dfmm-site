// LEAGUE UV — DFMM · Fonction « inscription »
// Reçoit le formulaire d'inscription (données + capture du profil) et crée :
// le compte de connexion (sans e-mail de confirmation), la candidature en attente,
// le compte de jeu et la capture rangée dans un espace privé.
// N'accepte rien si le paramètre « inscriptions_ouvertes » est à « non ».
// Vérifications automatiques (choix de Katana du 22/11/2026) : UID et pseudo lus chez volsever
// (UID inconnu = refus si « refus_uid_introuvable » est à « oui ») ; domaine de l'e-mail existant,
// qui reçoit des e-mails, et pas jetable ; code Messenger donné au joueur.
// Limites (migration 0015) : inscriptions par heure (« inscriptions_max_heure ») et longueur des textes.
// Limite par connexion (migration 0018, choix de Katana du 23/11/2026) : « inscriptions_max_heure_ip » par adresse IP ;
// seule une empreinte (SHA-256) de l'adresse part dans la base, jamais l'adresse elle-même.
import { createClient } from 'npm:@supabase/supabase-js@2.117.3';

// DEBUT-AIDES (JavaScript simple, testé automatiquement par tests/inscription.test.js)
const PROVINCES = ['Antananarivo', 'Antsiranana', 'Fianarantsoa', 'Mahajanga', 'Toamasina', 'Toliara'];
function normEmail(e) { return String(e || '').trim().toLowerCase(); }
// Un même profil Facebook peut s'écrire de plusieurs façons : on garde une forme unique.
function normFacebook(lien) {
  let s = String(lien || '').trim().toLowerCase();
  s = s.replace(/^https?:\/\//, '').replace(/^(www|m|web|mbasic)\./, '').replace(/^fb\.com/, 'facebook.com');
  const id = s.match(/^facebook\.com\/profile\.php\?(?:.*&)?id=(\d+)/);
  if (id) return 'facebook.com/profile.php?id=' + id[1];
  s = s.split(/[?#]/)[0].replace(/\/+$/, '');
  return s;
}
// Date qui existe au calendrier (pas de 31 février), après 1900 et avant aujourd'hui.
function dateReelle(t) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(t)) return false;
  const x = new Date(t + 'T00:00:00Z');
  return !isNaN(x.getTime()) && x.toISOString().slice(0, 10) === t && t >= '1900-01-01' && t < new Date().toISOString().slice(0, 10);
}
// Longueurs maximales (décision 3 du 22/11/2026, réglables : longueur_max_court et longueur_max_long).
const CHAMPS_COURTS = { nom_reel: 'nom réel', nom_gamer: 'nom de gamer', email: 'e-mail', pseudo: 'pseudo', clan: 'clan', pays: 'pays' };
const CHAMPS_LONGS = { facebook: 'lien Facebook' };
function verifierDonnees(d, lim) {
  const err = [];
  const txt = k => String(d[k] == null ? '' : d[k]).trim();
  const max = { court: Number(lim && lim.court) || 100, long: Number(lim && lim.long) || 2000 };
  ['nom_reel', 'nom_gamer', 'email', 'date_naissance', 'genre', 'facebook', 'pseudo', 'uid', 'residence', 'comprend_mg', 'parle_mg'].forEach(k => { if (!txt(k)) err.push('Champ manquant : ' + k + '.'); });
  [[CHAMPS_COURTS, max.court], [CHAMPS_LONGS, max.long]].forEach(([champs, n]) => Object.keys(champs).forEach(k => {
    if (txt(k).length > n) err.push('Texte trop long (' + champs[k] + ') : ' + n + ' caractères au plus.');
  }));
  if (txt('email') && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(txt('email'))) err.push('Adresse e-mail invalide.');
  if (txt('facebook') && !/^facebook\.com\/[^\s]+$/.test(normFacebook(txt('facebook')))) err.push('Lien Facebook invalide.');
  if (txt('date_naissance') && !dateReelle(txt('date_naissance'))) err.push('Date de naissance invalide.');
  if (txt('uid') && !/^\d{5,20}$/.test(txt('uid'))) err.push('UID invalide : il ne contient que des chiffres (de 5 à 20).');
  if (txt('genre') && ['Homme', 'Femme', 'Préfère ne pas le dire'].indexOf(txt('genre')) < 0) err.push('Genre invalide.');
  if (txt('residence') === 'Madagascar') {
    if (PROVINCES.indexOf(txt('province')) < 0) err.push('Province invalide.');
    if (['Ville principale', 'Périphérie'].indexOf(txt('zone')) < 0) err.push('Zone invalide.');
  } else if (txt('residence') === 'Étranger') {
    if (!txt('pays')) err.push('Pays manquant.');
  } else if (txt('residence')) err.push('Résidence invalide.');
  if (txt('comprend_mg') && txt('comprend_mg') !== 'Oui') err.push('Comprendre le malgache est un critère essentiel.');
  if (txt('parle_mg') && ['Oui', 'Non'].indexOf(txt('parle_mg')) < 0) err.push('Réponse invalide pour « parle le malgache ».');
  ['origine_mg', 'acc_dfmm', 'acc_uv', 'acc_donnees', 'acc_approbation'].forEach(k => { if (d[k] !== true) err.push('Case obligatoire non cochée : ' + k + '.'); });
  if (String(d.mot_de_passe || '').length < 8) err.push('Le mot de passe doit faire 8 caractères au moins.');
  return err;
}

// ----- volsever (même lecture que la fonction « pseudo-volsever ») -----
const ADRESSE_VOLSEVER = 'https://gate.volsever.com/proxy/api/game/delta-force?id=';
function interpreterVolsever(statutHttp, corps) {
  if (corps && corps.status === true && corps.data && typeof corps.data.username === 'string' && corps.data.username !== '') {
    return { resultat: 'trouve', pseudo: corps.data.username };
  }
  if (statutHttp === 404 || (corps && corps.code === 404)) return { resultat: 'introuvable', pseudo: null };
  return { resultat: 'erreur', pseudo: null };
}
function limiteAtteinte(nbJour, nbMinute, maxJour, maxMinute) {
  return !(Number.isFinite(maxJour) && Number.isFinite(maxMinute)) || nbJour >= maxJour || nbMinute >= maxMinute;
}

// ----- E-mail : domaine et adresses jetables -----
function domaineEmail(e) { const s = normEmail(e); return s.slice(s.lastIndexOf('@') + 1); }
// Liste publique (une adresse par ligne, lignes « # » ignorées) → ensemble de domaines.
function lireListeJetables(texte) {
  return new Set(String(texte || '').split(/\r?\n/).map(l => l.trim().toLowerCase()).filter(l => l && l[0] !== '#'));
}
// Le domaine ou l'un de ses parents (« x.yopmail.com » → « yopmail.com ») est dans la liste.
function estJetable(domaine, liste) {
  const parts = String(domaine || '').toLowerCase().split('.');
  for (let i = 0; i < parts.length - 1; i++) if (liste.has(parts.slice(i).join('.'))) return true;
  return false;
}
// Réponse JSON d'un service DNS (« DNS over HTTPS ») pour une recherche MX :
// « ok » (reçoit des e-mails), « sans_mx » (existe mais ne reçoit pas), « inexistant », « erreur » (pas de réponse fiable).
function interpreterMx(corps) {
  if (!corps || typeof corps.Status !== 'number') return 'erreur';
  if (corps.Status === 3) return 'inexistant';
  if (corps.Status !== 0) return 'erreur';
  const mx = (corps.Answer || []).filter(a => a && a.type === 15 && typeof a.data === 'string');
  if (!mx.length) return 'sans_mx';
  // « 0 . » = le domaine déclare ne recevoir aucun e-mail (RFC 7505).
  return mx.some(a => { const h = a.data.trim().split(/\s+/)[1]; return h && h !== '.'; }) ? 'ok' : 'sans_mx';
}
const MESSAGES_EMAIL = {
  inexistant: 'Le domaine de votre adresse e-mail n’existe pas. Vérifiez l’orthographe (par exemple gmail.com).',
  sans_mx: 'Votre adresse e-mail ne peut pas recevoir de messages (domaine sans serveur de messagerie). Utilisez une autre adresse.',
  jetable: 'Les adresses e-mail temporaires (jetables) ne sont pas acceptées. Utilisez votre adresse habituelle.',
};
const MESSAGE_UID_INCONNU = 'Cet UID n’existe pas dans Delta Force. Vérifiez-le sur votre profil de jeu (chiffres seulement), puis réessayez.';
const MESSAGE_TROP_D_INSCRIPTIONS = 'Trop d’inscriptions en ce moment. Réessayez dans une heure. Si le problème continue, écrivez à Katana sur Messenger.';
const MESSAGE_TROP_MEME_CONNEXION = 'Trop d’inscriptions depuis cette connexion internet en une heure. Réessayez dans une heure, ou depuis une autre connexion (Wi-Fi ou données mobiles). Si le problème continue, écrivez à Katana sur Messenger.';

// ----- Adresse IP du joueur, lue dans les en-têtes posés par l'hébergeur -----
// lire(nom) renvoie la valeur d'un en-tête. Ordre : cf-connecting-ip, x-real-ip, puis la 1re adresse de x-forwarded-for.
// Adresse absente, illisible ou interne (réseau privé, machine locale) : '' (seule la limite commune s'applique alors,
// pour ne jamais mettre tous les joueurs dans le même compteur).
function adresseClient(lire) {
  const brut = [lire('cf-connecting-ip'), lire('x-real-ip'), String(lire('x-forwarded-for') || '').split(',')[0]]
    .map(v => String(v || '').trim()).find(v => v !== '') || '';
  const ip = brut.toLowerCase().replace(/^::ffff:(?=\d+\.\d+\.\d+\.\d+$)/, '');
  const v4 = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (v4) {
    const n = v4.slice(1).map(Number);
    if (n.some(x => x > 255)) return '';
    if (n[0] === 10 || n[0] === 127 || n[0] === 0 || (n[0] === 172 && n[1] >= 16 && n[1] <= 31) || (n[0] === 192 && n[1] === 168)
        || (n[0] === 169 && n[1] === 254) || (n[0] === 100 && n[1] >= 64 && n[1] <= 127)) return '';
    return n.join('.');
  }
  if (/^[0-9a-f:]+$/.test(ip) && ip.includes(':') && ip.length <= 39) {
    if (ip === '::1' || ip === '::' || /^f[cd]/.test(ip) || /^fe[89ab]/.test(ip)) return '';
    return ip;
  }
  return '';
}

// ----- Code Messenger : « UV- » + 6 signes faciles à lire (sans 0, O, 1, I, L) -----
const SIGNES_CODE = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
function codeMessenger(octets) { return 'UV-' + Array.from(octets).slice(0, 6).map(b => SIGNES_CODE[Number(b) % SIGNES_CODE.length]).join(''); }
// FIN-AIDES

// Petite liste de secours si la liste publique ne se charge pas.
const JETABLES_SECOURS = ['mailinator.com', 'yopmail.com', 'yopmail.fr', 'guerrillamail.com', 'sharklasers.com', '10minutemail.com',
  'temp-mail.org', 'tempmail.com', 'trashmail.com', 'getnada.com', 'dispostable.com', 'maildrop.cc', 'throwawaymail.com', 'fakeinbox.com',
  'mohmal.com', 'emailondeck.com', 'mintemail.com', 'tempail.com', 'mailnesia.com', 'mytemp.email'];
const ADRESSE_JETABLES = 'https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf';
const SERVICES_DNS = ['https://cloudflare-dns.com/dns-query?type=MX&name=', 'https://dns.google/resolve?type=MX&name='];
let CACHE_JETABLES: { liste: Set<string>; le: number } | null = null;

async function lireAvecDelai(adresse: string, ms: number, entetes: Record<string, string> = {}) {
  const ctrl = new AbortController();
  const minuteur = setTimeout(() => ctrl.abort(), ms);
  try { return await fetch(adresse, { headers: entetes, signal: ctrl.signal }); } finally { clearTimeout(minuteur); }
}
async function listeJetables(): Promise<Set<string>> {
  if (CACHE_JETABLES && Date.now() - CACHE_JETABLES.le < 86400000) return CACHE_JETABLES.liste;
  try {
    const r = await lireAvecDelai(ADRESSE_JETABLES, 5000);
    if (r.ok) {
      const liste = lireListeJetables(await r.text());
      if (liste.size > 1000) { JETABLES_SECOURS.forEach(d => liste.add(d)); CACHE_JETABLES = { liste, le: Date.now() }; return liste; }
    }
  } catch (_e) { /* liste de secours */ }
  return new Set(JETABLES_SECOURS);
}
// Renvoie « ok », « sans_mx », « inexistant », « jetable » ou « non_verifie » (services DNS muets : l'inscription passe).
async function verifierEmail(email: string): Promise<string> {
  const dom = domaineEmail(email);
  if (estJetable(dom, await listeJetables())) return 'jetable';
  for (const s of SERVICES_DNS) {
    try {
      const r = await lireAvecDelai(s + encodeURIComponent(dom), 5000, { Accept: 'application/dns-json' });
      const v = interpreterMx(await r.json().catch(() => null));
      if (v !== 'erreur') return v;
    } catch (_e) { /* service suivant */ }
  }
  return 'non_verifie';
}

async function empreinte(texte: string) {
  const o = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texte));
  return Array.from(new Uint8Array(o)).map(b => b.toString(16).padStart(2, '0')).join('');
}
const entetes = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json; charset=utf-8',
};
const reponse = (corps: unknown, statut = 200) => new Response(JSON.stringify(corps), { status: statut, headers: entetes });

// Appel à volsever avec les limites d'appels (24 heures glissantes et dernière minute ; les refus pour limite ne comptent pas).
// Sans clé, sans réponse ou limite atteinte : l'inscription passe, Katana revérifie plus tard.
// deno-lint-ignore no-explicit-any
async function appelerVolsever(sb: any, uid: string, P: Record<string, unknown>) {
  const depuis = (ms: number) => new Date(Date.now() - ms).toISOString();
  const compter = async (ms: number) => (await sb.from('volsever_appels').select('id', { count: 'exact', head: true })
    .neq('resultat', 'quota').gte('cree_le', depuis(ms))).count ?? 0;
  const [nbJour, nbMinute] = await Promise.all([compter(86400000), compter(60000)]);
  let r: { resultat: string; pseudo: string | null; http: number | null };
  const cle = Deno.env.get('VOLSEVER_API_KEY') ?? '';
  if (limiteAtteinte(nbJour, nbMinute, Number(P.volsever_max_jour), Number(P.volsever_max_minute))) r = { resultat: 'quota', pseudo: null, http: null };
  else if (!cle) r = { resultat: 'erreur', pseudo: null, http: null };
  else {
    const delai = Number.isFinite(Number(P.volsever_delai_s)) ? Number(P.volsever_delai_s) : 15;
    try {
      const rep = await lireAvecDelai(ADRESSE_VOLSEVER + encodeURIComponent(uid), delai * 1000, { 'X-API-KEY': cle, Accept: 'application/json' });
      const corps = await rep.json().catch(() => null);
      r = { ...interpreterVolsever(rep.status, corps), http: rep.status };
    } catch (e) {
      r = { resultat: e instanceof DOMException && e.name === 'AbortError' ? 'delai' : 'erreur', pseudo: null, http: null };
    }
  }
  const { data: a } = await sb.from('volsever_appels').insert({ compte_id: null, resultat: r.resultat, pseudo_trouve: r.pseudo, http: r.http }).select('id').single();
  return { ...r, appel: a ? a.id : null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: entetes });
  if (req.method !== 'POST') return reponse({ erreur: 'Méthode non autorisée.' }, 405);
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const cle = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !cle) return reponse({ erreur: 'Configuration Supabase incomplète.' }, 500);
  const sb = createClient(url, cle, { auth: { persistSession: false } });
  let userId = '', chemin = '';
  try {
    // 1. Inscriptions ouvertes ? (et réglages des vérifications)
    const { data: ps, error: ep } = await sb.from('parametres').select('cle, valeur')
      .in('cle', ['inscriptions_ouvertes', 'refus_uid_introuvable', 'volsever_max_jour', 'volsever_max_minute', 'volsever_delai_s',
        'longueur_max_court', 'longueur_max_long']);
    const P: Record<string, unknown> = {};
    (ps ?? []).forEach((x: { cle: string; valeur: unknown }) => { P[x.cle] = x.valeur; });
    if (ep || !('inscriptions_ouvertes' in P)) return reponse({ erreur: 'Lecture des réglages impossible (' + (ep ? ep.message : 'réglage introuvable') + '). Prévenez Katana.' }, 500);
    if (P.inscriptions_ouvertes !== true) return reponse({ erreur: 'Les inscriptions sont fermées pour le moment.' }, 403);

    // 2. Lecture et contrôle du formulaire
    const form = await req.formData();
    const d = JSON.parse(String(form.get('donnees') || '{}'));
    const capture = form.get('capture');
    const err = verifierDonnees(d, { court: P.longueur_max_court, long: P.longueur_max_long });
    if (!(capture instanceof File) || !capture.size) err.push('La capture du profil est obligatoire.');
    else if (capture.size > 5 * 1024 * 1024 || !/^image\/(jpeg|png|webp)$/.test(capture.type)) err.push('Capture invalide (image JPEG, PNG ou WebP de 5 Mo au plus).');
    if (err.length) return reponse({ erreur: err.join(' ') }, 400);

    const email = normEmail(d.email), fb = normFacebook(d.facebook), uid = String(d.uid).trim();
    const empEmail = await empreinte(email), empFb = await empreinte(fb);

    // 3. Doublons (avant de créer quoi que ce soit)
    const { data: dbl } = await sb.from('membres').select('id').or('empreinte_email.eq.' + empEmail + ',empreinte_facebook.eq.' + empFb).limit(1);
    if (dbl && dbl.length) return reponse({ erreur: 'Une inscription existe déjà avec cet e-mail ou ce lien Facebook. Contactez Katana sur Messenger.' }, 409);
    const { data: dblUid } = await sb.from('comptes_jeu').select('id').eq('uid', uid).limit(1);
    if (dblUid && dblUid.length) return reponse({ erreur: 'Cet UID est déjà enregistré. Contactez Katana sur Messenger.' }, 409);

    // 3 bis. E-mail : domaine existant, qui reçoit des e-mails, pas jetable
    const verifEmail = await verifierEmail(email);
    if (verifEmail in MESSAGES_EMAIL) return reponse({ erreur: MESSAGES_EMAIL[verifEmail as keyof typeof MESSAGES_EMAIL] }, 400);

    // 3 ter. Limites d'inscriptions par heure : commune (« inscriptions_max_heure », migration 0015) et par connexion
    // (« inscriptions_max_heure_ip », migration 0018). Protègent le quota de volsever et l'espace de stockage.
    const ip = adresseClient((nom: string) => req.headers.get(nom));
    const empIp = ip ? await empreinte('ip:' + ip) : null;
    const { data: place, error: el } = await sb.rpc('reserver_essai_inscription', { p_empreinte_ip: empIp });
    if (el) return reponse({ erreur: 'Inscription impossible pour le moment. Réessayez plus tard.' }, 500);
    if (place === 'limite_ip') return reponse({ erreur: MESSAGE_TROP_MEME_CONNEXION }, 429);
    if (place !== 'ok') return reponse({ erreur: MESSAGE_TROP_D_INSCRIPTIONS }, 429);

    // 3 quater. UID et pseudo chez volsever (en dernier : chaque appel compte dans la limite de 24 heures)
    const pseudoTape = String(d.pseudo).trim();
    const vs = await appelerVolsever(sb, uid, P);
    if (vs.resultat === 'introuvable' && P.refus_uid_introuvable !== false) return reponse({ erreur: MESSAGE_UID_INCONNU }, 400);
    const maintenant = new Date().toISOString();
    const verifications = {
      volsever: Object.assign({ resultat: vs.resultat, pseudo_declare: pseudoTape, le: maintenant }, vs.pseudo ? { pseudo_officiel: vs.pseudo } : {}),
      email: { resultat: verifEmail, le: maintenant },
    };
    const pseudoRetenu = vs.pseudo || pseudoTape;   // le pseudo lu sur le profil est retenu (écart signalé à Katana)
    const code = codeMessenger(crypto.getRandomValues(new Uint8Array(6)));

    // 4. Compte de connexion (adresse considérée comme confirmée : décision Q20)
    const { data: u, error: eu } = await sb.auth.admin.createUser({ email, password: String(d.mot_de_passe), email_confirm: true });
    if (eu || !u?.user) return reponse({ erreur: 'Un compte existe déjà avec cet e-mail, ou la création a échoué.' }, 409);
    userId = u.user.id;

    // 5. Capture du profil, rangée dans l'espace privé « profils »
    chemin = userId + '/profil-' + Date.now() + (capture.type === 'image/png' ? '.png' : capture.type === 'image/webp' ? '.webp' : '.jpg');
    const { error: es } = await sb.storage.from('profils').upload(chemin, capture, { contentType: capture.type, upsert: false });
    if (es) throw new Error('capture');

    // 6. Candidature (tout ou rien)
    const oui = (x: unknown) => x === 'Oui';
    const { error: ei } = await sb.rpc('creer_inscription', { p: {
      user_id: userId, nom_gamer: String(d.nom_gamer).trim(), nom_reel: String(d.nom_reel).trim(), email,
      date_naissance: d.date_naissance, genre: d.genre, facebook: String(d.facebook).trim(), clan: d.clan || '',
      pseudo: pseudoRetenu, uid, residence: d.residence,
      province: d.residence === 'Madagascar' ? d.province : '', zone: d.residence === 'Madagascar' ? d.zone : '',
      pays: d.residence === 'Étranger' ? d.pays : '', comprend_mg: oui(d.comprend_mg), parle_mg: oui(d.parle_mg),
      origine_mg: d.origine_mg === true,
      acceptations: { dfmm: true, league_uv: true, donnees: true, approbation: true, date: new Date().toISOString() },
      empreinte_email: empEmail, empreinte_facebook: empFb, capture_profil: chemin,
      verifications, code_messenger: code, appel_volsever: vs.appel,
    } });
    if (ei) {
      const m = /DOUBLON_UID/.test(ei.message) ? 'Cet UID est déjà enregistré.' : /DOUBLON_INSCRIPTION/.test(ei.message) ? 'Une inscription existe déjà avec cet e-mail ou ce lien Facebook.' : 'Inscription impossible.';
      throw new Error(m);
    }
    return reponse({ ok: true, code_messenger: code, pseudo_retenu: pseudoRetenu, ecart_pseudo: !!vs.pseudo && vs.pseudo !== pseudoTape });
  } catch (e) {
    // Annulation : rien ne reste à moitié créé.
    if (chemin) await sb.storage.from('profils').remove([chemin]).catch(() => {});
    if (userId) await sb.auth.admin.deleteUser(userId).catch(() => {});
    const m = e instanceof Error && e.message && e.message !== 'capture' ? e.message : 'Inscription impossible pour le moment. Réessayez plus tard.';
    return reponse({ erreur: m }, 400);
  }
});
