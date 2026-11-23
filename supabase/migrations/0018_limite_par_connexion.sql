-- =====================================================================
-- LEAGUE UV — DFMM · Limite d'inscriptions par connexion · migration 0018
-- Audit du 23/11/2026 : la limite par heure (« inscriptions_max_heure ») est commune à tout le monde ;
-- une seule personne peut l'épuiser et bloquer les autres joueurs.
-- Choix de Katana du 23/11/2026 : 3 inscriptions vérifiées par heure et par adresse IP, en plus de la limite commune.
-- Protection des données : l'adresse IP n'est jamais enregistrée en clair. La fonction « inscription » n'envoie
-- qu'une empreinte (SHA-256) ; cette empreinte est effacée au bout de 24 h.
-- Compatible avec l'ancienne fonction « inscription » : reserver_essai_inscription() sans argument est gardée.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 1 réglage, 1 colonne, 1 index et 1 fonction.
-- =====================================================================
begin;

-- ---------- Réglage (Administration > Paramètres > Limites) ----------
insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('inscriptions_max_heure_ip', '3', 'entier',
   'Inscriptions vérifiées par heure depuis une même connexion (adresse IP), au plus', 'Limites', 5);

-- ---------- Compteur : empreinte de la connexion ----------
alter table public.inscription_essais add column empreinte_ip text;
create index inscription_essais_ip on public.inscription_essais (empreinte_ip, cree_le) where empreinte_ip is not null;

-- ---------- Inscription : une place dans les deux limites (appelée par la fonction « inscription ») ----------
-- Renvoie « ok » (place notée), « limite_ip » (trop d'envois depuis cette connexion) ou « limite » (limite commune
-- atteinte, ou réglage illisible). Sans empreinte (adresse inconnue), seule la limite commune s'applique.
create function public.reserver_essai_inscription(p_empreinte_ip text) returns text
language plpgsql security definer set search_path = ''
as $$
declare v_max    int  := (public.lire_param('inscriptions_max_heure') #>> '{}')::int;
        v_max_ip int  := (public.lire_param('inscriptions_max_heure_ip') #>> '{}')::int;
        v_ip     text := nullif(trim(coalesce(p_empreinte_ip, '')), '');
begin
  perform pg_advisory_xact_lock(hashtext('dfmm_inscription_essais'));   -- deux envois en même temps : l'un après l'autre
  -- Les empreintes de plus de 24 h sont effacées (le compteur commun garde la ligne, sans empreinte).
  update public.inscription_essais set empreinte_ip = null
   where empreinte_ip is not null and cree_le < clock_timestamp() - interval '24 hours';
  if v_max is null or (select count(*) from public.inscription_essais where cree_le > clock_timestamp() - interval '1 hour') >= v_max then
    return 'limite';
  end if;
  if v_ip is not null and v_max_ip is not null and (select count(*) from public.inscription_essais
       where empreinte_ip = v_ip and cree_le > clock_timestamp() - interval '1 hour') >= v_max_ip then
    return 'limite_ip';
  end if;
  insert into public.inscription_essais (empreinte_ip) values (v_ip);
  return 'ok';
end $$;

revoke all on function public.reserver_essai_inscription(text) from public, anon, authenticated;
grant execute on function public.reserver_essai_inscription(text) to service_role;

commit;
