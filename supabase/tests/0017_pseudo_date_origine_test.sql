-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0017 (pseudo à la date d'origine)
-- À exécuter APRÈS la migration 0017. Faux candidats seulement (adresses @test.invalid, UID 99170xx,
-- anciens matricules fictifs 99171 à 99173). Aucun nouveau matricule n'est attribué (le compteur ne bouge pas).
-- Tout est annulé à la fin (message rouge voulu).
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000017ad', 'faux.admin17@test.invalid'),
  ('00000000-0000-4000-8000-0000000017a1', 'faux.17a@test.invalid'),
  ('00000000-0000-4000-8000-0000000017b1', 'faux.17b@test.invalid'),
  ('00000000-0000-4000-8000-0000000017c1', 'faux.17c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000017ad');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values
  (99171, 'Ancien 171', '2026-11-18'), (99172, 'Ancien 172', '2026-11-19'), (99173, 'Ancien 173', '2026-11-18');

-- ---------- 1. Trois fausses candidatures (rôle serveur) ----------
set local role service_role;
do $$
declare k text; u text;
begin
  foreach k in array array['a', 'b', 'c'] loop
    u := '00000000-0000-4000-8000-0000000017' || k || '1';
    insert into ids select upper(k), public.creer_inscription(jsonb_build_object('user_id', u, 'nom_gamer', 'Faux 17' || upper(k),
      'email', '17' || k || '@test.invalid', 'facebook', 'facebook.com/faux17' || k, 'pseudo', 'Pseudo17' || upper(k),
      'uid', '991700' || (ascii(k) - 96), 'empreinte_email', 'e17' || k, 'empreinte_facebook', 'f17' || k,
      'residence', 'Madagascar', 'comprend_mg', true, 'parle_mg', true, 'origine_mg', true));
  end loop;
end $$;
reset role;

-- Le pseudo commence à la date de l'inscription (maintenant) : on le place au 22/11/2026 pour un résultat fixe.
update public.pseudos_historique set debut = '2026-11-22 10:00+03'
where compte_id in (select c.id from public.comptes_jeu c join ids on ids.id = c.membre_id);

-- ---------- 2. Approbation avec un ancien matricule : le pseudo prend la date d'origine ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000017ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000017ad', true);
set local role authenticated;
do $$
declare v_mat int; d timestamptz; m public.membres%rowtype;
begin
  v_mat := public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99171);
  select * into m from public.membres where id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Ancien matricule repris, adhésion à la date d''origine (inchangé)',
    v_mat = 99171 and m.date_approbation = '2026-11-18 00:00+03', v_mat || ' · ' || m.date_approbation);
end $$;
reset role;
do $$
declare d timestamptz; n int;
begin
  select h.debut, count(*) over () into d, n from public.pseudos_historique h
  join public.comptes_jeu c on c.id = h.compte_id where c.membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Pseudo ramené au 18/11/2026 à 0 h (Madagascar)',
    n = 1 and d = '2026-11-18 00:00+03', n || ' pseudo(s) · ' || d);
  select count(*) into n from public.comptes_periodes p join public.comptes_jeu c on c.id = p.compte_id
  where c.membre_id = (select id from ids where nom = 'A') and p.debut = '2026-11-18 00:00+03';
  insert into resultats (test, ok, detail) values ('Période du compte de jeu à la date d''origine (inchangé)', n = 1, n || ' période(s)');
end $$;

-- ---------- 3. Refus : aucun pseudo touché ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000017ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000017ad', true);
set local role authenticated;
do $$ begin perform public.decider_inscription((select id from ids where nom = 'B'), 'refuser', 'Faux refus de test'); end $$;
reset role;
do $$
declare d timestamptz;
begin
  select h.debut into d from public.pseudos_historique h join public.comptes_jeu c on c.id = h.compte_id
  where c.membre_id = (select id from ids where nom = 'B');
  insert into resultats (test, ok, detail) values ('Candidature refusée : pseudo inchangé', d = '2026-11-22 10:00+03', d::text);
end $$;

-- ---------- 4. Correction des membres déjà réinscrits (point 2) ----------
-- C : réinscrit avec 99173 avant la migration (simulé : pseudo remis au 22/11), puis un changement de pseudo le 23/11.
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000017ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000017ad', true);
set local role authenticated;
do $$ begin perform public.decider_inscription((select id from ids where nom = 'C'), 'approuver', null, 99173); end $$;
reset role;
do $$
declare v_cpt bigint; n int; d1 timestamptz; d2 timestamptz;
begin
  select c.id into v_cpt from public.comptes_jeu c where c.membre_id = (select id from ids where nom = 'C');
  update public.pseudos_historique set debut = '2026-11-22 10:00+03', fin = '2026-11-23 10:00+03' where compte_id = v_cpt;
  insert into public.pseudos_historique (compte_id, pseudo, debut) values (v_cpt, 'Pseudo17C-nouveau', '2026-11-23 10:00+03');
  n := public.pseudos_a_date_origine((select id from ids where nom = 'C'), (select date_approbation from public.membres where id = (select id from ids where nom = 'C')));
  select debut into d1 from public.pseudos_historique where compte_id = v_cpt and pseudo = 'Pseudo17C';
  select debut into d2 from public.pseudos_historique where compte_id = v_cpt and pseudo = 'Pseudo17C-nouveau';
  insert into resultats (test, ok, detail) values ('Correction : seul le premier pseudo est ramené à la date d''origine',
    n = 1 and d1 = '2026-11-18 00:00+03' and d2 = '2026-11-23 10:00+03', n || ' · ' || d1 || ' · ' || d2);
  n := public.pseudos_a_date_origine((select id from ids where nom = 'C'), '2026-11-18 00:00+03');
  insert into resultats (test, ok, detail) values ('Correction relancée : rien de plus (déjà à la bonne date)', n = 0, n || ' ligne(s)');
  n := public.pseudos_a_date_origine((select id from ids where nom = 'C'), '2026-11-25 00:00+03');
  insert into resultats (test, ok, detail) values ('Pseudo déjà plus ancien que la date donnée : jamais avancé', n = 0, n || ' ligne(s)');
end $$;

-- ---------- 5. Droits : la fonction de correction est réservée à la base ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000017ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000017ad', true);
set local role authenticated;
do $$
begin
  perform public.pseudos_a_date_origine((select id from ids where nom = 'A'), '2026-01-01 00:00+03');
  insert into resultats (test, ok, detail) values ('Personne connectée (même Katana) : correction directe refusée', false, 'acceptée');
exception when insufficient_privilege then
  insert into resultats (test, ok, detail) values ('Personne connectée (même Katana) : correction directe refusée', true, sqlerrm);
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99172);
  insert into resultats (test, ok, detail) values ('Visiteur : approbation refusée', false, 'acceptée');
exception when insufficient_privilege or raise_exception then
  insert into resultats (test, ok, detail) values ('Visiteur : approbation refusée', true, sqlerrm);
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
