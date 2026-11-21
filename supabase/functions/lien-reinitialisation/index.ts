// LEAGUE UV — DFMM · Fonction « lien-reinitialisation »
// Crée un lien de réinitialisation du mot de passe, SANS envoyer d'e-mail.
// Katana copie le lien et l'envoie lui-même au joueur (Messenger).
// Réservée à l'administrateur. La clé secrète n'est lue que dans Supabase.
import { createClient } from 'npm:@supabase/supabase-js@2.117.3';

const entetes = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json; charset=utf-8',
};
const reponse = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: entetes });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: entetes });
  if (req.method !== 'POST') return reponse({ erreur: 'Méthode non autorisée.' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? '';
    const clePublique = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const cleSecrete = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (!url || !clePublique || !cleSecrete) return reponse({ erreur: 'Configuration Supabase incomplète.' }, 500);

    // 1. Qui appelle ? Seul l'administrateur passe.
    const auth = req.headers.get('Authorization') ?? '';
    const appelant = createClient(url, clePublique, { global: { headers: { Authorization: auth } } });
    const { data: estAdmin, error: errAdmin } = await appelant.rpc('est_admin');
    if (errAdmin || estAdmin !== true) return reponse({ erreur: 'Accès réservé à l’administrateur.' }, 403);
    const { data: moi } = await appelant.auth.getUser();

    // 2. Données reçues
    const { email, redirectTo } = await req.json().catch(() => ({}));
    if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      return reponse({ erreur: 'Adresse e-mail invalide.' }, 400);
    }

    // 3. Création du lien (aucun e-mail n'est envoyé par cet appel)
    const admin = createClient(url, cleSecrete, { auth: { persistSession: false } });
    const { data, error } = await admin.auth.admin.generateLink({
      type: 'recovery',
      email: email.trim().toLowerCase(),
      options: typeof redirectTo === 'string' && redirectTo ? { redirectTo } : undefined,
    });
    if (error || !data?.properties?.action_link) {
      return reponse({ erreur: 'Aucun compte avec cette adresse, ou création impossible.' }, 400);
    }

    // 4. Trace dans le journal (sans l'adresse e-mail)
    await admin.from('journal').insert({
      type: 'Compte', decision: 'Lien de réinitialisation du mot de passe créé',
      objet: data.user?.id ?? null, auteur: moi?.user?.id ?? null,
    });
    return reponse({ lien: data.properties.action_link });
  } catch (_e) {
    return reponse({ erreur: 'Erreur inattendue.' }, 500);
  }
});
