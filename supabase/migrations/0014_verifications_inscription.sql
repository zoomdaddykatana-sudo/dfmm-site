-- =====================================================================
-- LEAGUE UV — DFMM · Vérifications automatiques à l'inscription · migration 0014
-- Choix de Katana du 22/11/2026 : UID inexistant chez volsever = refus immédiat (réglable) ;
-- e-mail : domaine inexistant ou jetable refusé ; code Messenger ; code par e-mail : plus tard.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 2 colonnes, 1 réglage et 1 fonction, et complète creer_inscription.
-- =====================================================================
begin;

-- ---------- Réglage ----------
-- Oui : un UID que volsever ne connaît pas bloque l'inscription. Non : l'inscription passe avec une alerte.
insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('refus_uid_introuvable', 'true', 'booleen', 'Inscription : refuser un UID inconnu de volsever', 'Site', 5);

-- ---------- Résultats des vérifications et code Messenger ----------
-- verifications = {"volsever": {"resultat", "pseudo_declare", "pseudo_officiel", "le"}, "email": {"resultat", "le"}}
-- code_messenger = code que le joueur envoie à la page DFMM depuis le compte Facebook indiqué.
alter table public.membres_prives
  add column verifications  jsonb not null default '{}'::jsonb,
  add column code_messenger text check (code_messenger is null or code_messenger ~ '^UV-[0-9A-Z]{6}$');

-- ---------- Création d'une inscription : mêmes contrôles qu'en 0002, avec les vérifications ----------
create or replace function public.creer_inscription(p jsonb) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint; v_cpt bigint;
begin
  if coalesce(p->>'user_id', '') = '' or coalesce(trim(p->>'nom_gamer'), '') = '' or coalesce(trim(p->>'uid'), '') = ''
     or coalesce(trim(p->>'pseudo'), '') = '' or coalesce(p->>'empreinte_email', '') = '' or coalesce(p->>'empreinte_facebook', '') = '' then
    raise exception 'Inscription incomplète.';
  end if;
  if exists (select 1 from public.membres where empreinte_email = p->>'empreinte_email' or empreinte_facebook = p->>'empreinte_facebook') then
    raise exception 'DOUBLON_INSCRIPTION';
  end if;
  if exists (select 1 from public.comptes_jeu where uid = trim(p->>'uid')) then
    raise exception 'DOUBLON_UID';
  end if;
  insert into public.membres (user_id, nom_gamer, statut, empreinte_email, empreinte_facebook)
  values ((p->>'user_id')::uuid, trim(p->>'nom_gamer'), 'en_attente', p->>'empreinte_email', p->>'empreinte_facebook')
  returning id into v_id;
  insert into public.membres_prives (membre_id, nom_reel, email, date_naissance, genre, facebook, clan, residence,
    province, zone, pays, comprend_mg, parle_mg, origine_mg, acceptations, capture_profil, verifications, code_messenger)
  values (v_id, p->>'nom_reel', p->>'email', nullif(p->>'date_naissance', '')::date, p->>'genre', p->>'facebook',
    nullif(p->>'clan', ''), p->>'residence', nullif(p->>'province', ''), nullif(p->>'zone', ''), nullif(p->>'pays', ''),
    (p->>'comprend_mg')::boolean, (p->>'parle_mg')::boolean, coalesce((p->>'origine_mg')::boolean, false),
    coalesce(p->'acceptations', '{}'::jsonb), nullif(p->>'capture_profil', ''),
    case when jsonb_typeof(p->'verifications') = 'object' then p->'verifications' else '{}'::jsonb end,
    nullif(p->>'code_messenger', ''));
  insert into public.comptes_jeu (membre_id, uid, pseudo, statut) values (v_id, trim(p->>'uid'), trim(p->>'pseudo'), 'en_pause')
  returning id into v_cpt;
  insert into public.pseudos_historique (compte_id, pseudo, debut) values (v_cpt, trim(p->>'pseudo'), now());
  -- L'appel à volsever fait avant la création est rattaché au compte.
  if coalesce(p->>'appel_volsever', '') ~ '^\d+$' then
    update public.volsever_appels set compte_id = v_cpt where id = (p->>'appel_volsever')::bigint and compte_id is null;
  end if;
  insert into public.journal (type, objet, decision, auteur)
  values ('Inscription', v_id::text, 'Candidature reçue : ' || trim(p->>'nom_gamer'), (p->>'user_id')::uuid);
  return v_id;
end $$;

-- ---------- Nouvelle vérification par volsever, demandée par Katana (bouton « Revérifier ») ----------
-- Appelée seulement par la fonction serveur « pseudo-volsever », qui fait l'appel à volsever.
-- Pseudo trouvé : il remplace le pseudo de la candidature (même règle que les changements de pseudo).
create function public.noter_reverification(p_admin uuid, p_membre bigint, p_resultat text, p_trouve text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; c public.comptes_jeu%rowtype; v_avant jsonb; v_nouv jsonb;
begin
  if not exists (select 1 from public.admins where user_id = p_admin) then raise exception 'Accès réservé à l''administrateur.'; end if;
  if p_resultat not in ('trouve', 'introuvable', 'erreur', 'delai', 'quota') then raise exception 'Résultat inconnu.'; end if;
  select * into m from public.membres where id = p_membre for update;
  if not found then raise exception 'Candidature introuvable.'; end if;
  if m.statut not in ('en_attente', 'precisions') then raise exception 'Cette candidature a déjà été traitée.'; end if;
  select * into c from public.comptes_jeu where membre_id = m.id order by id limit 1 for update;
  if not found then raise exception 'Aucun compte de jeu dans cette candidature.'; end if;
  select coalesce(verifications->'volsever', '{}'::jsonb) into v_avant from public.membres_prives where membre_id = m.id;
  v_nouv := jsonb_build_object('resultat', p_resultat, 'pseudo_declare', coalesce(v_avant->>'pseudo_declare', c.pseudo),
                               'le', clock_timestamp(), 'reverifie', true);
  if p_resultat = 'trouve' and coalesce(p_trouve, '') <> '' then
    v_nouv := v_nouv || jsonb_build_object('pseudo_officiel', p_trouve);
    if c.pseudo <> p_trouve then
      update public.comptes_jeu set pseudo = p_trouve where id = c.id;
      update public.pseudos_historique set pseudo = p_trouve where compte_id = c.id and fin is null;
    end if;
  end if;
  update public.membres_prives set verifications = verifications || jsonb_build_object('volsever', v_nouv), modifie_le = clock_timestamp()
  where membre_id = m.id;
  insert into public.journal (type, objet, decision, auteur)
  values ('Inscription', m.id::text, 'Revérification par volsever : ' || case p_resultat when 'trouve' then 'UID trouvé, pseudo ' || p_trouve
    when 'introuvable' then 'UID introuvable' when 'quota' then 'limite d''appels atteinte' when 'delai' then 'pas de réponse à temps'
    else 'volsever indisponible' end, p_admin);
  return v_nouv;
end $$;

revoke all on function public.noter_reverification(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.noter_reverification(uuid, bigint, text, text) to service_role;

commit;
