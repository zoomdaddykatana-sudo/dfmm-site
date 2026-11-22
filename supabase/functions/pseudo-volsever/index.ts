// LEAGUE UV — DFMM · Fonction « pseudo-volsever »
// Un membre connecté déclare un nouveau pseudo pour l'un de ses comptes.
// La fonction lit le pseudo officiel chez volsever à partir de l'UID enregistré
// (clé dans le secret VOLSEVER_API_KEY, jamais dans le code), puis enregistre le résultat.
// Avant l'appel : 1 déclaration par compte et par 24 h (réglable), refus pendant une suspension, 100 caractères
// au plus (réglable) — fonction reserver_declaration_pseudo (migration 0015).
// Limites d'appels réglables ; sans réponse utilisable, la déclaration reste en attente
// et Katana la valide à la main.
// Deuxième usage (Katana seulement) : { reverifier_inscription: <n° de candidature> } relit chez volsever
// l'UID d'une candidature en attente (bouton « Revérifier » dans Administration > Inscriptions).
import { createClient } from 'npm:@supabase/supabase-js@2.117.3';

// DEBUT-AIDES (JavaScript simple, testé automatiquement par tests/volsever.test.js)
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
const MESSAGES = {
  conforme: 'Votre pseudo est confirmé : il correspond à votre profil.',
  modifie: 'Votre pseudo est mis à jour.',
  ecart: 'Le pseudo lu sur votre profil est différent de celui que vous avez déclaré. Le pseudo du profil est retenu ; Katana va vérifier.',
  attente: 'La vérification automatique n’a pas pu se faire. Votre déclaration est en attente : Katana va la valider à la main.',
};
// FIN-AIDES

const entetes = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json; charset=utf-8',
};
const reponse = (corps: unknown, statut = 200) => new Response(JSON.stringify(corps), { status: statut, headers: entetes });

// Appel à volsever (ou pas, si la limite est atteinte ou la clé absente), noté dans « volsever_appels ».
// Limites : 24 heures glissantes et dernière minute ; les refus pour limite ne comptent pas.
// deno-lint-ignore no-explicit-any
async function appelerVolsever(sb: any, uid: string, compteId: number) {
  const { data: ps } = await sb.from('parametres').select('cle, valeur').in('cle', ['volsever_max_jour', 'volsever_max_minute', 'volsever_delai_s']);
  const P: Record<string, number> = {};
  (ps ?? []).forEach((p: { cle: string; valeur: unknown }) => { P[p.cle] = Number(p.valeur); });
  const depuis = (ms: number) => new Date(Date.now() - ms).toISOString();
  const compter = async (ms: number) => (await sb.from('volsever_appels').select('id', { count: 'exact', head: true })
    .neq('resultat', 'quota').gte('cree_le', depuis(ms))).count ?? 0;
  const [nbJour, nbMinute] = await Promise.all([compter(86400000), compter(60000)]);
  let r: { resultat: string; pseudo: string | null; http: number | null };
  const cle = Deno.env.get('VOLSEVER_API_KEY') ?? '';
  if (limiteAtteinte(nbJour, nbMinute, P.volsever_max_jour, P.volsever_max_minute)) r = { resultat: 'quota', pseudo: null, http: null };
  else if (!cle) r = { resultat: 'erreur', pseudo: null, http: null };
  else {
    const ctrl = new AbortController();
    const minuteur = setTimeout(() => ctrl.abort(), (Number.isFinite(P.volsever_delai_s) ? P.volsever_delai_s : 15) * 1000);
    try {
      const rep = await fetch(ADRESSE_VOLSEVER + encodeURIComponent(uid), { headers: { 'X-API-KEY': cle, Accept: 'application/json' }, signal: ctrl.signal });
      const corps = await rep.json().catch(() => null);
      r = { ...interpreterVolsever(rep.status, corps), http: rep.status };
    } catch (e) {
      r = { resultat: e instanceof DOMException && e.name === 'AbortError' ? 'delai' : 'erreur', pseudo: null, http: null };
    } finally { clearTimeout(minuteur); }
  }
  await sb.from('volsever_appels').insert({ compte_id: compteId, resultat: r.resultat, pseudo_trouve: r.pseudo, http: r.http });
  return r;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: entetes });
  if (req.method !== 'POST') return reponse({ erreur: 'Méthode non autorisée.' }, 405);
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const clePublique = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const cleServeur = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !clePublique || !cleServeur) return reponse({ erreur: 'Configuration Supabase incomplète.' }, 500);
  try {
    // 1. Le membre connecté
    const appelant = createClient(url, clePublique, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const { data: qui } = await appelant.auth.getUser();
    if (!qui?.user) return reponse({ erreur: 'Connectez-vous d’abord.' }, 401);
    const corpsDemande = await req.json().catch(() => ({}));
    const { compte_id, pseudo, reverifier_inscription } = corpsDemande;
    const sb = createClient(url, cleServeur, { auth: { persistSession: false } });

    // 1 bis. Revérification d'une candidature par Katana
    if (reverifier_inscription != null) {
      const { data: adm } = await sb.from('admins').select('user_id').eq('user_id', qui.user.id).maybeSingle();
      if (!adm) return reponse({ erreur: 'Accès réservé à l’administrateur.' }, 403);
      const { data: cand } = await sb.from('membres').select('id, statut, comptes_jeu(id, uid)').eq('id', Number(reverifier_inscription)).maybeSingle();
      if (!cand || ['en_attente', 'precisions'].indexOf(cand.statut) < 0) return reponse({ erreur: 'Candidature introuvable ou déjà traitée.' }, 400);
      const cpt = (cand.comptes_jeu ?? []).sort((a: { id: number }, b: { id: number }) => a.id - b.id)[0];
      if (!cpt) return reponse({ erreur: 'Aucun compte de jeu dans cette candidature.' }, 400);
      const rv = await appelerVolsever(sb, cpt.uid, cpt.id);
      const { data: verif, error: ev } = await sb.rpc('noter_reverification', { p_admin: qui.user.id, p_membre: cand.id, p_resultat: rv.resultat, p_trouve: rv.pseudo });
      if (ev) return reponse({ erreur: ev.message }, 400);
      return reponse({ verification: verif });
    }

    const tape = String(pseudo ?? '').trim();
    if (!tape) return reponse({ erreur: 'Le nouveau pseudo est obligatoire.' }, 400);

    const { data: m } = await sb.from('membres').select('id, statut').eq('user_id', qui.user.id).maybeSingle();
    if (!m || m.statut !== 'actif') return reponse({ erreur: 'Cette démarche est réservée aux membres actifs.' }, 403);
    const { data: c } = await sb.from('comptes_jeu').select('id, uid, statut').eq('id', Number(compte_id)).eq('membre_id', m.id).maybeSingle();
    if (!c || c.statut === 'remplace') return reponse({ erreur: 'Choisissez l’un de vos comptes.' }, 400);
    // 1 ter. Contrôles avant tout appel à volsever (migration 0015) : pas de suspension, pseudo pas trop long,
    // aucune déclaration en attente, 1 déclaration par compte et par « pseudo_delai_h » heures. La déclaration est notée.
    const { error: er } = await sb.rpc('reserver_declaration_pseudo', { p_user: qui.user.id, p_compte: c.id, p_tape: tape });
    if (er) return reponse({ erreur: er.message }, 409);

    // 2 et 3. Limites d'appels, puis appel à volsever
    const r = await appelerVolsever(sb, c.uid, c.id);

    // 4. Enregistrement (le pseudo trouvé remplace toujours l'actuel ; écart = vérification par Katana)
    const { data: issue, error } = await sb.rpc('enregistrer_declaration_pseudo',
      { p_user: qui.user.id, p_compte: c.id, p_tape: tape, p_resultat: r.resultat, p_trouve: r.pseudo });
    if (error) return reponse({ erreur: error.message }, 400);
    return reponse({ issue, message: MESSAGES[issue as keyof typeof MESSAGES] ?? '', pseudo_retenu: r.pseudo });
  } catch (_e) {
    return reponse({ erreur: 'Erreur inattendue. Réessayez plus tard.' }, 500);
  }
});
