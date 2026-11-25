-- =====================================================================
-- LEAGUE UV — DFMM · Rappels sur les téléphones (notifications) · migration 0020
-- Demande de Katana du 25/11/2026 (choix « A », « 1b », « 2a », « 3a », matchs libres validés) :
--  - notifications sur le téléphone, même site fermé (« notifications du site », Web Push) ;
--  - matchs du mercredi et du samedi (calendrier) : le matin du match (10 h) et 35 min avant le début
--    (15 h 30 pour 16 h 05) ; un match reporté ou annulé le jour même : le rappel le dit ;
--  - matchs libres annoncés : le matin du match (ou dès l'annonce si elle est faite après), 30 min avant,
--    et un avis si le match est annulé après un rappel ;
--  - « code de la salle disponible » dès que l'organisateur l'enregistre (le code lui-même n'est JAMAIS
--    dans la notification : il reste sur le site) ; envoyé seulement aux membres actifs non suspendus ;
--  - les autres rappels : tous les membres actifs inscrits aux rappels, suspendus compris (et Katana).
-- Fonctionnement : chaque minute, la base (pg_cron) regarde s'il y a un rappel à envoyer ; si oui, elle appelle
-- la fonction « rappels » (pg_net), qui chiffre et envoie les notifications. La clé des notifications (VAPID) est
-- créée toute seule par la fonction au premier appel et rangée dans le schéma « prive », que personne ne peut lire
-- (ni les visiteurs, ni les membres, ni la sauvegarde) ; le mot de passe entre la base et la fonction aussi.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 4 réglages, 3 tables, un schéma privé, des fonctions ; active pg_net et pg_cron
-- (extensions fournies par Supabase) et programme la tâche « dfmm-rappels » (chaque minute).
-- =====================================================================
begin;

-- ---------- Réglages (Administration > Paramètres > Rappels) ----------
insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('rappels_actifs',          'true',    'booleen', 'Rappels sur les téléphones (notifications)',                                   'Rappels', 1),
  ('rappel_matin_heure',      '"10:00"', 'heure',   'Heure du rappel du matin, le jour du match',                                   'Rappels', 2),
  ('rappel_avant_katana_min', '35',      'entier',  'Rappel avant un match du mercredi ou du samedi (min avant le début ; 35 = 15 h 30)', 'Rappels', 3),
  ('rappel_avant_libre_min',  '30',      'entier',  'Rappel avant un match libre (min avant le début)',                            'Rappels', 4);

-- ---------- Schéma privé : mot de passe base ↔ fonction, clé des notifications ----------
create schema if not exists prive;
revoke all on schema prive from public, anon, authenticated;
create table prive.rappels_config (
  id             boolean primary key default true check (id),
  secret         text not null,                 -- mot de passe envoyé par la base à la fonction « rappels »
  url_fonction   text not null,
  sujet          text not null,                 -- contact donné aux services de notification (adresse du site)
  vapid_public   text,                          -- clé publique (donnée aux téléphones)
  vapid_prive    text,                          -- clé privée (JWK), créée par la fonction, jamais affichée
  cle_le         timestamptz,
  dernier_reveil timestamptz,                   -- dernier appel de la fonction par la base
  dernier_envoi  timestamptz,
  dernier_bilan  jsonb
);
revoke all on prive.rappels_config from public, anon, authenticated;
insert into prive.rappels_config (secret, url_fonction, sujet)
values (replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
        'https://ijpbplzbjohfrqwnvrqv.supabase.co/functions/v1/rappels',
        'https://zoomdaddykatana-sudo.github.io/dfmm-site/');

-- ---------- Téléphones inscrits aux rappels ----------
create table public.abonnements_push (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  endpoint        text not null unique,          -- adresse technique du téléphone chez Google, Apple ou Mozilla
  p256dh          text not null,
  auth            text not null,
  cree_le         timestamptz not null default clock_timestamp(),
  vu_le           timestamptz not null default clock_timestamp(),
  dernier_envoi   timestamptz,
  echecs          int not null default 0,
  derniere_erreur text
);
create index abonnements_push_user on public.abonnements_push (user_id);

-- Rappels déjà envoyés (un rappel n'est jamais envoyé deux fois) ; effacés après 30 jours.
create table public.rappels_envoyes (
  cle           text primary key,
  envoye_le     timestamptz not null default clock_timestamp(),
  destinataires int
);

-- « Envoyer un essai à ce téléphone » (1 toutes les 5 minutes).
create table public.rappels_essais (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  demande_le timestamptz not null default clock_timestamp(),
  envoye_le  timestamptz
);

-- =====================================================================
-- Outils internes
-- =====================================================================
create function public.rappel_h(p_t timestamptz) returns text
language sql stable set search_path = ''
as $$ select to_char(p_t at time zone 'Indian/Antananarivo', 'FMHH24" h "MI') $$;

create function public.rappel_matin(p_jour date) returns timestamptz
language sql stable security definer set search_path = ''
as $$ select (p_jour + coalesce((public.lire_param('rappel_matin_heure') #>> '{}')::time, time '10:00')) at time zone 'Indian/Antananarivo' $$;

create function public.rappel_min(p_cle text, p_defaut int) returns interval
language sql stable security definer set search_path = ''
as $$ select make_interval(mins => coalesce((public.lire_param(p_cle) #>> '{}')::int, p_defaut)) $$;

-- Rappels à envoyer maintenant (pas encore envoyés). cible : tous (membres actifs et Katana),
-- code (membres actifs non suspendus et Katana), essai (les téléphones d'une personne).
create function public.rappels_dus()
returns table (cle text, cible text, user_id uuid, titre text, texte text, expire timestamptz, tag text)
language sql stable security definer set search_path = ''
as $$
with p as (
  select clock_timestamp() t, public.rappel_min('rappel_avant_katana_min', 35) ak, public.rappel_min('rappel_avant_libre_min', 30) al,
         public.rappel_min('salle_ouverture_min', 15) ouv, public.plage_fin() plage
),
j as (
  select j.*, public.rappel_matin(j.jour) matin from public.jours_match j, p
   where j.debut > p.t - p.plage - interval '1 hour' and j.debut < p.t + interval '2 days'
),
c as (
  select c.*, public.rappel_matin((c.debut at time zone 'Indian/Antananarivo')::date) matin, o.nom_gamer org
    from public.creneaux c join public.membres o on o.id = c.organisateur_id, p
   where c.debut > p.t - p.plage - interval '1 hour' and c.debut < p.t + interval '2 days'
),
tout as (
  -- Match du calendrier : le matin
  select 'j' || j.id || ':matin' cle, 'tous' cible, null::uuid user_id, 'LEAGUE UV — match aujourd''hui' titre,
         'Début à ' || public.rappel_h(j.debut) || ' · carte ' || coalesce(j.carte, '—') || ' · salle ouverte à '
           || public.rappel_h(j.debut - p.ouv) || '.' texte, j.debut expire, 'j' || j.id tag
    from j, p where j.statut = 'prevu' and p.t >= j.matin and p.t < j.debut - p.ak
  union all
  -- Match du calendrier : avant le début
  select 'j' || j.id || ':avant', 'tous', null, 'LEAGUE UV — match à ' || public.rappel_h(j.debut),
         'Carte ' || coalesce(j.carte, '—') || ' · salle ouverte à ' || public.rappel_h(j.debut - p.ouv)
           || '. Le code de la salle sera sur le site, dans « Prochains événements ».', j.debut + interval '15 minutes', 'j' || j.id
    from j, p where j.statut = 'prevu' and p.t >= j.debut - p.ak and p.t < j.debut
  union all
  -- Match du calendrier reporté ou annulé : le jour du match (dès le matin, ou dès la décision)
  select 'j' || j.id || ':' || j.statut, 'tous', null,
         case when j.statut = 'reporte' then 'LEAGUE UV — match reporté' else 'LEAGUE UV — match annulé' end,
         case when j.statut = 'reporte'
              then 'Le match d''aujourd''hui (' || public.rappel_h(j.debut) || ') est reporté' || coalesce(' (' || j.motif || ')', '')
                   || ' : la carte ' || coalesce(j.carte, '—') || ' passe au match suivant.'
              else 'Pas de match LEAGUE UV aujourd''hui : le match de ' || public.rappel_h(j.debut) || ' est annulé'
                   || coalesce(' (' || j.motif || ')', '') || '.' end,
         j.debut + p.plage, 'j' || j.id
    from j, p where j.statut in ('reporte', 'annule') and p.t >= greatest(j.matin, coalesce(j.modifie_le, j.cree_le)) and p.t < j.debut + p.plage
  union all
  -- Match du calendrier : code de la salle enregistré (1 minute après la saisie, pas avant le matin du match)
  select 'j' || j.id || ':code:' || floor(extract(epoch from s.modifie_le))::bigint, 'code', null,
         case when exists (select 1 from public.rappels_envoyes r where r.cle like 'j' || j.id || ':code:%')
              then 'LEAGUE UV — code de la salle modifié' else 'LEAGUE UV — code de la salle disponible' end,
         'Match de ' || public.rappel_h(j.debut) || ' · carte ' || coalesce(j.carte, '—')
           || '. Ouvrez « Prochains événements » sur le site pour voir le code et le mot de passe.', j.debut + p.plage, 'j' || j.id
    from j join public.salles s on s.jour_id = j.id, p
   where j.statut = 'prevu' and p.t >= greatest(s.modifie_le + interval '1 minute', j.matin) and p.t < j.debut + p.plage
  union all
  -- Match libre : le matin (ou dès l'annonce si elle est faite après)
  select 'c' || c.id || ':matin', 'tous', null, 'LEAGUE UV — match libre aujourd''hui',
         'Début à ' || public.rappel_h(c.debut) || ' · organisé par ' || c.org || ' · carte au choix de l''organisateur.', c.debut, 'c' || c.id
    from c, p where c.statut = 'annonce' and p.t >= greatest(c.matin, coalesce(c.decide_le, c.cree_le)) and p.t < c.debut - p.al
  union all
  -- Match libre : avant le début
  select 'c' || c.id || ':avant', 'tous', null, 'LEAGUE UV — match libre à ' || public.rappel_h(c.debut),
         'Organisé par ' || c.org || '. Le code de la salle sera sur le site, dans « Prochains événements ».', c.debut + interval '15 minutes', 'c' || c.id
    from c, p where c.statut = 'annonce' and p.t >= c.debut - p.al and p.t < c.debut
  union all
  -- Match libre annulé après un rappel
  select 'c' || c.id || ':annule', 'tous', null, 'LEAGUE UV — match libre annulé',
         'Le match libre de ' || public.rappel_h(c.debut) || ' (organisé par ' || c.org || ') est annulé.', c.debut + p.plage, 'c' || c.id
    from c, p where c.statut = 'annule' and p.t < c.debut + p.plage
     and exists (select 1 from public.rappels_envoyes r where r.cle in ('c' || c.id || ':matin', 'c' || c.id || ':avant'))
  union all
  -- Match libre : code de la salle enregistré
  select 'c' || c.id || ':code:' || floor(extract(epoch from s.modifie_le))::bigint, 'code', null,
         case when exists (select 1 from public.rappels_envoyes r where r.cle like 'c' || c.id || ':code:%')
              then 'LEAGUE UV — code de la salle modifié' else 'LEAGUE UV — code de la salle disponible' end,
         'Match libre de ' || public.rappel_h(c.debut) || ' (organisé par ' || c.org
           || '). Ouvrez « Prochains événements » sur le site pour voir le code et le mot de passe.', c.debut + p.plage, 'c' || c.id
    from c join public.salles s on s.creneau_id = c.id, p
   where c.statut = 'annonce' and p.t >= greatest(s.modifie_le + interval '1 minute', c.matin) and p.t < c.debut + p.plage
  union all
  -- Essai demandé par un membre ou Katana
  select 'essai:' || e.user_id || ':' || floor(extract(epoch from e.demande_le))::bigint, 'essai', e.user_id, 'LEAGUE UV — essai',
         'Les rappels fonctionnent sur ce téléphone.', e.demande_le + interval '1 hour', 'essai'
    from public.rappels_essais e, p where (e.envoye_le is null or e.envoye_le < e.demande_le) and e.demande_le > p.t - interval '1 hour'
)
select * from tout where not exists (select 1 from public.rappels_envoyes r where r.cle = tout.cle)
$$;

-- Personnes qui peuvent recevoir les rappels : membres actifs (suspendus compris) et Katana.
create function public.rappels_autorise(p_user uuid) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admins where user_id = p_user)
          or exists (select 1 from public.membres where user_id = p_user and statut = 'actif' and matricule is not null) $$;

-- =====================================================================
-- Base → fonction « rappels » : réveil chaque minute (pg_cron), seulement s'il y a quelque chose à envoyer
-- =====================================================================
create function public.rappels_reveil() returns text
language plpgsql security definer set search_path = ''
as $$
declare c prive.rappels_config%rowtype;
begin
  select * into c from prive.rappels_config;
  if not found then return 'sans réglage'; end if;
  delete from public.rappels_envoyes where envoye_le < clock_timestamp() - interval '30 days';
  -- Journal de pg_cron (une ligne par minute) : 7 jours gardés ; nettoyé une fois par heure.
  if extract(minute from clock_timestamp())::int = 0 and to_regclass('cron.job_run_details') is not null then
    begin
      execute 'delete from cron.job_run_details where end_time < now() - interval ''7 days''';
    exception when others then null;
    end;
  end if;
  -- Téléphones de personnes qui ne sont plus membres actifs (retrait, exclusion, effacement) : oubliés.
  delete from public.abonnements_push a where not public.rappels_autorise(a.user_id);
  if public.lire_param('rappels_actifs') is distinct from 'true'::jsonb then return 'rappels arrêtés'; end if;
  perform public.calendrier_preparer();
  if c.vapid_public is null then
    -- Clé pas encore créée : un appel toutes les 10 minutes au plus, pour que la fonction la crée.
    if c.dernier_reveil is not null and c.dernier_reveil > clock_timestamp() - interval '10 minutes' then return 'clé en attente'; end if;
  elsif not exists (select 1 from public.rappels_dus()) then
    return 'rien à envoyer';
  end if;
  update prive.rappels_config set dernier_reveil = clock_timestamp();
  perform net.http_post(url := c.url_fonction, body := '{}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-rappels-cle', c.secret),
                        timeout_milliseconds := 30000);
  return 'fonction appelée';
end $$;

-- =====================================================================
-- Fonction « rappels » (rôle serveur seulement)
-- =====================================================================
create function public.rappels_config() returns jsonb
language sql stable security definer set search_path = ''
as $$ select jsonb_build_object('secret', secret, 'sujet', sujet, 'vapid_public', vapid_public, 'vapid_prive', vapid_prive) from prive.rappels_config $$;

-- Clé des notifications : enregistrée une seule fois (si deux appels la créent en même temps, la première gagne).
create function public.rappels_enregistrer_cles(p_publique text, p_prive text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  if coalesce(p_publique, '') !~ '^[A-Za-z0-9_-]{80,100}$' or coalesce(p_prive, '') = '' then raise exception 'Clé invalide.'; end if;
  update prive.rappels_config set vapid_public = p_publique, vapid_prive = p_prive, cle_le = clock_timestamp() where vapid_public is null;
  return public.rappels_config();
end $$;

-- Prend les rappels à envoyer (notés « envoyés » tout de suite : jamais deux fois) et la liste des téléphones.
create function public.rappels_prendre() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_msgs jsonb; v_abos jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('dfmm_rappels'));
  if public.lire_param('rappels_actifs') is distinct from 'true'::jsonb then
    return jsonb_build_object('messages', '[]'::jsonb, 'abonnements', '[]'::jsonb);
  end if;
  perform public.calendrier_preparer();
  with m as (select * from public.rappels_dus()),
       ins as (insert into public.rappels_envoyes (cle) select m.cle from m on conflict do nothing returning cle)
  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) into v_msgs from m where m.cle in (select cle from ins);
  update public.rappels_essais e set envoye_le = clock_timestamp()
   where exists (select 1 from jsonb_array_elements(v_msgs) x where x->>'cible' = 'essai' and (x->>'user_id')::uuid = e.user_id);
  if jsonb_array_length(v_msgs) = 0 then return jsonb_build_object('messages', v_msgs, 'abonnements', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'user_id', a.user_id, 'endpoint', a.endpoint, 'p256dh', a.p256dh, 'auth', a.auth,
           'code', x.adm or (m.id is not null and not public.est_suspendu(m.id, clock_timestamp())))), '[]'::jsonb)
    into v_abos
    from public.abonnements_push a
    cross join lateral (select exists (select 1 from public.admins ad where ad.user_id = a.user_id) adm) x
    left join public.membres m on m.user_id = a.user_id and m.statut = 'actif' and m.matricule is not null
   where x.adm or m.id is not null;
  return jsonb_build_object('messages', v_msgs, 'abonnements', v_abos);
end $$;

-- Résultat des envois : p = {envois: [{id, http}], cles: {cle: nombre}}. 404 et 410 = téléphone désinscrit : oublié.
create function public.rappels_resultats(p jsonb) returns void
language plpgsql security definer set search_path = ''
as $$
declare e jsonb; k text; v_ok int := 0; v_ko int := 0; v_oublies int := 0; v_http int;
begin
  for e in select * from jsonb_array_elements(coalesce(p->'envois', '[]'::jsonb)) loop
    v_http := nullif(e->>'http', '')::int;
    if v_http between 200 and 299 then
      v_ok := v_ok + 1;
      update public.abonnements_push set dernier_envoi = clock_timestamp(), echecs = 0, derniere_erreur = null where id = (e->>'id')::bigint;
    elsif v_http in (404, 410) then
      v_oublies := v_oublies + 1;
      delete from public.abonnements_push where id = (e->>'id')::bigint;
    else
      v_ko := v_ko + 1;
      update public.abonnements_push set echecs = echecs + 1, derniere_erreur = left(coalesce(v_http::text, 'pas de réponse'), 100)
       where id = (e->>'id')::bigint;
    end if;
  end loop;
  -- Téléphone en échec 20 fois de suite : oublié.
  delete from public.abonnements_push where echecs >= 20;
  for k in select jsonb_object_keys(coalesce(p->'cles', '{}'::jsonb)) loop
    update public.rappels_envoyes set destinataires = (p->'cles'->>k)::int where cle = k;
  end loop;
  update prive.rappels_config set dernier_envoi = clock_timestamp(),
         dernier_bilan = jsonb_build_object('le', clock_timestamp(), 'envoyes', v_ok, 'echecs', v_ko, 'oublies', v_oublies,
                                            'messages', (select count(*) from jsonb_object_keys(coalesce(p->'cles', '{}'::jsonb))));
end $$;

-- =====================================================================
-- Membres et Katana (personnes connectées)
-- =====================================================================
create function public.rappels_moi() returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'peut', public.rappels_autorise((select auth.uid())),
    'actifs', public.lire_param('rappels_actifs') = 'true'::jsonb,
    'cle_publique', (select vapid_public from prive.rappels_config),
    'telephones', (select count(*) from public.abonnements_push where user_id = (select auth.uid())))
$$;

-- Inscrire ce téléphone : p = {endpoint, p256dh, auth} (donnés par le navigateur). 5 téléphones au plus par personne.
create function public.abonner_rappels(p jsonb) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_u uuid := (select auth.uid()); v_e text := trim(coalesce(p->>'endpoint', '')); v_k text := trim(coalesce(p->>'p256dh', '')); v_a text := trim(coalesce(p->>'auth', ''));
begin
  if v_u is null or not public.rappels_autorise(v_u) then raise exception 'Les rappels sont réservés aux membres actifs.'; end if;
  if v_e !~ '^https://[^\s]+$' or length(v_e) > 1000 then raise exception 'Adresse de notification invalide.'; end if;
  if v_k !~ '^[A-Za-z0-9_=-]{80,100}$' or v_a !~ '^[A-Za-z0-9_=-]{16,30}$' then raise exception 'Clé de notification invalide.'; end if;
  insert into public.abonnements_push (user_id, endpoint, p256dh, auth) values (v_u, v_e, v_k, v_a)
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
     vu_le = clock_timestamp(), echecs = 0, derniere_erreur = null;
  delete from public.abonnements_push where user_id = v_u and id not in
    (select id from public.abonnements_push where user_id = v_u order by vu_le desc, id desc limit 5);
end $$;

create function public.desabonner_rappels(p_endpoint text) returns void
language sql security definer set search_path = ''
as $$ delete from public.abonnements_push where endpoint = p_endpoint and user_id = (select auth.uid()) $$;

create function public.essai_rappel() returns void
language plpgsql security definer set search_path = ''
as $$
declare v_u uuid := (select auth.uid());
begin
  if v_u is null or not public.rappels_autorise(v_u) then raise exception 'Les rappels sont réservés aux membres actifs.'; end if;
  if public.lire_param('rappels_actifs') is distinct from 'true'::jsonb then raise exception 'Les rappels sont arrêtés pour le moment.'; end if;
  if not exists (select 1 from public.abonnements_push where user_id = v_u) then raise exception 'Activez d''abord les rappels sur ce téléphone.'; end if;
  insert into public.rappels_essais (user_id) values (v_u)
  on conflict (user_id) do update set demande_le = clock_timestamp()
   where public.rappels_essais.demande_le < clock_timestamp() - interval '5 minutes';
  if not found then raise exception 'Un essai a déjà été demandé il y a moins de 5 minutes.'; end if;
end $$;

-- Katana : état des rappels (nombres seulement).
create function public.rappels_admin() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare c prive.rappels_config%rowtype; v_tache boolean := false;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into c from prive.rappels_config;
  if to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''dfmm-rappels'' and active)' into v_tache;
  end if;
  return jsonb_build_object(
    'actifs', public.lire_param('rappels_actifs') = 'true'::jsonb,
    'tache', v_tache,
    'cle_prete', c.vapid_public is not null,
    'telephones', (select count(*) from public.abonnements_push),
    'personnes', (select count(distinct user_id) from public.abonnements_push),
    'en_echec', (select count(*) from public.abonnements_push where echecs > 0),
    'dernier_reveil', c.dernier_reveil, 'dernier_envoi', c.dernier_envoi, 'dernier_bilan', c.dernier_bilan,
    'envoyes_7j', (select count(*) from public.rappels_envoyes where envoye_le > clock_timestamp() - interval '7 days'));
end $$;

-- =====================================================================
-- Droits
-- =====================================================================
alter table public.abonnements_push enable row level security;
alter table public.rappels_envoyes enable row level security;
alter table public.rappels_essais enable row level security;
revoke all on public.abonnements_push, public.rappels_envoyes, public.rappels_essais from anon, authenticated;
-- Lecture directe par l'administrateur seulement (sauvegarde) ; les membres passent par les fonctions.
grant select on public.abonnements_push, public.rappels_envoyes, public.rappels_essais to authenticated;
create policy "admin lit" on public.abonnements_push for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.rappels_envoyes for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.rappels_essais for select to authenticated using ((select public.est_admin()));
grant select, insert, update, delete on public.abonnements_push, public.rappels_envoyes, public.rappels_essais to service_role;

revoke all on function public.rappel_matin(date), public.rappel_min(text, int), public.rappels_dus(), public.rappels_autorise(uuid),
  public.rappels_reveil(), public.rappels_config(), public.rappels_enregistrer_cles(text, text), public.rappels_prendre(),
  public.rappels_resultats(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.rappels_config(), public.rappels_enregistrer_cles(text, text), public.rappels_prendre(),
  public.rappels_resultats(jsonb) to service_role;
revoke all on function public.rappels_moi(), public.abonner_rappels(jsonb), public.desabonner_rappels(text), public.essai_rappel(),
  public.rappels_admin() from public, anon;
grant execute on function public.rappels_moi(), public.abonner_rappels(jsonb), public.desabonner_rappels(text), public.essai_rappel(),
  public.rappels_admin() to authenticated;

-- ---------- Extensions de Supabase et tâche de chaque minute (absentes de la base locale de test) ----------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net with schema extensions;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('dfmm-rappels', '* * * * *', 'select public.rappels_reveil()');
  end if;
end $$;

commit;
