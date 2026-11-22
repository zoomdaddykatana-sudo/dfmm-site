-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0013 (matchs libres)
-- À exécuter APRÈS la migration 0013. Faux membres seulement (anciens matricules fictifs 99081 à 99084),
-- fausse saison (rendue active le temps du test), fausses sanctions, faux matchs, faux fichiers. Les
-- matchs libres sont ouverts le temps du test seulement. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000d1', 'faux.13k@test.invalid'),
  ('00000000-0000-4000-8000-0000000013a1', 'faux.13a@test.invalid'),
  ('00000000-0000-4000-8000-0000000013b1', 'faux.13b@test.invalid'),
  ('00000000-0000-4000-8000-0000000013c1', 'faux.13c@test.invalid'),
  ('00000000-0000-4000-8000-0000000013d1', 'faux.13d@test.invalid'),
  ('00000000-0000-4000-8000-0000000013e1', 'faux.13e@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000000d1');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values
  (99081, 'Faux 13A', '2026-11-18'), (99082, 'Faux 13B', '2026-11-18'), (99083, 'Faux 13C', '2026-11-18'), (99084, 'Faux 13D', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000013a1','nom_gamer','Faux 13A','email','13a@x','facebook','fb/13a','pseudo','Treize A','uid','9913001','empreinte_email','e13a','empreinte_facebook','f13a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000013b1','nom_gamer','Faux 13B','email','13b@x','facebook','fb/13b','pseudo','Treize B','uid','9913002','empreinte_email','e13b','empreinte_facebook','f13b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'C', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000013c1','nom_gamer','Faux 13C','email','13c@x','facebook','fb/13c','pseudo','Treize C','uid','9913003','empreinte_email','e13c','empreinte_facebook','f13c','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'D', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000013d1','nom_gamer','Faux 13D','email','13d@x','facebook','fb/13d','pseudo','Treize D','uid','9913004','empreinte_email','e13d','empreinte_facebook','f13d','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;

-- ---------- Préparation par Katana : approbations, saison de test, sanctions ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99081);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99082);
  perform public.decider_inscription((select id from ids where nom = 'C'), 'approuver', null, 99083);
  perform public.decider_inscription((select id from ids where nom = 'D'), 'approuver', null, 99084);
  insert into public.saisons (nom, debut, fin) values ('Saison test 0013', current_date - 10, current_date + 60) returning id into x;
  insert into ids values ('S', x);
  perform public.activer_saison(x);
  -- C : capture falsifiée dans la saison (avertissement noté dans cette catégorie) ; D : suspendu.
  perform public.sanctionner(jsonb_build_object('membre_id', (select id from ids where nom = 'C'), 'type', 'avertissement', 'motif', 'Test 0013', 'categorie', 'Capture falsifiée'));
  perform public.sanctionner(jsonb_build_object('membre_id', (select id from ids where nom = 'D'), 'type', 'suspension', 'motif', 'Test 0013',
    'fin_jour', to_char((clock_timestamp() at time zone 'Indian/Antananarivo')::date + 3, 'YYYY-MM-DD')));
end $$;
reset role;

-- ---------- Déclaration ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013a1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin perform public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99081, 'resp_gti', 99082));
    insert into resultats (test, ok, detail) values ('Matchs libres fermés : déclaration refusée', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Matchs libres fermés : déclaration refusée', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  update public.parametres set valeur = 'true' where cle = 'matchs_libres_ouverts';
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013a1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin perform public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99081, 'resp_gti', 99082));
    insert into resultats (test, ok, detail) values ('Déclaration moins de 2 h avant : refusée', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Déclaration moins de 2 h avant : refusée', true, sqlerrm); end;
  begin perform public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99081, 'resp_gti', 99999));
    insert into resultats (test, ok, detail) values ('Responsable inconnu : refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Responsable inconnu : refusé', true, sqlerrm); end;
  j := public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99081, 'resp_gti', 99082));
  insert into ids values ('L1', (j->>'id')::bigint), ('M1', (j->>'match')::bigint);
  insert into resultats (test, ok, detail) values ('Déclaration valide : match libre annoncé', j->>'statut' = 'annonce' and j->>'match' is not null, j::text);
  j := public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '5 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99082, 'resp_gti', 99081));
  insert into ids values ('L2', (j->>'id')::bigint);
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013c1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  j := public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99081, 'resp_gti', 99082));
  insert into ids values ('L3', (j->>'id')::bigint);
  insert into resultats (test, ok, detail) values ('Organisateur interdit après capture falsifiée : demande retenue, champ signalé', j->>'statut' = 'retenu' and j->'champs' ? 'organisateur' and j->>'match' is null, j::text);
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013b1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  j := public.declarer_match_libre(jsonb_build_object('debut', to_char(clock_timestamp() + interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'resp_haavk', 99082, 'resp_gti', 99084));
  insert into ids values ('L4', (j->>'id')::bigint);
  insert into resultats (test, ok, detail) values ('Responsable suspendu : demande retenue, seul ce champ signalé', j->>'statut' = 'retenu' and j->'champs' = '["resp_gti"]'::jsonb, j::text);
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  select count(*) into n from public.matchs where id = (select id from ids where nom = 'M1') and type = 'libre' and statut = 'brouillon' and creneau_id = (select id from ids where nom = 'L1');
  insert into resultats (test, ok, detail) values ('Un créneau = un match libre en brouillon', n = 1, n || '');
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'B') and texte like 'Vous êtes responsable GTI du match libre%';
  insert into resultats (test, ok, detail) values ('Responsable GTI averti', n = 1, n || ' notification(s)');
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'D');
  insert into resultats (test, ok, detail) values ('Responsable suspendu non averti (demande retenue)', n = 1, n || ' notification(s) (la sanction seulement)');
  select count(*) into n from public.journal where type = 'Match libre' and decision like 'Demande retenue%';
  insert into resultats (test, ok, detail) values ('Demandes retenues dans la liste de Katana (journal)', n = 2, n || '');
  select count(*) into n from public.creneaux where vu_le is null;
  insert into resultats (test, ok, detail) values ('Alerte à Katana : créneaux non vus', n = 4, n || '');
  perform public.marquer_creneaux_vus();
  select count(*) into n from public.creneaux where vu_le is null;
  insert into resultats (test, ok, detail) values ('Créneaux vus (les demandes retenues restent à traiter)', n = 2, n || '');
  perform public.decider_creneau((select id from ids where nom = 'L4'), 'refuser', 'Test');
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'B') and texte like '%n''a pas été retenue.' and texte not like '%uspen%';
  insert into resultats (test, ok, detail) values ('Demande refusée : message neutre à l’organisateur', n = 1, n || '');
  perform public.decider_creneau((select id from ids where nom = 'L3'), 'accepter', null);
  select count(*) into n from public.matchs where creneau_id = (select id from ids where nom = 'L3');
  insert into resultats (test, ok, detail) values ('Demande retenue acceptée : match créé', n = 1, n || '');
end $$;
reset role;

-- ---------- Liste des matchs libres ----------
set local role anon;
do $$
declare j jsonb;
begin
  begin j := public.liste_matchs_libres();
    insert into resultats (test, ok, detail) values ('Visiteur : pas de liste des matchs libres', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : pas de liste des matchs libres', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013e1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013e1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin j := public.liste_matchs_libres();
    insert into resultats (test, ok, detail) values ('Compte sans fiche membre : pas de liste', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Compte sans fiche membre : pas de liste', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  j := public.liste_matchs_libres();
  insert into resultats (test, ok, detail) values ('Membre (même suspendu) : voit les 3 matchs annoncés, pas la demande refusée d’un autre', jsonb_array_length(j) = 3, jsonb_array_length(j) || '');
  select count(*) into n from public.creneaux;
  insert into resultats (test, ok, detail) values ('Membre : ne lit pas la table des créneaux', n = 0, n || '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013b1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  j := public.liste_matchs_libres();
  insert into resultats (test, ok, detail) values ('Organisateur : voit aussi sa demande refusée', jsonb_array_length(j) = 4, jsonb_array_length(j) || '');
end $$;
reset role;

-- ---------- Annulation ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013c1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin perform public.annuler_creneau((select id from ids where nom = 'L2'));
    insert into resultats (test, ok, detail) values ('Un autre membre n’annule pas le match', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un autre membre n’annule pas le match', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013a1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  perform public.annuler_creneau((select id from ids where nom = 'L2'), null);
  select count(*) into n from jsonb_array_elements(public.liste_matchs_libres()) e where (e->>'id')::bigint = (select id from ids where nom = 'L2') and e->>'statut' = 'annule' and e->>'match_statut' = 'annule';
  insert into resultats (test, ok, detail) values ('Organisateur : annule avant le début (match annulé aussi)', n = 1, n || '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'B') and texte like '%annulé par l''organisateur.';
  insert into resultats (test, ok, detail) values ('Annulation : responsable averti', n = 1, n || '');
  perform public.annuler_creneau((select id from ids where nom = 'L3'), null);
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'C') and texte like '%annulé par Katana.';
  insert into resultats (test, ok, detail) values ('Katana annule sans motif : organisateur averti', n = 1, n || '');
end $$;
reset role;

-- ---------- Captures des responsables ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013b1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-0.jpg');
    insert into resultats (test, ok, detail) values ('Avant l’heure de début : dépôt refusé', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Avant l’heure de début : dépôt refusé', true, sqlerrm); end;
end $$;
reset role;

update public.creneaux set debut = clock_timestamp() - interval '20 minutes' where id = (select id from ids where nom = 'L1');  -- le match a commencé (test)

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013c1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'C') || '-1.jpg');
    insert into resultats (test, ok, detail) values ('Membre non responsable : dépôt refusé', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre non responsable : dépôt refusé', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013b1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'A') || '-1.jpg');
    insert into resultats (test, ok, detail) values ('Dépôt au nom d’un autre membre : refusé', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Dépôt au nom d’un autre membre : refusé', true, sqlerrm); end;
  insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-1.jpg');
  x := public.envoyer_capture((select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-1.jpg', 'unique');
  insert into ids values ('CB1', x);
  insert into resultats (test, ok, detail) values ('Responsable GTI : capture envoyée', x is not null, x || '');
  begin insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-2.jpg'); perform public.envoyer_capture((select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-2.jpg', 'unique');
    insert into resultats (test, ok, detail) values ('Deuxième capture « unique » : refusée', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Deuxième capture « unique » : refusée', true, sqlerrm); end;
  t := public.annuler_ma_capture((select id from ids where nom = 'CB1'));
  perform set_config('storage.allow_delete_query', 'true', true);  -- le vrai Supabase bloque l'effacement direct en SQL ; le site passe par le service de stockage, qui lève ce blocage
  delete from storage.objects where bucket_id = 'captures' and name = t;
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Capture annulée par l’envoyeur et fichier supprimé', n = 1, n || '');
  insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-3.jpg');
  x := public.envoyer_capture((select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-3.jpg', 'unique');
  insert into ids values ('CB3', x);
  select count(*) into n from public.captures;
  insert into resultats (test, ok, detail) values ('Renvoi pendant la période ; le membre ne lit pas la table des captures', n = 0, n || '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013a1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'A') || '-1.jpg'); x := public.envoyer_capture((select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'A') || '-1.jpg', 'haut');
  insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'A') || '-2.jpg'); x := public.envoyer_capture((select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'A') || '-2.jpg', 'bas');
  j := public.liste_matchs_libres();
  select jsonb_array_length(e->'mes_captures') into n from jsonb_array_elements(j) e where (e->>'id')::bigint = (select id from ids where nom = 'L1');
  insert into resultats (test, ok, detail) values ('Responsable HAAVK : 2 captures (haut et bas)', n = 2, n || '');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin perform public.envoyer_capture((select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'D') || '-1.jpg', 'unique');
    insert into resultats (test, ok, detail) values ('Membre suspendu : n’envoie pas de capture', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre suspendu : n’envoie pas de capture', true, sqlerrm); end;
end $$;
reset role;

-- ---------- Katana : délai de 10 min, retard accepté, captures identiques ----------
update public.captures set envoyee_le = clock_timestamp() + interval '20 minutes' where id = (select id from ids where nom = 'CB3');  -- capture de B en retard (test)

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  select count(*) into n from public.registre where match_id = (select id from ids where nom = 'M1') and type = 'capture_recue' and membre_id = (select id from ids where nom = 'B');
  insert into resultats (test, ok, detail) values ('Capture notée au registre avec le matricule de l’envoyeur', n = 2, n || ' (envoi et renvoi)');
  perform public.noter_lecture(array[(select id from ids where nom = 'CB3')], '{"carte":"Test"}');
  select count(*) into n from public.captures where id = (select id from ids where nom = 'CB3') and lecture->>'carte' = 'Test';
  insert into resultats (test, ok, detail) values ('Lecture de claude.ai gardée avec la capture', n = 1, n || '');
  perform public.enregistrer_match(jsonb_build_object('id', (select id from ids where nom = 'M1'), 'saison_id', (select id from ids where nom = 'S'), 'fin', to_char(clock_timestamp() - interval '5 minutes', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
    'lignes', jsonb_build_array(jsonb_build_object('faction', 'HAAVK', 'pseudo', 'Joueur test', 'score', 1, 'elim', 0, 'morts', 0, 'assist', 0, 'med', 0, 'ing', 0, 'obj', 0, 'tac', 0))));
  perform public.decider_match((select id from ids where nom = 'M1'), 'valider', null);
  select count(*) into n from public.captures where id = (select id from ids where nom = 'CB3') and statut = 'refusee' and motif = 'Hors délai';
  insert into resultats (test, ok, detail) values ('Validation : la capture en retard est rejetée seule', n = 1, n || '');
  select count(*) into n from public.captures where match_id = (select id from ids where nom = 'M1') and statut = 'retenue';
  insert into resultats (test, ok, detail) values ('Les 2 captures à temps sont retenues, match validé', n = 2 and (select statut from public.matchs where id = (select id from ids where nom = 'M1')) = 'valide', n || '');
  begin perform public.accepter_capture_retard((select id from ids where nom = 'CB3'), 'Réseau coupé');
    insert into resultats (test, ok, detail) values ('Retard accepté : seulement sur un brouillon', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Retard accepté : seulement sur un brouillon', true, sqlerrm); end;
  perform public.decider_match((select id from ids where nom = 'M1'), 'brouillon', 'Test 0013');
  begin perform public.accepter_capture_retard((select id from ids where nom = 'CB3'), '');
    insert into resultats (test, ok, detail) values ('Retard accepté : motif obligatoire', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Retard accepté : motif obligatoire', true, sqlerrm); end;
  perform public.accepter_capture_retard((select id from ids where nom = 'CB3'), 'Réseau coupé, preuve envoyée');
  perform public.decider_match((select id from ids where nom = 'M1'), 'valider', null);
  select count(*) into n from public.captures where match_id = (select id from ids where nom = 'M1') and statut = 'retenue';
  insert into resultats (test, ok, detail) values ('Retard accepté (échec technique prouvé) : la capture compte', n = 3, n || '');
  perform public.decider_match((select id from ids where nom = 'M1'), 'brouillon', 'Test 0013');
  select array_length(public.ecarter_captures((select id from ids where nom = 'M1'), array[(select id from ids where nom = 'CB3')], null), 1) into n;
  insert into resultats (test, ok, detail) values ('Captures identiques : celle en trop est écartée (fichier à supprimer)', n = 1, n || '');
  perform public.decider_match((select id from ids where nom = 'M1'), 'valider', null);
  select count(*) into n from public.registre where match_id = (select id from ids where nom = 'M1') and type = 'capture_ecartee';
  insert into resultats (test, ok, detail) values ('Capture écartée notée au registre', n = 1, n || '');
end $$;
reset role;

update public.creneaux set debut = clock_timestamp() - interval '3 hours' where id = (select id from ids where nom = 'L1');  -- période d'envoi finie (test)

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  perform public.decider_match((select id from ids where nom = 'M1'), 'brouillon', 'Test 0013');
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000013b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000013b1', true);
set local role authenticated;
do $$
declare n int; x bigint; t text; j jsonb;
begin
  begin insert into storage.objects (bucket_id, name) values ('captures', (select id from ids where nom = 'M1') || '/m' || (select id from ids where nom = 'B') || '-9.jpg');
    insert into resultats (test, ok, detail) values ('Après la période d’envoi : dépôt refusé', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Après la période d’envoi : dépôt refusé', true, sqlerrm); end;
end $$;
reset role;

-- ---------- Résultat (tout est annulé) ----------
do $$
declare total int; echecs int; liste text;
begin
  select count(*), count(*) filter (where not ok) into total, echecs from resultats;
  select string_agg(n || '. ' || test || ' (' || detail || ')', ' | ' order by n) into liste from resultats where not ok;
  raise exception 'FIN DU TEST : % réussi(s) sur %. % Rien n''a été gardé dans la base (ce message apparaît comme une erreur exprès, pour tout annuler).',
    total - echecs, total, case when echecs = 0 then 'Tout est bon.' else 'ÉCHECS : ' || liste || '.' end;
end $$;
