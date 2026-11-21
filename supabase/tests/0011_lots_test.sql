-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0011 (titres et lots)
-- À exécuter APRÈS la migration 0011. Faux membres seulement (anciens matricules fictifs 99061 et
-- 99062), fausse saison terminée, faux classements, faux lots. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000b1', 'faux.admin11@test.invalid'),
  ('00000000-0000-4000-8000-0000000011a1', 'faux.11a@test.invalid'),
  ('00000000-0000-4000-8000-0000000011b1', 'faux.11b@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000000b1');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99061, 'Faux 11A', '2026-09-08'), (99062, 'Faux 11B', '2026-09-08');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000011a1','nom_gamer','Faux 11A','email','11a@x','facebook','fb/11a','pseudo','Onze A','uid','9911001','empreinte_email','e11a','empreinte_facebook','f11a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000011b1','nom_gamer','Faux 11B','email','11b@x','facebook','fb/11b','pseudo','Onze B','uid','9911002','empreinte_email','e11b','empreinte_facebook','f11b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
set local role authenticated;
do $$
declare s bigint; n int;
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99061);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99062);
  insert into public.saisons (nom, debut, fin) values ('Saison test 0011', '2026-09-08', '2026-11-10') returning id into s;
  insert into ids values ('S', s);
  insert into public.lots (saison_id, categorie, description, confirme) values
    (s, 'most_elim', 'Lot test 1', true), (s, 'most_med', 'Lot test 2', true), (s, 'best_tac', 'Lot test 3 (pas encore confirmé)', false);
  insert into public.publications (saison_id, type, coupure, contenu) values (s, 'provisoire', '2026-10-17T16:00:00+03:00', '{"categories":[]}');
  insert into ids select 'PROV', id from public.publications where saison_id = s and type = 'provisoire';
  insert into public.publications (saison_id, type, coupure, contenu) values (s, 'final', '2026-11-11T00:00:00+03:00', '{"categories":[]}');
  insert into ids select 'FIN', id from public.publications where saison_id = s and type = 'final';
  select count(*) into n from public.lots where saison_id = s;
  insert into resultats (test, ok, detail) values ('Administrateur : enregistre les lots de la saison', n = 3, n || ' lot(s)');
end $$;
reset role;

-- ---------- Lots jamais visibles du public ni des membres ----------
set local role anon;
do $$
declare n int;
begin
  begin select count(*) into n from public.lots;
    insert into resultats (test, ok, detail) values ('Visiteur : ne voit pas les lots', false, n || ' ligne(s)');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : ne voit pas les lots', true, 'refusé'); end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000011a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000011a1', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.lots;
  insert into resultats (test, ok, detail) values ('Membre : ne voit pas les lots', n = 0, n || ' ligne(s)');
  begin insert into public.lots (saison_id, categorie) values ((select id from ids where nom = 'S'), 'best_obj');
    insert into resultats (test, ok, detail) values ('Membre : n''ajoute pas de lot', false, 'ajouté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : n''ajoute pas de lot', true, 'refusé'); end;
  begin perform public.enregistrer_attribution((select id from ids where nom = 'FIN'), '[]');
    insert into resultats (test, ok, detail) values ('Membre : n''enregistre pas d''attribution', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre : n''enregistre pas d''attribution', true, sqlerrm); end;
end $$;
reset role;

-- ---------- Attribution sur le classement final ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
set local role authenticated;
do $$
declare s bigint := (select id from ids where nom = 'S'); n int; l bigint;
begin
  begin perform public.enregistrer_attribution((select id from ids where nom = 'PROV'), '[]');
    insert into resultats (test, ok, detail) values ('Pas d''attribution sur un classement provisoire', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Pas d''attribution sur un classement provisoire', true, sqlerrm); end;
  begin perform public.enregistrer_attribution((select id from ids where nom = 'FIN'), jsonb_build_array(
      jsonb_build_object('categorie', 'most_elim', 'beneficiaire_matricule', 99061, 'statut', 'Attribué'),
      jsonb_build_object('categorie', 'most_med', 'beneficiaire_matricule', 99061, 'statut', 'Attribué')));
    insert into resultats (test, ok, detail) values ('Un joueur ne reçoit qu''un lot au plus', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un joueur ne reçoit qu''un lot au plus', true, sqlerrm); end;
  n := public.enregistrer_attribution((select id from ids where nom = 'FIN'), jsonb_build_array(
      jsonb_build_object('categorie', 'most_elim', 'beneficiaire_matricule', 99061, 'statut', 'Attribué', 'explication', 'Lot remis au lauréat sportif.'),
      jsonb_build_object('categorie', 'most_med', 'beneficiaire_matricule', 99062, 'statut', 'Attribué (redistribution)', 'explication', 'Le lauréat a déjà un lot.'),
      jsonb_build_object('categorie', 'best_tac', 'beneficiaire_matricule', null, 'statut', 'Non attribué')));
  insert into resultats (test, ok, detail) values ('Attribution : seuls les lots confirmés sont attribués', n = 2, n || ' lot(s)');
  select count(*) into n from public.lots where saison_id = s and beneficiaire_id is not null and publication_id = (select id from ids where nom = 'FIN');
  insert into resultats (test, ok, detail) values ('Bénéficiaires enregistrés avec le classement final', n = 2, n || ' bénéficiaire(s)');
  select id into l from public.lots where saison_id = s and categorie = 'most_elim';
  perform public.marquer_lot_remis(l);
  select count(*) into n from public.lots where id = l and remis_le is not null;
  insert into resultats (test, ok, detail) values ('Lot marqué comme remis', n = 1, '');
  begin perform public.marquer_lot_remis((select id from public.lots where saison_id = s and categorie = 'best_tac'));
    insert into resultats (test, ok, detail) values ('Pas de remise sans bénéficiaire', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Pas de remise sans bénéficiaire', true, sqlerrm); end;
  select count(*) into n from public.journal where type = 'Lots';
  insert into resultats (test, ok, detail) values ('Attribution et remise notées au journal', n = 2, n || ' ligne(s)');
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
