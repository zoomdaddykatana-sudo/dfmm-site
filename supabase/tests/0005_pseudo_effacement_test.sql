-- =====================================================================
-- LEAGUE UV — DFMM · Test du lot 2C (pseudo avec volsever, effacement)
-- À exécuter APRÈS la migration 0005. Faux membres seulement (anciens matricules
-- fictifs 99021 et 99022). Aucun appel réel à volsever. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad05', 'faux.admin5@test.invalid'),
  ('00000000-0000-4000-8000-0000000005a1', 'faux.5a@test.invalid'),
  ('00000000-0000-4000-8000-0000000005b1', 'faux.5b@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad05');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99021, 'Faux 5A', '2026-11-18'), (99022, 'Faux 5B', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000005a1','nom_gamer','Faux 5A','nom_reel','Vrai Nom A','email','5a@x','date_naissance','2000-01-01','genre','Homme','facebook','fb/5a','pseudo','PKL¬Ancien','uid','9950001','empreinte_email','e5a','empreinte_facebook','f5a','residence','Madagascar','province','Antananarivo','zone','Périphérie','comprend_mg',true,'parle_mg',true,'origine_mg',true,'capture_profil','00000000-0000-4000-8000-0000000005a1/profil.jpg'));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000005b1','nom_gamer','Faux 5B','email','5b@x','facebook','fb/5b','pseudo','PseudoB','uid','9950002','empreinte_email','e5b','empreinte_facebook','f5b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad05"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad05', true);
set local role authenticated;
do $$ begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99021);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99022);
end $$;
reset role;

-- ---------- 1. Paramètres et accès ----------
do $$
declare n int;
begin
  select count(*) into n from public.parametres where section = 'Volsever';
  insert into resultats (test, ok, detail) values ('4 paramètres volsever réglables', n = 4, n || ' paramètre(s)');
end $$;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000005a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005a1', true);
set local role authenticated;
do $$
declare n int;
begin
  begin perform public.enregistrer_declaration_pseudo('00000000-0000-4000-8000-0000000005a1', 1, 'X', 'trouve', 'X');
    insert into resultats (test, ok, detail) values ('Membre : ne contourne pas volsever', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : ne contourne pas volsever', true, 'refusé'); end;
  begin perform public.effacer_donnees_membre(1);
    insert into resultats (test, ok, detail) values ('Membre : n''efface pas en direct', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : n''efface pas en direct', true, 'refusé'); end;
  select count(*) into n from public.volsever_appels;
  insert into resultats (test, ok, detail) values ('Membre : ne lit pas le journal des appels', n = 0, n || ' ligne(s)');
end $$;
reset role;

-- ---------- 2. Pseudo (résultats simulés de volsever, rôle serveur) ----------
set local role service_role;
do $$
declare a uuid := '00000000-0000-4000-8000-0000000005a1'; ca bigint; r text; p text; n int;
begin
  select id into ca from public.comptes_jeu where uid = '9950001';
  r := public.enregistrer_declaration_pseudo(a, ca, 'PKL¬Ancien', 'trouve', 'PKL¬Ancien');
  insert into resultats (test, ok, detail) values ('Pseudo identique : « conforme », rien ne change', r = 'conforme', r);
  r := public.enregistrer_declaration_pseudo(a, ca, '  PKL¬Nouveau ', 'trouve', 'PKL¬Nouveau');
  select pseudo into p from public.comptes_jeu where id = ca;
  select count(*) into n from public.pseudos_historique where compte_id = ca;
  insert into resultats (test, ok, detail) values ('Nouveau pseudo confirmé : « modifie », tag ¬ gardé, historique daté', r = 'modifie' and p = 'PKL¬Nouveau' and n = 2, r || ', ' || p || ', ' || n || ' pseudo(s)');
  r := public.enregistrer_declaration_pseudo(a, ca, 'PKL¬Autre', 'trouve', 'PKL¬Profil');
  select pseudo into p from public.comptes_jeu where id = ca;
  select count(*) into n from public.demandes where type = 'pseudo' and statut = 'en_attente' and details->>'compte_id' = ca::text;
  insert into resultats (test, ok, detail) values ('Écart : le pseudo du profil remplace, demande de vérification', r = 'ecart' and p = 'PKL¬Profil' and n = 1, r || ', ' || p);
  begin perform public.enregistrer_declaration_pseudo(a, ca, 'Encore', 'trouve', 'Encore');
    insert into resultats (test, ok, detail) values ('Une seule déclaration en attente par compte', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Une seule déclaration en attente par compte', true, sqlerrm); end;
end $$;
do $$
declare b uuid := '00000000-0000-4000-8000-0000000005b1'; cb bigint; r text; p text; raison text;
begin
  select id into cb from public.comptes_jeu where uid = '9950002';
  r := public.enregistrer_declaration_pseudo(b, cb, 'PseudoB2', 'delai', null);
  select pseudo into p from public.comptes_jeu where id = cb;
  select details->>'raison' into raison from public.demandes where type = 'pseudo' and details->>'compte_id' = cb::text;
  insert into resultats (test, ok, detail) values ('volsever muet : en attente, pseudo inchangé', r = 'attente' and p = 'PseudoB' and raison like '%pas répondu%', r || ', ' || p || ', ' || raison);
  begin perform public.enregistrer_declaration_pseudo(b, (select id from public.comptes_jeu where uid = '9950001'), 'Vol', 'trouve', 'Vol');
    insert into resultats (test, ok, detail) values ('Pas de déclaration sur le compte d''un autre', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Pas de déclaration sur le compte d''un autre', true, sqlerrm); end;
  insert into public.volsever_appels (compte_id, resultat) values (cb, 'delai');
  insert into resultats (test, ok, detail) values ('Le serveur note chaque appel à volsever', true, '');
end $$;
reset role;

-- ---------- 3. Administrateur : validation manuelle du pseudo ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad05"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad05', true);
set local role authenticated;
do $$
declare d bigint; p text; n int;
begin
  select id into d from public.demandes where type = 'pseudo' and details->>'uid' = '9950002';
  perform public.decider_demande(d, 'accepter', null, 'PseudoB2');
  select pseudo into p from public.comptes_jeu where uid = '9950002';
  insert into resultats (test, ok, detail) values ('Admin : valide à la main le pseudo en attente', p = 'PseudoB2', p);
  select count(*) into n from public.volsever_appels;
  insert into resultats (test, ok, detail) values ('Admin : lit le journal des appels (compteur)', n >= 1, n || ' appel(s)');
end $$;
reset role;

-- ---------- 4. Effacement des données ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000005a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005a1', true);
set local role authenticated;
do $$ begin
  perform public.demander_effacement();
  insert into resultats (test, ok, detail) values ('Membre : demande l''effacement de ses données', true, '');
  begin perform public.demander_effacement();
    insert into resultats (test, ok, detail) values ('Une seule demande d''effacement à la fois', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Une seule demande d''effacement à la fois', true, sqlerrm); end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad05"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad05', true);
set local role authenticated;
do $$ begin
  begin perform public.decider_demande((select id from public.demandes where type = 'effacement' limit 1), 'accepter');
    insert into resultats (test, ok, detail) values ('Admin : l''effacement passe par la fonction prévue', false, 'accepté ailleurs');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Admin : l''effacement passe par la fonction prévue', true, sqlerrm); end;
end $$;
reset role;
set local role service_role;
do $$
declare ida bigint; r jsonb; p public.membres_prives%rowtype; m public.membres%rowtype; n int; s text;
begin
  ida := (select id from ids where nom = 'A');
  r := public.effacer_donnees_membre((select id from public.demandes where type = 'effacement' and membre_id = ida));
  select * into p from public.membres_prives where membre_id = ida;
  select * into m from public.membres where id = ida;
  insert into resultats (test, ok, detail) values ('Effacés : nom réel, naissance, genre, résidence, langues, e-mail, Facebook, capture',
    p.nom_reel is null and p.date_naissance is null and p.genre is null and p.residence is null and p.province is null and p.comprend_mg is null
    and p.parle_mg is null and p.email is null and p.facebook is null and p.capture_profil is null, '');
  select count(*) into n from public.comptes_jeu where membre_id = ida;
  insert into resultats (test, ok, detail) values ('Gardés : empreintes, matricule, UID, pseudos',
    m.empreinte_email = 'e5a' and m.empreinte_facebook = 'f5a' and m.matricule = 99021 and n = 1 and m.donnees_effacees, '');
  insert into resultats (test, ok, detail) values ('Renvoie le compte et la capture à supprimer',
    r->>'user_id' = '00000000-0000-4000-8000-0000000005a1' and r->'captures' ? '00000000-0000-4000-8000-0000000005a1/profil.jpg', r::text);
  select statut into s from public.demandes where type = 'effacement' and membre_id = ida;
  insert into resultats (test, ok, detail) values ('La demande d''effacement est close', s = 'acceptee', s);
  begin perform public.effacer_donnees_membre((select id from public.demandes where type = 'effacement' and membre_id = ida));
    insert into resultats (test, ok, detail) values ('Un effacement ne se rejoue pas', false, 'rejoué');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un effacement ne se rejoue pas', true, sqlerrm); end;
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
