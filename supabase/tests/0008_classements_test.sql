-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0008 (classements publiés)
-- À exécuter APRÈS la migration 0008. Faux administrateur, faux membre, fausse saison,
-- faux classements. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad08', 'faux.admin8@test.invalid'),
  ('00000000-0000-4000-8000-0000000008a1', 'faux.8a@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad08');
insert into public.saisons (nom, debut, fin) values ('Saison test 0008', '2026-09-08', '2026-11-10');
insert into ids select 'S', id from public.saisons where nom = 'Saison test 0008';

-- ---------- 1. Administrateur : numéros automatiques, heure du serveur, journal ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad08"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad08', true);
set local role authenticated;
do $$
declare s bigint := (select id from ids where nom = 'S'); n int; a int; b int; d timestamptz;
begin
  insert into public.publications (saison_id, type, numero, publie_le, coupure, contenu)
  values (s, 'provisoire', 99, '2000-01-01', '2026-10-17T16:00:00+03:00', '{"categories":[]}');
  insert into public.publications (saison_id, type, coupure, contenu)
  values (s, 'provisoire', '2026-10-31T16:00:00+03:00', '{"categories":[]}');
  select min(numero), max(numero) into a, b from public.publications where saison_id = s and type = 'provisoire';
  insert into resultats (test, ok, detail) values ('Provisoires numérotés 1 puis 2 par la base (numéro du téléphone ignoré)', a = 1 and b = 2, a || ' et ' || b);
  select min(publie_le) into d from public.publications where saison_id = s;
  insert into resultats (test, ok, detail) values ('Heure de publication fixée par le serveur', d > '2026-01-01'::timestamptz, d::text);
  select count(*) into n from public.journal where type = 'Publication' and objet = 'Saison test 0008';
  insert into resultats (test, ok, detail) values ('Chaque publication est notée au journal', n = 2, n || ' ligne(s)');

  insert into public.publications (saison_id, type, coupure, contenu) values (s, 'final', '2026-11-11T00:00:00+03:00', '{"categories":[]}');
  select numero into a from public.publications where saison_id = s and type = 'final';
  insert into resultats (test, ok, detail) values ('Classement final : sans numéro', a is null, coalesce(a::text, 'aucun'));
  begin insert into public.publications (saison_id, type, coupure, contenu) values (s, 'final', '2026-11-11T00:00:00+03:00', '{}');
    insert into resultats (test, ok, detail) values ('Un seul classement final par saison', false, 'deux finals');
  exception when raise_exception or unique_violation then insert into resultats (test, ok, detail) values ('Un seul classement final par saison', true, sqlerrm); end;

  begin insert into public.publications (saison_id, type, coupure, contenu) values (s, 'provisoire', now() + interval '2 days', '{}');
    insert into resultats (test, ok, detail) values ('Coupure dans le futur refusée', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Coupure dans le futur refusée', true, sqlerrm); end;

  begin update public.publications set contenu = '{"modifie":true}' where saison_id = s;
    insert into resultats (test, ok, detail) values ('Un classement publié ne se modifie pas', false, 'modifié');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un classement publié ne se modifie pas', true, sqlerrm); end;
  begin delete from public.publications where saison_id = s;
    insert into resultats (test, ok, detail) values ('Un classement publié ne se supprime pas', false, 'supprimé');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un classement publié ne se supprime pas', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 2. Visiteur : lit les classements, n'en publie pas ----------
set local role anon;
do $$
declare n int;
begin
  select count(*) into n from public.publications where saison_id = (select id from ids where nom = 'S');
  insert into resultats (test, ok, detail) values ('Visiteur : lit les classements publiés', n = 3, n || ' classement(s)');
  begin insert into public.publications (saison_id, type, coupure, contenu) values ((select id from ids where nom = 'S'), 'provisoire', '2026-10-17T16:00:00+03:00', '{}');
    insert into resultats (test, ok, detail) values ('Visiteur : ne publie pas', false, 'publié');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : ne publie pas', true, 'refusé'); end;
end $$;
reset role;

-- ---------- 3. Membre connecté (non administrateur) : ne publie pas ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000008a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008a1', true);
set local role authenticated;
do $$
begin
  begin insert into public.publications (saison_id, type, coupure, contenu) values ((select id from ids where nom = 'S'), 'provisoire', '2026-10-17T16:00:00+03:00', '{}');
    insert into resultats (test, ok, detail) values ('Membre : ne publie pas', false, 'publié');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : ne publie pas', true, 'refusé'); end;
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
