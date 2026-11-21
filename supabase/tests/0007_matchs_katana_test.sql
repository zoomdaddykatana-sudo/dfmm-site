-- =====================================================================
-- LEAGUE UV — DFMM · Test du lot 3A (matchs de Katana, captures, registre)
-- À exécuter APRÈS la migration 0007. Faux membre seulement (ancien matricule fictif 99031),
-- fausse saison et faux match. Aucun fichier envoyé. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad07', 'faux.admin7@test.invalid'),
  ('00000000-0000-4000-8000-0000000007a1', 'faux.7a@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad07');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99031, 'Faux 7A', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000007a1','nom_gamer','Faux 7A','email','7a@x','facebook','fb/7a','pseudo','PKL¬Sept','uid','9970001','empreinte_email','e7a','empreinte_facebook','f7a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad07"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad07', true);
set local role authenticated;
do $$ begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99031);
  insert into public.saisons (nom, debut, fin) values ('Saison test 0007', '2026-11-10', '2027-01-21');
  insert into ids select 'S', id from public.saisons where nom = 'Saison test 0007';
  insert into ids select 'C', id from public.comptes_jeu where uid = '9970001';
end $$;
reset role;

-- ---------- 1. Visiteur et membre : aucun accès aux matchs ----------
set local role anon;
do $$
declare n int;
begin
  begin select count(*) into n from public.matchs;
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas les matchs', false, n || ' ligne(s)');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas les matchs', true, 'refusé'); end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000007a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000007a1', true);
set local role authenticated;
do $$
declare n int;
begin
  begin perform public.enregistrer_match(jsonb_build_object('saison_id', (select id from ids where nom = 'S')));
    insert into resultats (test, ok, detail) values ('Membre : n''enregistre pas de match', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre : n''enregistre pas de match', true, sqlerrm); end;
  begin perform public.activer_saison((select id from ids where nom = 'S'));
    insert into resultats (test, ok, detail) values ('Membre : n''active pas de saison', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre : n''active pas de saison', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 2. Administrateur : saison active, match de démarrage ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad07"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad07', true);
set local role authenticated;
do $$
declare s bigint := (select id from ids where nom = 'S'); c bigint := (select id from ids where nom = 'C');
        v_m bigint; n int; b boolean; d timestamptz;
begin
  perform public.activer_saison(s);
  select count(*) into n from public.saisons where active;
  select active into b from public.saisons where id = s;
  insert into resultats (test, ok, detail) values ('Une seule saison active : celle choisie', n = 1 and b, n || ' active(s)');

  v_m := public.enregistrer_match(jsonb_build_object('saison_id', s, 'carte', 'Faille', 'fin', '2026-11-18T16:40:00+03:00',
    'lignes', jsonb_build_array(
      jsonb_build_object('faction','HAAVK','pseudo','PKL¬Sept','compte_id',c,'resolution','auto','score',2450,'elim',12,'morts',5,'assist',3,'med',0,'ing',450,'obj',120,'tac',300),
      jsonb_build_object('faction','GTI','pseudo','Invité','resolution','non_inscrit','score',2100,'elim',8,'morts',6,'assist',4,'med',150,'ing',0,'obj',90,'tac',45),
      jsonb_build_object('faction','GTI','pseudo','PKL¬Sep','resolution','a_identifier','score',900,'elim',2,'morts',9,'assist',1,'med',0,'ing',0,'obj',10,'tac',5))));
  insert into ids values ('M', v_m);
  select demarrage into b from public.matchs where id = v_m;
  insert into resultats (test, ok, detail) values ('Phase de démarrage : le match est une « saisie de démarrage »', b, coalesce(b::text, 'vide'));
  select count(*) into n from public.match_lignes where match_id = v_m and membre_id = (select id from ids where nom = 'A') and resolution = 'auto';
  insert into resultats (test, ok, detail) values ('La ligne du membre est reliée à sa fiche par son compte', n = 1, n || ' ligne(s)');
  select count(*) into n from public.registre where match_id = v_m and type = 'match_declare';
  insert into resultats (test, ok, detail) values ('Registre : « match déclaré »', n = 1, n || ' événement(s)');

  begin perform public.decider_match(v_m, 'valider');
    insert into resultats (test, ok, detail) values ('Pas de validation sans capture', false, 'validé');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Pas de validation sans capture', true, sqlerrm); end;

  insert into public.captures (match_id, chemin, envoyee_le) values (v_m, v_m || '/essai.jpg', '2000-01-01T00:00:00Z');
  select envoyee_le into d from public.captures where match_id = v_m;
  insert into resultats (test, ok, detail) values ('Heure d''envoi fixée par le serveur (pas par le téléphone)', d > '2026-01-01'::timestamptz, d::text);
  select count(*) into n from public.registre where match_id = v_m and type = 'capture_recue';
  insert into resultats (test, ok, detail) values ('Registre : « capture reçue »', n = 1, n || ' événement(s)');

  begin perform public.decider_match(v_m, 'attente', '  ');
    insert into resultats (test, ok, detail) values ('Mise en attente : motif obligatoire', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Mise en attente : motif obligatoire', true, sqlerrm); end;

  perform public.decider_match(v_m, 'valider');
  select count(*) into n from public.matchs where id = v_m and statut = 'valide' and valide_le is not null;
  insert into resultats (test, ok, detail) values ('Validation : match « validé », date notée', n = 1, '');
  select count(*) into n from public.captures where match_id = v_m and statut = 'retenue';
  insert into resultats (test, ok, detail) values ('Validation : capture retenue', n = 1, n || ' capture(s)');
  select count(*) into n from public.registre where match_id = v_m and type in ('capture_acceptee', 'decision');
  insert into resultats (test, ok, detail) values ('Registre : « capture acceptée » et « décision »', n = 2, n || ' événement(s)');
  select count(*) into n from public.journal where objet = 'M-' || v_m;
  insert into resultats (test, ok, detail) values ('Journal des décisions : validation notée', n = 1, n || ' ligne(s)');

  begin perform public.enregistrer_match(jsonb_build_object('id', v_m, 'saison_id', s));
    insert into resultats (test, ok, detail) values ('Match validé : plus modifiable sans repasser en brouillon', false, 'modifié');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Match validé : plus modifiable sans repasser en brouillon', true, sqlerrm); end;
  begin insert into public.captures (match_id, chemin) values (v_m, v_m || '/tard.jpg');
    insert into resultats (test, ok, detail) values ('Match validé : pas de nouvelle capture', false, 'ajoutée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Match validé : pas de nouvelle capture', true, sqlerrm); end;
end $$;

-- ---------- 3. Ligne à identifier après la validation ----------
do $$
declare v_m bigint := (select id from ids where nom = 'M'); l bigint; r text; d timestamptz;
begin
  select id into l from public.match_lignes where match_id = v_m and pseudo = 'PKL¬Sep';
  begin perform public.identifier_ligne(l, (select id from ids where nom = 'C'));
    insert into resultats (test, ok, detail) values ('Un joueur ne figure qu''une fois par match', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un joueur ne figure qu''une fois par match', true, sqlerrm); end;
  perform public.identifier_ligne(l, null);
  select resolution, identifie_le into r, d from public.match_lignes where id = l;
  insert into resultats (test, ok, detail) values ('Ligne identifiée après validation : datée (classements suivants)', r = 'non_inscrit_confirme' and d is not null, r);
end $$;

-- ---------- 4. Registre intouchable, retour en brouillon, refus ----------
do $$
declare v_m bigint := (select id from ids where nom = 'M'); n int; s text;
begin
  begin update public.registre set detail = 'modifié' where match_id = v_m;
    insert into resultats (test, ok, detail) values ('Le registre ne se modifie pas', false, 'modifié');
  exception when insufficient_privilege or raise_exception then insert into resultats (test, ok, detail) values ('Le registre ne se modifie pas', true, 'refusé'); end;
  perform public.decider_match(v_m, 'brouillon', 'Erreur de saisie à corriger');
  select statut into s from public.matchs where id = v_m;
  select count(*) into n from public.captures where match_id = v_m and statut = 'recue';
  insert into resultats (test, ok, detail) values ('Retour en brouillon (avec motif) : capture à nouveau « reçue »', s = 'brouillon' and n = 1, s);
  perform public.decider_match(v_m, 'refuser', 'Capture floue');
  select statut into s from public.matchs where id = v_m;
  select count(*) into n from public.captures where match_id = v_m and statut = 'refusee' and motif = 'Capture floue';
  insert into resultats (test, ok, detail) values ('Refus : match gardé avec le motif, capture refusée', s = 'refuse' and n = 1, s);
end $$;
reset role;

-- ---------- 5. Le membre ne voit ni les matchs ni le registre ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000007a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000007a1', true);
set local role authenticated;
do $$
declare n int; k int;
begin
  select count(*) into n from public.matchs;
  select count(*) into k from public.registre;
  insert into resultats (test, ok, detail) values ('Membre : ne lit ni les matchs ni le registre', n = 0 and k = 0, n || ' match(s), ' || k || ' événement(s)');
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
