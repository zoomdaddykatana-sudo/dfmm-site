// LEAGUE UV — DFMM · Fonction « inscription »
// Reçoit le formulaire d'inscription (données + capture du profil) et crée :
// le compte de connexion (sans e-mail de confirmation), la candidature en attente,
// le compte de jeu et la capture rangée dans un espace privé.
// N'accepte rien si le paramètre « inscriptions_ouvertes » est à « non ».
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
function verifierDonnees(d) {
  const err = [];
  const txt = k => String(d[k] == null ? '' : d[k]).trim();
  ['nom_reel', 'nom_gamer', 'email', 'date_naissance', 'genre', 'facebook', 'pseudo', 'uid', 'residence', 'comprend_mg', 'parle_mg'].forEach(k => { if (!txt(k)) err.push('Champ manquant : ' + k + '.'); });
  if (txt('email') && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(txt('email'))) err.push('Adresse e-mail invalide.');
  if (txt('facebook') && !/^facebook\.com\/[^\s]+$/.test(normFacebook(txt('facebook')))) err.push('Lien Facebook invalide.');
  if (txt('date_naissance') && !(/^\d{4}-\d{2}-\d{2}$/.test(txt('date_naissance')) && txt('date_naissance') < new Date().toISOString().slice(0, 10))) err.push('Date de naissance invalide.');
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
// FIN-AIDES

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: entetes });
  if (req.method !== 'POST') return reponse({ erreur: 'Méthode non autorisée.' }, 405);
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const cle = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !cle) return reponse({ erreur: 'Configuration Supabase incomplète.' }, 500);
  const sb = createClient(url, cle, { auth: { persistSession: false } });
  let userId = '', chemin = '';
  try {
    // 1. Inscriptions ouvertes ?
    const { data: p } = await sb.from('parametres').select('valeur').eq('cle', 'inscriptions_ouvertes').single();
    if (!p || p.valeur !== true) return reponse({ erreur: 'Les inscriptions sont fermées pour le moment.' }, 403);

    // 2. Lecture et contrôle du formulaire
    const form = await req.formData();
    const d = JSON.parse(String(form.get('donnees') || '{}'));
    const capture = form.get('capture');
    const err = verifierDonnees(d);
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
      pseudo: String(d.pseudo).trim(), uid, residence: d.residence,
      province: d.residence === 'Madagascar' ? d.province : '', zone: d.residence === 'Madagascar' ? d.zone : '',
      pays: d.residence === 'Étranger' ? d.pays : '', comprend_mg: oui(d.comprend_mg), parle_mg: oui(d.parle_mg),
      origine_mg: d.origine_mg === true,
      acceptations: { dfmm: true, league_uv: true, donnees: true, approbation: true, date: new Date().toISOString() },
      empreinte_email: empEmail, empreinte_facebook: empFb, capture_profil: chemin,
    } });
    if (ei) {
      const m = /DOUBLON_UID/.test(ei.message) ? 'Cet UID est déjà enregistré.' : /DOUBLON_INSCRIPTION/.test(ei.message) ? 'Une inscription existe déjà avec cet e-mail ou ce lien Facebook.' : 'Inscription impossible.';
      throw new Error(m);
    }
    return reponse({ ok: true });
  } catch (e) {
    // Annulation : rien ne reste à moitié créé.
    if (chemin) await sb.storage.from('profils').remove([chemin]).catch(() => {});
    if (userId) await sb.auth.admin.deleteUser(userId).catch(() => {});
    const m = e instanceof Error && e.message && e.message !== 'capture' ? e.message : 'Inscription impossible pour le moment. Réessayez plus tard.';
    return reponse({ erreur: m }, 400);
  }
});
