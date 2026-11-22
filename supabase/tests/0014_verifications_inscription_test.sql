-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0014 (vérifications automatiques à l'inscription)
-- À exécuter APRÈS la migration 0014. Faux candidats seulement (adresses @test.invalid, UID 99140xx).
-- Aucun appel réel à volsever (résultats simulés). Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000014ad', 'faux.admin14@test.invalid'),
  ('00000000-0000-4000-8000-0000000014a1', 'faux.14a@test.invalid'),
  ('00000000-0000-4000-8000-0000000014b1', 'faux.14b@test.invalid'),
  ('00000000-0000-4000-8000-0000000014c1', 'faux.14c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000014ad');

-- ---------- 1. Réglage et colonnes ----------
do $$
declare p public.parametres%rowtype;
begin
  select * into p from public.parametres where cle = 'refus_uid_introuvable';
  insert into resultats (test, ok, detail) values ('Réglage « refus_uid_introuvable » : oui par défaut, section Site',
    found and p.valeur = 'true'::jsonb and p.type = 'booleen' and p.section = 'Site', coalesce(p.valeur::text, 'absent'));
end $$;

-- ---------- 2. Création avec vérifications, code Messenger et appel rattaché (rôle serveur) ----------
set local role service_role;
do $$
declare v_app bigint; v_cpt bigint; p public.membres_prives%rowtype; c public.comptes_jeu%rowtype; n int;
begin
  insert into public.volsever_appels (compte_id, resultat, pseudo_trouve, http) values (null, 'trouve', 'PKL¬Officiel', 200) returning id into v_app;
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000014a1','nom_gamer','Faux 14A',
    'email','14a@test.invalid','facebook','facebook.com/faux14a','pseudo','PKL¬Officiel','uid','9914001','empreinte_email','e14a','empreinte_facebook','f14a',
    'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true,'code_messenger','UV-ABC234','appel_volsever',v_app,
    'verifications', jsonb_build_object('volsever', jsonb_build_object('resultat','trouve','pseudo_declare','PKL Officiel','pseudo_officiel','PKL¬Officiel'),
                                        'email', jsonb_build_object('resultat','ok'))));
  select * into p from public.membres_prives where membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Vérifications et code Messenger enregistrés',
    p.code_messenger = 'UV-ABC234' and p.verifications->'volsever'->>'pseudo_officiel' = 'PKL¬Officiel' and p.verifications->'email'->>'resultat' = 'ok', p.verifications::text);
  select * into c from public.comptes_jeu where membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Pseudo officiel enregistré tel quel (tag « ¬ » gardé)', c.pseudo = 'PKL¬Officiel', c.pseudo);
  select compte_id into v_cpt from public.volsever_appels where id = v_app;
  insert into resultats (test, ok, detail) values ('Appel à volsever rattaché au nouveau compte', v_cpt = c.id, coalesce(v_cpt::text, 'null'));

  -- Sans vérifications (ancien format) : la création marche toujours
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000014b1','nom_gamer','Faux 14B',
    'email','14b@test.invalid','facebook','facebook.com/faux14b','pseudo','Pseudo14B','uid','9914002','empreinte_email','e14b','empreinte_facebook','f14b',
    'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  select * into p from public.membres_prives where membre_id = (select id from ids where nom = 'B');
  insert into resultats (test, ok, detail) values ('Sans vérifications : candidature créée, champs vides', p.verifications = '{}'::jsonb and p.code_messenger is null, p.verifications::text);

  begin
    perform public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000014c1','nom_gamer','Faux 14C',
      'email','14c@test.invalid','facebook','facebook.com/faux14c','pseudo','Pseudo14C','uid','9914003','empreinte_email','e14c','empreinte_facebook','f14c',
      'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true,'code_messenger','mauvais'));
    insert into resultats (test, ok, detail) values ('Code Messenger mal formé refusé', false, 'accepté');
  exception when check_violation then insert into resultats (test, ok, detail) values ('Code Messenger mal formé refusé', true, sqlerrm); end;

  begin
    perform public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000014c1','nom_gamer','Faux 14C',
      'email','14c@test.invalid','facebook','facebook.com/faux14c','pseudo','Pseudo14C','uid','9914001','empreinte_email','e14c','empreinte_facebook','f14c',
      'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
    insert into resultats (test, ok, detail) values ('UID déjà enregistré toujours refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('UID déjà enregistré toujours refusé', sqlerrm = 'DOUBLON_UID', sqlerrm); end;
  select count(*) into n from public.membres where nom_gamer = 'Faux 14C';
  insert into resultats (test, ok, detail) values ('Rien de créé pour les refus', n = 0, n || ' fiche(s)');
end $$;
reset role;

-- ---------- 3. Revérification (bouton « Revérifier », rôle serveur au nom de Katana) ----------
set local role service_role;
do $$
declare v jsonb; c public.comptes_jeu%rowtype; h text; n int; idb bigint := (select id from ids where nom = 'B');
begin
  begin perform public.noter_reverification('00000000-0000-4000-8000-0000000014b1', idb, 'trouve', 'X');
    insert into resultats (test, ok, detail) values ('Revérification réservée à Katana', false, 'permis');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Revérification réservée à Katana', true, sqlerrm); end;

  v := public.noter_reverification('00000000-0000-4000-8000-0000000014ad', idb, 'delai', null);
  insert into resultats (test, ok, detail) values ('volsever muet : noté, pseudo inchangé',
    v->>'resultat' = 'delai' and v->>'pseudo_declare' = 'Pseudo14B' and (select pseudo from public.comptes_jeu where membre_id = idb) = 'Pseudo14B', v::text);

  v := public.noter_reverification('00000000-0000-4000-8000-0000000014ad', idb, 'trouve', 'Pseudo14B¬Vrai');
  select * into c from public.comptes_jeu where membre_id = idb;
  select pseudo into h from public.pseudos_historique where compte_id = c.id and fin is null;
  select count(*) into n from public.pseudos_historique where compte_id = c.id;
  insert into resultats (test, ok, detail) values ('Pseudo trouvé : remplace celui de la candidature, sans ancien pseudo dans l''historique',
    c.pseudo = 'Pseudo14B¬Vrai' and h = 'Pseudo14B¬Vrai' and n = 1 and v->>'pseudo_declare' = 'Pseudo14B' and v->>'pseudo_officiel' = 'Pseudo14B¬Vrai', v::text);
  select count(*) into n from public.journal where type = 'Inscription' and objet = idb::text and decision like 'Revérification%';
  insert into resultats (test, ok, detail) values ('Revérifications inscrites au journal', n = 2, n || ' ligne(s)');

  begin perform public.noter_reverification('00000000-0000-4000-8000-0000000014ad', idb, 'bizarre', null);
    insert into resultats (test, ok, detail) values ('Résultat inconnu refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Résultat inconnu refusé', true, sqlerrm); end;
end $$;
reset role;

-- Une candidature traitée ne se revérifie plus
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000014ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000014ad', true);
set local role authenticated;
do $$ begin perform public.decider_inscription((select id from ids where nom = 'A'), 'refuser', 'Test 0014', null); end $$;
reset role;
set local role service_role;
do $$ begin
  begin perform public.noter_reverification('00000000-0000-4000-8000-0000000014ad', (select id from ids where nom = 'A'), 'trouve', 'X');
    insert into resultats (test, ok, detail) values ('Candidature traitée : plus de revérification', false, 'permis');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Candidature traitée : plus de revérification', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 4. Droits ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000014ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000014ad', true);
set local role authenticated;
do $$ begin
  begin perform public.noter_reverification('00000000-0000-4000-8000-0000000014ad', (select id from ids where nom = 'B'), 'trouve', 'X');
    insert into resultats (test, ok, detail) values ('Depuis le site (même Katana) : passer par volsever obligatoire', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Depuis le site (même Katana) : passer par volsever obligatoire', true, 'refusé'); end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000014b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000014b1', true);
set local role authenticated;
do $$
declare v_code text; n int;
begin
  select count(*) into n from public.membres_prives;
  insert into resultats (test, ok, detail) values ('Candidat : ne voit que sa propre fiche privée', n = 1, n || ' fiche(s)');
  update public.membres_prives set code_messenger = 'UV-ZZZZZZ', verifications = '{}'::jsonb;
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Candidat : ne modifie ni son code ni ses vérifications', n = 0, n || ' ligne(s)');
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
