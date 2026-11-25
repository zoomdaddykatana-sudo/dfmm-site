-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0020 (membre hors concours)
-- À exécuter APRÈS la migration 0020. Faux membres seulement (anciens matricules fictifs 99071 et
-- 99072, adresses @test.invalid), fausse saison, faux classement final, faux lots. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000020a0', 'faux.admin20@test.invalid'),
  ('00000000-0000-4000-8000-0000000020a1', 'faux.20a@test.invalid'),
  ('00000000-0000-4000-8000-0000000020b1', 'faux.20b@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000020a0');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99071, 'Faux 20A', '2026-11-18'), (99072, 'Faux 20B', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000020a1','nom_gamer','Faux 20A','email','20a@test.invalid','facebook','facebook.com/faux20a','pseudo','Vingt A','uid','9920001','empreinte_email','e20a','empreinte_facebook','f20a','residence','Madagascar','comprend_mg',true,'parle_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000020b1','nom_gamer','Faux 20B','email','20b@test.invalid','facebook','facebook.com/faux20b','pseudo','Vingt B','uid','9920002','empreinte_email','e20b','empreinte_facebook','f20b','residence','Madagascar','comprend_mg',true,'parle_mg',true));
end $$;
reset role;

-- ---------- 1. Colonne en place, « non » par défaut ----------
do $$
declare t text; nul text; def text; n int;
begin
  select data_type, is_nullable, column_default into t, nul, def from information_schema.columns
   where table_schema = 'public' and table_name = 'membres' and column_name = 'hors_concours';
  insert into resultats (test, ok, detail) values ('Colonne membres.hors_concours : booléen, obligatoire, non par défaut',
    t = 'boolean' and nul = 'NO' and def = 'false', coalesce(t || ' / ' || nul || ' / ' || def, 'absente'));
  select count(*) into n from public.membres where id in (select id from ids) and hors_concours;
  insert into resultats (test, ok, detail) values ('Nouvelle inscription : pas hors concours', n = 0, n || ' hors concours');
end $$;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000020a0"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000020a0', true);
set local role authenticated;
do $$
declare a bigint := (select id from ids where nom = 'A'); n int; hc boolean;
begin
  perform public.decider_inscription(a, 'approuver', null, 99071);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99072);
  -- 2. Motif obligatoire
  begin perform public.definir_hors_concours(a, true, '   ');
    insert into resultats (test, ok, detail) values ('Motif vide refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Motif vide refusé', true, sqlerrm); end;
  -- 3. Déclaration par l'administrateur, notée au journal
  perform public.definir_hors_concours(a, true, 'Administrateur joueur');
  select hors_concours into hc from public.membres where id = a;
  insert into resultats (test, ok, detail) values ('Administrateur : déclare un membre hors concours', hc, coalesce(hc::text, 'absent'));
  select count(*) into n from public.journal where objet = 'DFMM-99071' and decision like 'Déclaré hors concours%' and motif = 'Administrateur joueur';
  insert into resultats (test, ok, detail) values ('Déclaration notée au journal avec le motif', n = 1, n || ' ligne(s)');
  -- 4. Déjà hors concours : refusé
  begin perform public.definir_hors_concours(a, true, 'Encore');
    insert into resultats (test, ok, detail) values ('Déjà hors concours : refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Déjà hors concours : refusé', true, sqlerrm); end;
  -- 5. Membre inconnu : refusé
  begin perform public.definir_hors_concours(-1, true, 'Essai');
    insert into resultats (test, ok, detail) values ('Membre inconnu : refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre inconnu : refusé', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 6. Un membre ne se déclare pas hors concours (ni un autre) ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000020b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000020b1', true);
set local role authenticated;
do $$ begin
  begin perform public.definir_hors_concours((select id from ids where nom = 'B'), true, 'Moi aussi');
    insert into resultats (test, ok, detail) values ('Membre : ne change pas le statut', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre : ne change pas le statut', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 7. Un visiteur ne peut pas appeler la fonction ----------
set local role anon;
do $$ begin
  begin perform public.definir_hors_concours((select id from ids where nom = 'B'), true, 'Visiteur');
    insert into resultats (test, ok, detail) values ('Visiteur : fonction refusée', false, 'accepté');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : fonction refusée', true, 'refusé'); end;
end $$;
reset role;

-- ---------- 8. Lots : jamais à un membre hors concours (contrôle de la base) ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000020a0"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000020a0', true);
set local role authenticated;
do $$
declare s bigint; f bigint; n int;
begin
  insert into public.saisons (nom, debut, fin) values ('Saison test 0020', '2026-09-08', '2026-11-10') returning id into s;
  insert into public.lots (saison_id, categorie, description, confirme) values (s, 'most_elim', 'Lot test 1', true), (s, 'most_med', 'Lot test 2', true);
  insert into public.publications (saison_id, type, coupure, contenu) values (s, 'final', '2026-11-11T00:00:00+03:00', '{"categories":[]}');
  select id into f from public.publications where saison_id = s and type = 'final';
  begin perform public.enregistrer_attribution(f, jsonb_build_array(
      jsonb_build_object('categorie', 'most_elim', 'beneficiaire_matricule', 99071, 'statut', 'Attribué')));
    insert into resultats (test, ok, detail) values ('Lot refusé à un membre hors concours', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Lot refusé à un membre hors concours', sqlerrm like '%hors concours%', sqlerrm); end;
  n := public.enregistrer_attribution(f, jsonb_build_array(
      jsonb_build_object('categorie', 'most_elim', 'beneficiaire_matricule', 99072, 'statut', 'Attribué', 'explication', 'Lot remis au lauréat sportif.'),
      jsonb_build_object('categorie', 'most_med', 'beneficiaire_matricule', null, 'statut', 'Non attribué')));
  insert into resultats (test, ok, detail) values ('Lots des autres membres : attribution inchangée', n = 2, n || ' lot(s)');
  select count(*) into n from public.lots where saison_id = s and beneficiaire_id = (select id from ids where nom = 'B');
  insert into resultats (test, ok, detail) values ('Bénéficiaire en concours enregistré', n = 1, n || ' lot(s)');
  -- 9. Remis en concours
  perform public.definir_hors_concours((select id from ids where nom = 'A'), false, 'Fin de l''essai');
  select count(*) into n from public.membres where id = (select id from ids where nom = 'A') and not hors_concours;
  insert into resultats (test, ok, detail) values ('Administrateur : remet le membre en concours', n = 1, '');
  select count(*) into n from public.journal where objet = 'DFMM-99071' and decision = 'Remis en concours';
  insert into resultats (test, ok, detail) values ('Remise en concours notée au journal', n = 1, n || ' ligne(s)');
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
