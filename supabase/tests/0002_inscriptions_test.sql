-- =====================================================================
-- LEAGUE UV — DFMM · Test du lot 2A (inscription, approbation, accès)
-- À exécuter dans Supabase APRÈS la migration 0002 : SQL Editor > New query > Run.
-- Faux candidats seulement. Tout est annulé à la fin (message rouge voulu),
-- et le compteur des matricules est remis exactement où il était.
-- =====================================================================
begin;

create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table compteur as select last_value, is_called from public.matricule_seq;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad02', 'faux.admin2@test.invalid'),
  ('00000000-0000-4000-8000-0000000000a1', 'faux.a@test.invalid'),
  ('00000000-0000-4000-8000-0000000000b1', 'faux.b@test.invalid'),
  ('00000000-0000-4000-8000-0000000000c1', 'faux.c@test.invalid'),
  ('00000000-0000-4000-8000-0000000000d1', 'faux.d@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad02');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values
  (99007, 'Ancien Sept', '2026-11-18'), (99008, 'Ancien Huit', '2026-11-19');
insert into storage.objects (bucket_id, name) values ('profils', 'test/faux-profil.jpg');

create function pg_temp.dossier(u text, mail text, fb text, uid text) returns jsonb language sql as $$
  select jsonb_build_object('user_id', u, 'nom_gamer', 'Gamer ' || uid, 'nom_reel', 'Nom ' || uid, 'email', mail,
    'date_naissance', '2000-01-01', 'genre', 'Homme', 'facebook', fb, 'pseudo', 'Pseudo' || uid, 'uid', uid,
    'residence', 'Madagascar', 'province', 'Antananarivo', 'zone', 'Ville principale', 'comprend_mg', true, 'parle_mg', true,
    'origine_mg', true, 'acceptations', '{"dfmm":true}'::jsonb, 'empreinte_email', 'e-' || mail, 'empreinte_facebook', 'f-' || fb) $$;
grant execute on function pg_temp.dossier(text, text, text, text) to service_role;

-- ---------- 1. Fonction serveur (rôle service) : création des candidatures ----------
set local role service_role;
do $$
begin
  perform public.creer_inscription(pg_temp.dossier('00000000-0000-4000-8000-0000000000a1', 'a@x', 'fb/a', '9900001'));
  perform public.creer_inscription(pg_temp.dossier('00000000-0000-4000-8000-0000000000b1', 'b@x', 'fb/b', '9900002'));
  perform public.creer_inscription(pg_temp.dossier('00000000-0000-4000-8000-0000000000c1', 'c@x', 'fb/c', '9900003'));
  insert into resultats (test, ok, detail) values ('Serveur : 3 candidatures créées', true, '');
  begin
    perform public.creer_inscription(pg_temp.dossier('00000000-0000-4000-8000-0000000000d1', 'a@x', 'fb/d', '9900004'));
    insert into resultats (test, ok, detail) values ('Même e-mail refusé', false, 'acceptée');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Même e-mail refusé', sqlerrm = 'DOUBLON_INSCRIPTION', sqlerrm);
  end;
  begin
    perform public.creer_inscription(pg_temp.dossier('00000000-0000-4000-8000-0000000000d1', 'd@x', 'fb/a', '9900004'));
    insert into resultats (test, ok, detail) values ('Même lien Facebook refusé', false, 'acceptée');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Même lien Facebook refusé', sqlerrm = 'DOUBLON_INSCRIPTION', sqlerrm);
  end;
  begin
    perform public.creer_inscription(pg_temp.dossier('00000000-0000-4000-8000-0000000000d1', 'd@x', 'fb/d', '9900001'));
    insert into resultats (test, ok, detail) values ('Même UID refusé', false, 'acceptée');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Même UID refusé', sqlerrm = 'DOUBLON_UID', sqlerrm);
  end;
end $$;
reset role;

-- ---------- 2. Visiteur ----------
select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
  begin
    perform 1 from public.membres_prives;
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas les données privées', false, 'lecture permise');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas les données privées', true, 'refusé');
  end;
  begin
    perform public.creer_inscription('{}'::jsonb);
    insert into resultats (test, ok, detail) values ('Visiteur : ne crée pas d''inscription en direct', false, 'permis');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne crée pas d''inscription en direct', true, 'refusé');
  end;
end $$;
reset role;

-- ---------- 3. Candidat A (connecté, en attente) ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
set local role authenticated;
do $$
declare n int; e text;
begin
  select count(*), max(email) into n, e from public.membres_prives;
  insert into resultats (test, ok, detail) values ('Candidat A : voit seulement ses données privées', n = 1 and e = 'a@x', n || ' fiche(s)');
  select count(*) into n from public.matricules_anciens;
  insert into resultats (test, ok, detail) values ('Candidat A : ne voit pas les anciens matricules', n = 0, n || ' ligne(s)');
  select count(*) into n from storage.objects where bucket_id = 'profils';
  insert into resultats (test, ok, detail) values ('Candidat A : ne voit pas les captures de profil', n = 0, n || ' fichier(s)');
  update public.membres_prives set nom_reel = 'Pirate';
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Candidat A : ne modifie pas ses données lui-même', n = 0, n || ' ligne(s)');
  begin
    perform public.decider_inscription((select id from public.membres limit 1), 'approuver');
    insert into resultats (test, ok, detail) values ('Candidat A : ne peut pas s''approuver', false, 'approuvé');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Candidat A : ne peut pas s''approuver', true, sqlerrm);
  end;
  begin
    perform public.creer_inscription('{}'::jsonb);
    insert into resultats (test, ok, detail) values ('Candidat A : ne crée pas d''inscription en direct', false, 'permis');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Candidat A : ne crée pas d''inscription en direct', true, 'refusé');
  end;
end $$;
reset role;

-- ---------- 4. Administrateur : décisions ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad02"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad02', true);
set local role authenticated;
do $$
declare ida bigint; idb bigint; idc bigint; mat int; attendu int; deb timestamptz; n int; st text;
begin
  select id into ida from public.membres where user_id = '00000000-0000-4000-8000-0000000000a1';
  select id into idb from public.membres where user_id = '00000000-0000-4000-8000-0000000000b1';
  select id into idc from public.membres where user_id = '00000000-0000-4000-8000-0000000000c1';
  select count(*) into n from storage.objects where bucket_id = 'profils';
  insert into resultats (test, ok, detail) values ('Admin : voit les captures de profil', n >= 1, n || ' fichier(s)');
  select greatest(26, coalesce((select max(matricule) from public.membres), 0) + 0) into attendu;
  mat := public.decider_inscription(ida, 'approuver');
  insert into resultats (test, ok, detail) values ('Admin : nouveau matricule attribué (26 ou plus)', mat >= 26, 'DFMM-' || mat);
  select statut into st from public.membres where id = ida;
  select count(*) into n from public.comptes_jeu where membre_id = ida and statut = 'actif';
  insert into resultats (test, ok, detail) values ('Admin : membre actif et compte de jeu actif', st = 'actif' and n = 1, st || ', ' || n || ' compte(s) actif(s)');
  mat := public.decider_inscription(idb, 'approuver', null, 99007);
  select debut into deb from public.periodes where membre_id = idb;
  insert into resultats (test, ok, detail) values ('Admin : ancien matricule repris', mat = 99007, 'DFMM-' || mat);
  insert into resultats (test, ok, detail) values ('Admin : période depuis 0 h (Madagascar) le jour d''origine',
    deb = timestamptz '2026-11-18 00:00:00+03', deb::text);
  select count(*) into n from public.comptes_periodes cp join public.comptes_jeu c on c.id = cp.compte_id where c.membre_id = idb;
  insert into resultats (test, ok, detail) values ('Admin : période du compte de jeu ouverte', n = 1, n || ' période(s)');
  begin
    perform public.decider_inscription(idc, 'approuver', null, 99007);
    insert into resultats (test, ok, detail) values ('Admin : un ancien matricule ne sert qu''une fois', false, 'repris deux fois');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Admin : un ancien matricule ne sert qu''une fois', true, sqlerrm);
  end;
  begin
    perform public.decider_inscription(idc, 'refuser', '  ');
    insert into resultats (test, ok, detail) values ('Admin : refus sans motif impossible', false, 'accepté');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Admin : refus sans motif impossible', true, sqlerrm);
  end;
  perform public.decider_inscription(idc, 'precisions', 'Capture illisible');
  select statut into st from public.membres where id = idc;
  insert into resultats (test, ok, detail) values ('Admin : demande de précisions', st = 'precisions', st);
  perform public.decider_inscription(idc, 'refuser', 'Ne comprend pas le malgache');
  select statut into st from public.membres where id = idc;
  insert into resultats (test, ok, detail) values ('Admin : refus avec motif', st = 'refuse', st);
  begin
    perform public.decider_inscription(ida, 'refuser', 'Trop tard');
    insert into resultats (test, ok, detail) values ('Admin : une décision prise ne se rejoue pas', false, 'rejouée');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Admin : une décision prise ne se rejoue pas', true, sqlerrm);
  end;
  select count(*) into n from public.journal where type = 'Inscription';
  insert into resultats (test, ok, detail) values ('Admin : chaque étape est dans le journal', n >= 6, n || ' ligne(s)');
end $$;
reset role;

-- ---------- 5. Membre A approuvé ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.comptes_periodes;
  insert into resultats (test, ok, detail) values ('Membre A : voit la période de son compte, pas celles des autres', n = 1, n || ' ligne(s)');
  select count(*) into n from public.membres;
  insert into resultats (test, ok, detail) values ('Membre A : voit seulement sa fiche', n = 1, n || ' fiche(s)');
end $$;
reset role;

-- ---------- Résultat ; compteur des matricules remis en place ; tout est annulé ----------
do $$
declare total int; echecs int; liste text; c record;
begin
  select * into c from compteur;
  perform setval('public.matricule_seq', c.last_value, c.is_called);
  select count(*), count(*) filter (where not ok) into total, echecs from resultats;
  select string_agg(n || '. ' || test || ' (' || detail || ')', ' | ' order by n) into liste from resultats where not ok;
  raise exception 'FIN DU TEST : % réussi(s) sur %. % Rien n''a été gardé dans la base (ce message apparaît comme une erreur exprès, pour tout annuler).',
    total - echecs, total, case when echecs = 0 then 'Tout est bon.' else 'ÉCHECS : ' || liste || '.' end;
end $$;
