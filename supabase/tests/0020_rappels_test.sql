-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0020 (rappels sur les téléphones)
-- À exécuter APRÈS la migration 0020. Faux membres seulement (anciens matricules fictifs 99201 à 99203),
-- fausse saison, faux calendrier, faux matchs libres, faux téléphones (adresses @test.invalid).
-- Aucune notification n'est envoyée : tout est annulé à la fin (les appels réseau de la base ne partent
-- qu'après validation, qui n'a jamais lieu ici).
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;
create temp table lot (n int primary key, j jsonb);
grant all on lot to anon, authenticated, service_role;

-- Base locale seulement : imitation de pg_net (sur Supabase, la vraie fonction existe).
do $$
begin
  if to_regnamespace('net') is null then
    create schema net;
    create table net.appels (url text, headers jsonb);
    create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
      headers jsonb default '{}'::jsonb, timeout_milliseconds int default 2000) returns bigint
    language sql as $f$ insert into net.appels values (url, headers); select 1::bigint $f$;
  end if;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000c2', 'faux.admin20@test.invalid'),
  ('00000000-0000-4000-8000-0000000020a1', 'faux.20a@test.invalid'),
  ('00000000-0000-4000-8000-0000000020b1', 'faux.20b@test.invalid'),
  ('00000000-0000-4000-8000-0000000020c1', 'faux.20c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000000c2') on conflict do nothing;
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values
  (99201, 'Faux 20A', '2026-11-18'), (99202, 'Faux 20B', '2026-11-18'), (99203, 'Faux 20C', '2026-11-18');

set local role service_role;
do $$
declare k text;
begin
  foreach k in array array['a', 'b', 'c'] loop
    insert into ids select upper(k), public.creer_inscription(jsonb_build_object('user_id', '00000000-0000-4000-8000-0000000020' || k || '1',
      'nom_gamer', 'Faux 20' || upper(k), 'email', '20' || k || '@x', 'facebook', 'fb/20' || k, 'pseudo', 'Vingt ' || upper(k),
      'uid', '99200' || ascii(k), 'empreinte_email', 'e20' || k, 'empreinte_facebook', 'f20' || k, 'residence', 'Madagascar',
      'comprend_mg', true, 'parle_mg', true, 'origine_mg', true));
  end loop;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c2"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c2', true);
set local role authenticated;
do $$
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99201);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99202);
  perform public.decider_inscription((select id from ids where nom = 'C'), 'approuver', null, 99203);
end $$;
reset role;

-- ---------- Préparation (rôle propriétaire) : A actif, B suspendu, C exclu ; faux calendrier et matchs libres ----------
-- Matin du match à 00:00 le temps du test (pour ne pas dépendre de l'heure à laquelle le test est lancé).
do $$
declare td date := (clock_timestamp() at time zone 'Indian/Antananarivo')::date; s bigint; x bigint; t timestamptz := clock_timestamp();
begin
  insert into ids select 'mA', id from public.membres where matricule = 99201;
  insert into ids select 'mB', id from public.membres where matricule = 99202;
  insert into ids select 'mC', id from public.membres where matricule = 99203;
  insert into public.sanctions (membre_id, type, motif, debut, fin, recours_jusqu)
  values ((select id from ids where nom = 'mB'), 'suspension', 'Test 0020', t - interval '1 day', t + interval '5 days', t + interval '1 day');
  update public.membres set statut = 'exclu' where id = (select id from ids where nom = 'mC');
  update public.parametres set valeur = '"00:00"' where cle = 'rappel_matin_heure';
  update public.parametres set valeur = '1' where cle = 'calendrier_dates_affichees';
  update public.parametres set valeur = 'true' where cle = 'rappels_actifs';
  update prive.rappels_config set vapid_public = null, vapid_prive = null, dernier_reveil = null;
  delete from public.rappels_envoyes;
  delete from public.rappels_essais;
  -- Faux calendrier : les dates sans match saisi sont retirées le temps du test.
  delete from public.jours_match j where not exists (select 1 from public.matchs mt where mt.jour_id = j.id);
  -- J1 : dans 2 h (rappel du matin) ; J2 : dans 20 min (rappel d'avant) ; J3 : annulé, dans 1 h ;
  -- J4 : dans 2 h mais le matin de sa date n'est pas encore arrivé (rien) ; J5 : reporté, matin pas encore arrivé (rien).
  insert into public.jours_match (jour, debut, carte) values (td - 40, t + interval '2 hours', 'Ascension') returning id into x; insert into ids values ('J1', x);
  insert into public.jours_match (jour, debut, carte) values (td - 39, t + interval '20 minutes', 'Faille') returning id into x; insert into ids values ('J2', x);
  insert into public.jours_match (jour, debut, carte, statut, motif) values (td - 38, t + interval '1 hour', null, 'annule', 'Test') returning id into x; insert into ids values ('J3', x);
  insert into public.jours_match (jour, debut, carte) values (td + 40, t + interval '2 hours', 'Craqué') returning id into x; insert into ids values ('J4', x);
  insert into public.jours_match (jour, debut, carte, statut) values (td + 41, t + interval '3 hours', 'Craqué', 'reporte') returning id into x; insert into ids values ('J5', x);
  -- Code de J1 enregistré il y a 2 min (envoyé) ; code de J2 à l'instant (attend 1 min).
  insert into public.salles (jour_id, code, mot_de_passe, modifie_le) values ((select id from ids where nom = 'J1'), 'CODE-SECRET-123', 'MDP-SECRET-456', t - interval '2 minutes');
  insert into public.salles (jour_id, code, mot_de_passe, modifie_le) values ((select id from ids where nom = 'J2'), 'CODE-SECRET-789', 'MDP-SECRET-000', t);
  insert into public.saisons (nom, debut, fin) values ('Saison test 0020', td - 60, td + 60) returning id into s;
  -- C1 : match libre annoncé dans 40 min ; C2 : annulé après un rappel ; C3 : annulé sans rappel ; C4 : retenu.
  insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut, cree_le)
  values (s, (select id from ids where nom = 'mA'), (select id from ids where nom = 'mA'), (select id from ids where nom = 'mB'), t + interval '40 minutes', t - interval '1 hour')
  returning id into x; insert into ids values ('C1', x);
  insert into public.salles (creneau_id, code, mot_de_passe, saisi_par, modifie_le) values (x, 'LIBRE-SECRET-1', 'LIBRE-MDP-1', (select id from ids where nom = 'mA'), t - interval '5 minutes');
  insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut, statut, annule_par)
  values (s, (select id from ids where nom = 'mA'), (select id from ids where nom = 'mA'), (select id from ids where nom = 'mB'), t + interval '50 minutes', 'annule', 'organisateur')
  returning id into x; insert into ids values ('C2', x);
  insert into public.rappels_envoyes (cle) values ('c' || x || ':matin');
  insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut, statut, annule_par)
  values (s, (select id from ids where nom = 'mA'), (select id from ids where nom = 'mA'), (select id from ids where nom = 'mB'), t + interval '50 minutes', 'annule', 'organisateur')
  returning id into x; insert into ids values ('C3', x);
  insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut, statut)
  values (s, (select id from ids where nom = 'mA'), (select id from ids where nom = 'mA'), (select id from ids where nom = 'mB'), t + interval '50 minutes', 'retenu')
  returning id into x; insert into ids values ('C4', x);
end $$;

-- ---------- 1. Réglages et schéma privé ----------
do $$
declare n int; v text;
begin
  select count(*), string_agg(cle, ', ' order by ordre) into n, v from public.parametres where section = 'Rappels';
  insert into resultats (test, ok, detail) values ('4 réglages Rappels', n = 4, v);
  select valeur::text into v from public.parametres where cle = 'rappel_avant_katana_min';
  insert into resultats (test, ok, detail) values ('Rappel 35 min avant un match du calendrier (15 h 30 pour 16 h 05)', v = '35', v);
  select count(*) into n from prive.rappels_config where length(secret) = 64 and url_fonction like 'https://%/functions/v1/rappels';
  insert into resultats (test, ok, detail) values ('Mot de passe base ↔ fonction créé (64 caractères) et adresse de la fonction', n = 1, n || '');
end $$;

set local role anon;
do $$
declare ok boolean := false;
begin
  begin perform 1 from prive.rappels_config; exception when insufficient_privilege then ok := true; end;
  insert into resultats (test, ok, detail) values ('Visiteur : schéma privé illisible', ok, '');
  ok := false;
  begin perform public.rappels_moi(); exception when insufficient_privilege then ok := true; end;
  insert into resultats (test, ok, detail) values ('Visiteur : rappels_moi refusé', ok, '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000020a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000020a1', true);
set local role authenticated;
do $$
declare ok boolean := false; n int; r jsonb;
begin
  begin perform 1 from prive.rappels_config; exception when insufficient_privilege then ok := true; end;
  insert into resultats (test, ok, detail) values ('Membre : schéma privé illisible (clé et mot de passe)', ok, '');
  ok := false;
  begin perform public.rappels_config(); exception when insufficient_privilege then ok := true; end;
  insert into resultats (test, ok, detail) values ('Membre : rappels_config refusé', ok, '');
  ok := false;
  begin perform public.rappels_prendre(); exception when insufficient_privilege then ok := true; end;
  insert into resultats (test, ok, detail) values ('Membre : rappels_prendre refusé', ok, '');
  ok := false;
  begin perform public.rappels_admin(); exception when others then ok := sqlerrm like '%administrateur%'; end;
  insert into resultats (test, ok, detail) values ('Membre : état des rappels de Katana refusé', ok, '');
  -- ---------- 2. Inscription du téléphone ----------
  r := public.rappels_moi();
  insert into resultats (test, ok, detail) values ('A (actif) : peut recevoir les rappels, 0 téléphone, clé pas encore créée',
    (r->>'peut')::boolean and (r->>'telephones')::int = 0 and r->>'cle_publique' is null, r::text);
  perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/a1', 'p256dh', repeat('A', 87), 'auth', repeat('a', 22)));
  select count(*) into n from public.abonnements_push;
  insert into resultats (test, ok, detail) values ('A : téléphone inscrit (et ne lit pas directement la table)', (public.rappels_moi()->>'telephones')::int = 1 and n = 0, n || ' ligne(s) lue(s)');
  perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/a1', 'p256dh', repeat('B', 87), 'auth', repeat('b', 22)));
  insert into resultats (test, ok, detail) values ('A : même téléphone réinscrit = mis à jour, pas en double', (public.rappels_moi()->>'telephones')::int = 1, '');
  ok := false;
  begin perform public.abonner_rappels(jsonb_build_object('endpoint', 'http://pas-https', 'p256dh', repeat('A', 87), 'auth', repeat('a', 22)));
  exception when others then ok := sqlerrm like '%invalide%'; end;
  insert into resultats (test, ok, detail) values ('Adresse non https refusée', ok, '');
  ok := false;
  begin perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/x', 'p256dh', 'court', 'auth', repeat('a', 22)));
  exception when others then ok := sqlerrm like '%invalide%'; end;
  insert into resultats (test, ok, detail) values ('Clé de téléphone invalide refusée', ok, '');
  for n in 2..7 loop
    perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/a' || n, 'p256dh', repeat('A', 87), 'auth', repeat('a', 22)));
  end loop;
  insert into resultats (test, ok, detail) values ('5 téléphones au plus par personne', (public.rappels_moi()->>'telephones')::int = 5, public.rappels_moi()->>'telephones');
  perform public.desabonner_rappels('https://push.test.invalid/a7');
  perform public.desabonner_rappels('https://push.test.invalid/a6');
  perform public.desabonner_rappels('https://push.test.invalid/a5');
  perform public.desabonner_rappels('https://push.test.invalid/a4');
  insert into resultats (test, ok, detail) values ('« Arrêter les rappels » : téléphone retiré ; les plus anciens ont été remplacés', (public.rappels_moi()->>'telephones')::int = 1 and not exists (select 1 from public.rappels_essais), public.rappels_moi()->>'telephones');
  perform public.essai_rappel();
  ok := false;
  begin perform public.essai_rappel(); exception when others then ok := sqlerrm like '%5 minutes%'; end;
  insert into resultats (test, ok, detail) values ('Essai : un seul toutes les 5 minutes', ok, '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000020b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000020b1', true);
set local role authenticated;
do $$
begin
  perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/b1', 'p256dh', repeat('C', 87), 'auth', repeat('c', 22)));
  insert into resultats (test, ok, detail) values ('B (suspendu) : peut s''inscrire aux rappels (choix 2a)', (public.rappels_moi()->>'telephones')::int = 1, '');
  begin
    perform public.desabonner_rappels('https://push.test.invalid/a3');  -- B ne peut pas retirer le téléphone de A
  end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000020c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000020c1', true);
set local role authenticated;
do $$
declare ok boolean := false;
begin
  begin perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/c1', 'p256dh', repeat('D', 87), 'auth', repeat('d', 22)));
  exception when others then ok := sqlerrm like '%membres actifs%'; end;
  insert into resultats (test, ok, detail) values ('C (exclu) : inscription aux rappels refusée', ok, '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c2"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c2', true);
set local role authenticated;
do $$
declare r jsonb;
begin
  perform public.abonner_rappels(jsonb_build_object('endpoint', 'https://push.test.invalid/k1', 'p256dh', repeat('E', 87), 'auth', repeat('e', 22)));
  r := public.rappels_admin();
  insert into resultats (test, ok, detail) values ('Katana : état des rappels (3 téléphones, 3 personnes, clé pas prête)',
    (r->>'telephones')::int = 3 and (r->>'personnes')::int = 3 and not (r->>'cle_prete')::boolean, r::text);
end $$;
reset role;

-- Téléphone d'un exclu glissé directement (cas d'un membre exclu après son inscription).
insert into public.abonnements_push (user_id, endpoint, p256dh, auth)
values ('00000000-0000-4000-8000-0000000020c1', 'https://push.test.invalid/c-ancien', repeat('F', 87), repeat('f', 22));

-- ---------- 3. Rappels à envoyer ----------
do $$
declare n int; v text; tous text; j1 bigint := (select id from ids where nom = 'J1'); j2 bigint := (select id from ids where nom = 'J2');
        j3 bigint := (select id from ids where nom = 'J3'); c1 bigint := (select id from ids where nom = 'C1'); c2 bigint := (select id from ids where nom = 'C2');
        meme_jour boolean := ((clock_timestamp() + interval '40 minutes') at time zone 'Indian/Antananarivo')::date = (clock_timestamp() at time zone 'Indian/Antananarivo')::date;
begin
  select string_agg(cle, ' ' order by cle) into tous from public.rappels_dus();
  select texte into v from public.rappels_dus() where cle = 'j' || j1 || ':matin';
  insert into resultats (test, ok, detail) values ('Match du calendrier : rappel du matin (heure, carte, salle ouverte)',
    v like 'Début à % · carte Ascension · salle ouverte à %', coalesce(v, 'absent'));
  insert into resultats (test, ok, detail) values ('Pas de rappel « avant » trop tôt (match dans 2 h)', tous not like '%j' || j1 || ':avant%', tous);
  select titre || ' / ' || texte into v from public.rappels_dus() where cle = 'j' || j2 || ':avant';
  insert into resultats (test, ok, detail) values ('Match du calendrier : rappel 35 min avant (carte Faille)', v like 'LEAGUE UV — match à % / Carte Faille%', coalesce(v, 'absent'));
  insert into resultats (test, ok, detail) values ('Pas de rappel du matin quand l''heure du rappel d''avant est passée', tous not like '%j' || j2 || ':matin%', tous);
  select titre into v from public.rappels_dus() where cle = 'j' || j3 || ':annule';
  insert into resultats (test, ok, detail) values ('Date annulée : avis le jour du match', v = 'LEAGUE UV — match annulé', coalesce(v, 'absent'));
  insert into resultats (test, ok, detail) values ('Rien avant le matin du jour du match (J4 et J5 reporté)',
    tous not like '%j' || (select id from ids where nom = 'J4') || ':%' and tous not like '%j' || (select id from ids where nom = 'J5') || ':%', tous);
  select count(*), max(cible) into n, v from public.rappels_dus() where cle like 'j' || j1 || ':code:%';
  insert into resultats (test, ok, detail) values ('Code de la salle enregistré : avis « code disponible » réservé aux membres actifs non suspendus', n = 1 and v = 'code', n || ' ' || coalesce(v, ''));
  select count(*) into n from public.rappels_dus() where cle like 'j' || j2 || ':code:%';
  insert into resultats (test, ok, detail) values ('Code saisi à l''instant : attend 1 minute (correction possible)', n = 0, n || '');
  select count(*) into n from public.rappels_dus() where titre || texte ~ 'SECRET|MDP';
  insert into resultats (test, ok, detail) values ('Choix 3a : le code et le mot de passe ne sont JAMAIS dans une notification', n = 0, n || '');
  select texte into v from public.rappels_dus() where cle = 'c' || c1 || ':matin';
  insert into resultats (test, ok, detail) values ('Match libre : rappel du jour (heure, organisateur)',
    case when meme_jour then v like 'Début à % · organisé par Faux 20A%' else true end, coalesce(v, 'absent') || case when meme_jour then '' else ' (après 23 h 20 : non vérifié)' end);
  select count(*) into n from public.rappels_dus() where cle like 'c' || c1 || ':code:%' and cible = 'code';
  insert into resultats (test, ok, detail) values ('Match libre : avis « code disponible »', n = 1, n || '');
  insert into resultats (test, ok, detail) values ('Match libre annulé après un rappel : avis', tous like '%c' || c2 || ':annule%', tous);
  insert into resultats (test, ok, detail) values ('Match libre annulé sans rappel, ou retenu : rien',
    tous not like '%c' || (select id from ids where nom = 'C3') || ':%' and tous not like '%c' || (select id from ids where nom = 'C4') || ':%', tous);
  select count(*) into n from public.rappels_dus() where cible = 'essai' and user_id = '00000000-0000-4000-8000-0000000020a1';
  insert into resultats (test, ok, detail) values ('Essai demandé par A : à envoyer à ses téléphones seulement', n = 1, n || '');
end $$;

-- ---------- 4. Réveil par la base (clé pas encore créée) ----------
do $$
declare v text;
begin
  v := public.rappels_reveil();
  insert into resultats (test, ok, detail) values ('Réveil : appelle la fonction pour créer la clé', v = 'fonction appelée', v);
  v := public.rappels_reveil();
  insert into resultats (test, ok, detail) values ('Réveil : clé en attente, pas d''autre appel avant 10 min', v = 'clé en attente', v);
  insert into resultats (test, ok, detail) values ('Réveil : téléphone d''un exclu oublié',
    not exists (select 1 from public.abonnements_push where endpoint = 'https://push.test.invalid/c-ancien'), '');
end $$;

-- ---------- 5. Fonction « rappels » (rôle serveur) ----------
set local role service_role;
do $$
declare r jsonb; ok boolean := false; abos jsonb;
begin
  begin perform public.rappels_enregistrer_cles('court', '{}'); exception when others then ok := sqlerrm like '%invalide%'; end;
  insert into resultats (test, ok, detail) values ('Clé invalide refusée', ok, '');
  r := public.rappels_enregistrer_cles(repeat('K', 87), '{"kty":"EC"}');
  r := public.rappels_enregistrer_cles(repeat('Z', 87), '{"kty":"EC","autre":1}');
  insert into resultats (test, ok, detail) values ('Clé enregistrée une seule fois (la première gagne)', r->>'vapid_public' = repeat('K', 87), left(r->>'vapid_public', 3));
  r := public.rappels_prendre();
  insert into lot values (1, r);
  abos := r->'abonnements';
  insert into resultats (test, ok, detail) values ('Lot : 7 rappels pris (J1 matin et code, J2 avant, J3 annulé, C1 code, C2 annulé, essai ; + C1 matin si même jour)',
    jsonb_array_length(r->'messages') between 7 and 8, jsonb_array_length(r->'messages') || '');
  insert into resultats (test, ok, detail) values ('Lot : 3 téléphones (A, B suspendu, Katana), pas l''exclu',
    jsonb_array_length(abos) = 3, jsonb_array_length(abos) || '');
  insert into resultats (test, ok, detail) values ('« Code » : A et Katana oui, B suspendu non',
    (select bool_and(case when x->>'endpoint' like '%/b1' then not (x->>'code')::boolean else (x->>'code')::boolean end) from jsonb_array_elements(abos) x), abos::text);
  r := public.rappels_prendre();
  insert into resultats (test, ok, detail) values ('Jamais deux fois le même rappel', jsonb_array_length(r->'messages') = 0, jsonb_array_length(r->'messages') || '');
  -- Résultats : A 201, B 410 (désinscrit), Katana 500.
  perform public.rappels_resultats(jsonb_build_object('envois', (select jsonb_agg(jsonb_build_object('id', x->>'id',
      'http', case when x->>'endpoint' like '%/a3' then 201 when x->>'endpoint' like '%/b1' then 410 else 500 end)) from jsonb_array_elements(abos) x),
    'cles', jsonb_build_object((select x->>'cle' from lot, jsonb_array_elements(lot.j->'messages') x limit 1), 3)));
end $$;
reset role;

do $$
declare n int;
begin
  select count(*) into n from public.abonnements_push where endpoint like 'https://push.test.invalid/%';
  insert into resultats (test, ok, detail) values ('Téléphone désinscrit (410) oublié', n = 2 and not exists (select 1 from public.abonnements_push where endpoint like '%/b1'), n || '');
  insert into resultats (test, ok, detail) values ('Envoi réussi noté, échec compté',
    exists (select 1 from public.abonnements_push where endpoint like '%/a3' and dernier_envoi is not null and echecs = 0)
    and exists (select 1 from public.abonnements_push where endpoint like '%/k1' and echecs = 1), '');
  insert into resultats (test, ok, detail) values ('Bilan du dernier envoi (1 envoyé, 1 échec, 1 oublié)',
    (select dernier_bilan->>'envoyes' = '1' and dernier_bilan->>'echecs' = '1' and dernier_bilan->>'oublies' = '1' from prive.rappels_config), (select dernier_bilan::text from prive.rappels_config));
  insert into resultats (test, ok, detail) values ('Essai marqué envoyé', exists (select 1 from public.rappels_essais where envoye_le is not null), '');
  -- Réveil après coup : rien à envoyer, puis rappels arrêtés.
  insert into resultats (test, ok, detail) values ('Réveil : rien à envoyer (pas d''appel inutile)', public.rappels_reveil() = 'rien à envoyer', '');
  update public.parametres set valeur = 'false' where cle = 'rappels_actifs';
  insert into resultats (test, ok, detail) values ('Réglage « rappels_actifs » à non : rien n''est envoyé',
    public.rappels_reveil() = 'rappels arrêtés' and jsonb_array_length((select public.rappels_prendre())->'messages') = 0, '');
  update public.parametres set valeur = 'true' where cle = 'rappels_actifs';
  -- Tâche de chaque minute (vrai projet seulement).
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname = ''dfmm-rappels'' and schedule = ''* * * * *'' and active' into n;
    insert into resultats (test, ok, detail) values ('Tâche « dfmm-rappels » programmée chaque minute', n = 1, n || '');
  else
    insert into resultats (test, ok, detail) values ('Tâche « dfmm-rappels » (base locale sans pg_cron : non vérifiée)', true, 'base locale');
  end if;
end $$;

-- ---------- Résultat (tout est annulé) ----------
do $$
declare total int; echecs int; liste text;
begin
  select count(*), count(*) filter (where not ok) into total, echecs from resultats;
  select string_agg(n || '. ' || test || ' (' || detail || ')', ' | ' order by n) into liste from resultats where not ok;
  raise exception 'FIN DU TEST : % réussi(s) sur %. % Rien n''a été gardé dans la base (ce message apparaît comme une erreur exprès, pour tout annuler).',
    total - echecs, total, case when echecs = 0 then 'Tout est bon.' else 'ÉCHECS : ' || liste || '.' end;
end $$;
