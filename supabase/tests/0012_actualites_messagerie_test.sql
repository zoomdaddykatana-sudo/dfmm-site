-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0012 (actualités et messagerie)
-- À exécuter APRÈS la migration 0012. Faux membres seulement (anciens matricules fictifs 99071 et
-- 99072), fausse saison, faux classement, fausses actualités et faux messages. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000c1', 'faux.admin12@test.invalid'),
  ('00000000-0000-4000-8000-0000000012a1', 'faux.12a@test.invalid'),
  ('00000000-0000-4000-8000-0000000012b1', 'faux.12b@test.invalid'),
  ('00000000-0000-4000-8000-0000000012c1', 'faux.12c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000000c1');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99071, 'Faux 12A', '2026-11-18'), (99072, 'Faux 12B', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000012a1','nom_gamer','Faux 12A','email','12a@x','facebook','fb/12a','pseudo','Douze A','uid','9912001','empreinte_email','e12a','empreinte_facebook','f12a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000012b1','nom_gamer','Faux 12B','email','12b@x','facebook','fb/12b','pseudo','Douze B','uid','9912002','empreinte_email','e12b','empreinte_facebook','f12b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);
set local role authenticated;
do $$
declare s bigint;
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99071);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99072);
  insert into public.actualites (titre, texte) values ('Test 0012 visible', 'Bienvenue');
  insert into public.actualites (titre, texte, retire_le) values ('Test 0012 retirée', 'Ancienne', clock_timestamp());
  insert into public.saisons (nom, debut, fin) values ('Saison test 0012', '2026-09-08', '2026-11-10') returning id into s;
  insert into public.publications (saison_id, type, coupure, contenu) values (s, 'provisoire', '2026-10-17T16:00:00+03:00', '{"categories":[]}');
  insert into ids select 'P', id from public.publications where saison_id = s;
end $$;
reset role;

-- ---------- Actualités : membres connectés seulement ----------
set local role anon;
do $$
declare n int;
begin
  begin select count(*) into n from public.actualites;
    insert into resultats (test, ok, detail) values ('Visiteur : ne voit pas les actualités', false, n || ' ligne(s)');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : ne voit pas les actualités', true, 'refusé'); end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000012c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000012c1', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.actualites where titre like 'Test 0012%';
  insert into resultats (test, ok, detail) values ('Compte connecté sans fiche membre : ne voit pas les actualités', n = 0, n || ' ligne(s)');
  begin perform public.ecrire_a_katana('Bonjour');
    insert into resultats (test, ok, detail) values ('Compte sans fiche membre : n''écrit pas à Katana', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Compte sans fiche membre : n''écrit pas à Katana', true, sqlerrm); end;
end $$;
reset role;

-- ---------- Membre A : lit les actualités, écrit, fait une réclamation ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000012a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000012a1', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.actualites where titre like 'Test 0012%';
  insert into resultats (test, ok, detail) values ('Membre : voit l''actualité publiée, pas celle retirée', n = 1, n || ' ligne(s)');
  begin insert into public.actualites (titre, texte) values ('Pirate', 'x');
    insert into resultats (test, ok, detail) values ('Membre : ne publie pas d''actualité', false, 'publiée');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : ne publie pas d''actualité', true, 'refusé'); end;
  perform public.ecrire_a_katana('Bonjour Katana');
  perform public.ecrire_a_katana('Je conteste le classement', (select id from ids where nom = 'P'));
  select count(*) into n from public.messages;
  insert into resultats (test, ok, detail) values ('Membre : écrit à Katana, réclamation dans les 48 h acceptée', n = 2, n || ' message(s)');
  begin insert into public.messages (membre_id, de_katana, texte) values ((select id from ids where nom = 'B'), true, 'faux Katana');
    insert into resultats (test, ok, detail) values ('Membre : ne se fait pas passer pour Katana', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : ne se fait pas passer pour Katana', true, 'refusé'); end;
end $$;
reset role;

-- ---------- Katana : lit, répond ; délai de réclamation ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);
set local role authenticated;
do $$
declare a bigint := (select id from ids where nom = 'A'); n int;
begin
  select count(*) into n from public.messages where membre_id = a and not de_katana and lu_le is null;
  insert into resultats (test, ok, detail) values ('Katana : voit les 2 messages non lus', n = 2, n || ' message(s)');
  select count(*) into n from public.journal where type = 'Réclamation';
  insert into resultats (test, ok, detail) values ('Réclamation notée au journal', n = 1, n || ' ligne(s)');
  perform public.marquer_messages_lus(a);
  select count(*) into n from public.messages where membre_id = a and not de_katana and lu_le is null;
  insert into resultats (test, ok, detail) values ('Katana : marque les messages comme lus', n = 0, n || ' non lu(s)');
  perform public.repondre_membre(a, 'Je regarde ta réclamation.');
  select count(*) into n from public.notifications where membre_id = a and texte like 'Nouveau message de Katana%';
  insert into resultats (test, ok, detail) values ('Réponse de Katana : le membre est averti', n = 1, n || ' notification(s)');
  update public.parametres set valeur = '0' where cle = 'reclamation_h';
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000012a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000012a1', true);
set local role authenticated;
do $$
declare n int;
begin
  begin perform public.ecrire_a_katana('Trop tard', (select id from ids where nom = 'P'));
    insert into resultats (test, ok, detail) values ('Réclamation refusée après le délai', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Réclamation refusée après le délai', true, sqlerrm); end;
  perform public.marquer_messages_lus();
  select count(*) into n from public.messages where de_katana and lu_le is null;
  insert into resultats (test, ok, detail) values ('Membre : lit la réponse de Katana', n = 0, n || ' non lu(s)');
end $$;
reset role;

-- ---------- Membre B : ne voit pas la conversation de A ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000012b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000012b1', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.messages;
  insert into resultats (test, ok, detail) values ('Un autre membre ne voit pas la conversation', n = 0, n || ' message(s)');
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
