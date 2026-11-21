// LEAGUE UV — DFMM · Fonction « effacer-donnees » (administrateur seulement)
// Exécute une demande d'effacement (décision Q10) : efface les données personnelles prévues,
// supprime les captures du membre, puis supprime son compte de connexion (l'accès est fermé).
// Gardés : empreintes de l'e-mail et du lien Facebook, UID, pseudos, matricule, statistiques.
import { createClient } from 'npm:@supabase/supabase-js@2.117.3';

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
  const clePublique = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const cleServeur = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !clePublique || !cleServeur) return reponse({ erreur: 'Configuration Supabase incomplète.' }, 500);
  try {
    const appelant = createClient(url, clePublique, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
    const { data: estAdmin, error: ea } = await appelant.rpc('est_admin');
    if (ea || estAdmin !== true) return reponse({ erreur: 'Accès réservé à l’administrateur.' }, 403);
    const { demande_id } = await req.json().catch(() => ({}));
    if (!Number.isInteger(Number(demande_id))) return reponse({ erreur: 'Demande invalide.' }, 400);

    const sb = createClient(url, cleServeur, { auth: { persistSession: false } });
    // 1. Données personnelles effacées dans la base (tout ou rien)
    const { data: r, error } = await sb.rpc('effacer_donnees_membre', { p_demande: Number(demande_id) });
    if (error) return reponse({ erreur: error.message }, 400);
    const userId: string | null = r?.user_id ?? null;
    const captures: string[] = Array.isArray(r?.captures) ? r.captures : [];

    // 2. Captures du membre (celles notées dans la base, et tout son dossier)
    let fichiers = 0;
    if (userId) {
      const { data: liste } = await sb.storage.from('profils').list(userId, { limit: 1000 });
      (liste ?? []).forEach((f: { name: string }) => { const ch = userId + '/' + f.name; if (captures.indexOf(ch) < 0) captures.push(ch); });
    }
    if (captures.length) {
      const { data: supp } = await sb.storage.from('profils').remove(captures);
      fichiers = (supp ?? []).length;
    }

    // 3. Compte de connexion supprimé : l'accès est fermé
    let compteSupprime = false;
    if (userId) {
      const { error: eu } = await sb.auth.admin.deleteUser(userId);
      compteSupprime = !eu;
    }
    return reponse({ ok: true, fichiers_supprimes: fichiers, compte_supprime: compteSupprime });
  } catch (_e) {
    return reponse({ erreur: 'Erreur inattendue. Rien n’a été effacé si la première étape a échoué.' }, 500);
  }
});
