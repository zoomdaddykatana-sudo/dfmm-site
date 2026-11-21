-- =====================================================================
-- LEAGUE UV — DFMM · Test du lot 4B (matchs en attente et litiges)
-- À exécuter APRÈS la migration 0010. Faux membres seulement (anciens matricules fictifs 99051,
-- 99052, 99053), fausse saison, faux matchs, fausses captures (aucun fichier). Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'faux.admin10@test.invalid'),
  ('00000000-0000-4000-8000-0000000010a1', 'faux.10a@test.invalid'),
  ('00000000-0000-4000-8000-0000000010b1', 'faux.10b@test.invalid'),
  ('00000000-0000-4000-8000-0000000010c1', 'faux.10c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000000a1');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99051, 'Faux 10A', '2026-11-18'), (99052, 'Faux 10B', '2026-11-18'), (99053, 'Faux 10C', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000010a1','nom_gamer','Faux 10A','email','10a@x','facebook','fb/10a','pseudo','Dix A','uid','9910001','empreinte_email','e10a','empreinte_facebook','f10a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000010b1','nom_gamer','Faux 10B','email','10b@x','facebook','fb/10b','pseudo','Dix B','uid','9910002','empreinte_email','e10b','empreinte_facebook','f10b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'C', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000010c1','nom_gamer','Faux 10C','email','10c@x','facebook','fb/10c','pseudo','Dix C','uid','9910003','empreinte_email','e10c','empreinte_facebook','f10c','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;

-- ---------- Préparation : 2 matchs avec 2 captures chacun, mis en attente ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
set local role authenticated;
do $$
declare s bigint; m1 bigint; m2 bigint; lignes jsonb; n int;
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99051);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99052);
  perform public.decider_inscription((select id from ids where nom = 'C'), 'approuver', null, 99053);
  insert into public.saisons (nom, debut, fin) values ('Saison test 0010', '2026-11-10', '2027-01-21') returning id into s;
  lignes := jsonb_build_array(
    jsonb_build_object('faction','HAAVK','pseudo','Dix A','compte_id',(select id from public.comptes_jeu where uid = '9910001'),'resolution','auto','score',100,'elim',1,'morts',1,'assist',1,'med',0,'ing',0,'obj',0,'tac',0),
    jsonb_build_object('faction','GTI','pseudo','Dix B','compte_id',(select id from public.comptes_jeu where uid = '9910002'),'resolution','auto','score',90,'elim',1,'morts',1,'assist',1,'med',0,'ing',0,'obj',0,'tac',0));
  m1 := public.enregistrer_match(jsonb_build_object('saison_id', s, 'fin', '2026-11-18T16:40:00+03:00', 'lignes', lignes));
  m2 := public.enregistrer_match(jsonb_build_object('saison_id', s, 'fin', '2026-11-21T16:40:00+03:00', 'lignes', lignes));
  insert into ids values ('M1', m1), ('M2', m2);
  insert into public.captures (match_id, chemin) values (m1, m1 || '/a.jpg'), (m1, m1 || '/b.jpg'), (m2, m2 || '/a.jpg'), (m2, m2 || '/b.jpg');
  insert into ids select 'CAP1', min(id) from public.captures where match_id = m1;
  insert into ids select 'CAP2', max(id) from public.captures where match_id = m1;
  perform public.decider_match(m1, 'attente', 'Deux captures différentes');
  perform public.decider_match(m2, 'attente', 'Heure de fin hors de la plage');
  insert into ids select 'D1', id from public.dossiers where match_id = m1;
  insert into ids select 'D2', id from public.dossiers where match_id = m2;
  select count(*) into n from public.dossiers where match_id in (m1, m2) and statut = 'ouvert';
  insert into resultats (test, ok, detail) values ('Un dossier s''ouvre tout seul pour chaque match mis en attente', n = 2, n || ' dossier(s)');

  perform public.qualifier_dossier((select id from ids where nom = 'D1'), true, 'Deux captures avec des scores différents');
  select count(*) into n from public.registre where match_id = m1 and type = 'litige_ouvert';
  insert into resultats (test, ok, detail) values ('Litige qualifié : noté au registre', n = 1, n || ' événement(s)');

  perform public.convoquer((select id from ids where nom = 'D1'), (select id from ids where nom = 'A'), 'responsable');
  perform public.convoquer((select id from ids where nom = 'D1'), (select id from ids where nom = 'B'), 'temoin');
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'A') and texte like 'Katana vous convoque%';
  insert into resultats (test, ok, detail) values ('Convocation : le membre est averti (12 h, confidentialité)', n = 1, n || ' notification(s)');
  begin perform public.convoquer((select id from ids where nom = 'D1'), (select id from ids where nom = 'A'), 'joueur');
    insert into resultats (test, ok, detail) values ('Pas de double convocation', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Pas de double convocation', true, sqlerrm); end;
  perform public.ecrire_litige((select id from ids where nom = 'D1'), 'Envoyez-moi vos explications.');
end $$;
reset role;

-- ---------- Convoqué : voit le dossier, confirme, écrit ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000010a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010a1', true);
set local role authenticated;
do $$
declare n int; k int;
begin
  select count(*) into n from public.dossiers;
  select count(*) into k from public.messages_litige;
  insert into resultats (test, ok, detail) values ('Convoqué : voit son dossier et la discussion (pas l''autre dossier)', n = 1 and k = 1, n || ' dossier(s), ' || k || ' message(s)');
  perform public.confirmer_convocation((select id from ids where nom = 'D1'));
  select count(*) into n from public.convocations where confirme_le is not null;
  insert into resultats (test, ok, detail) values ('Convoqué : confirme la réception', n = 1, n || ' confirmation(s)');
  perform public.ecrire_litige((select id from ids where nom = 'D1'), 'La capture b est la bonne.');
  begin perform public.ecrire_litige((select id from ids where nom = 'D2'), 'Intrusion');
    insert into resultats (test, ok, detail) values ('Convoqué : n''écrit pas dans un autre dossier', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Convoqué : n''écrit pas dans un autre dossier', true, sqlerrm); end;
end $$;
reset role;

-- ---------- Non convoqué et visiteur : rien ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000010c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010c1', true);
set local role authenticated;
do $$
declare n int; k int;
begin
  select count(*) into n from public.dossiers;
  select count(*) into k from public.messages_litige;
  insert into resultats (test, ok, detail) values ('Non convoqué : ne voit ni dossier ni discussion', n = 0 and k = 0, n || ' dossier(s), ' || k || ' message(s)');
  begin perform public.ecrire_litige((select id from ids where nom = 'D1'), 'Je m''en mêle');
    insert into resultats (test, ok, detail) values ('Non convoqué : n''écrit pas', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Non convoqué : n''écrit pas', true, sqlerrm); end;
end $$;
reset role;
set local role anon;
do $$
declare n int;
begin
  begin select count(*) into n from public.messages_litige;
    insert into resultats (test, ok, detail) values ('Visiteur : aucun accès aux litiges', false, n || ' ligne(s)');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : aucun accès aux litiges', true, 'refusé'); end;
end $$;
reset role;

-- ---------- Décision, sanction liée, suppression des captures écartées, synthèse ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
set local role authenticated;
do $$
declare d1 bigint := (select id from ids where nom = 'D1'); d2 bigint := (select id from ids where nom = 'D2');
        m1 bigint := (select id from ids where nom = 'M1'); m2 bigint := (select id from ids where nom = 'M2');
        n int; st text; v bigint; ch text[];
begin
  begin perform public.trancher_dossier(d1, 'capture_retenue', (select id from ids where nom = 'CAP2'), ' ');
    insert into resultats (test, ok, detail) values ('Décision : motif obligatoire', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Décision : motif obligatoire', true, sqlerrm); end;
  begin perform public.trancher_dossier(d1, 'capture_retenue', (select min(id) from public.captures where match_id = m2), 'x');
    insert into resultats (test, ok, detail) values ('Décision : la vraie capture doit être une capture de ce match', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Décision : la vraie capture doit être une capture de ce match', true, sqlerrm); end;

  perform public.trancher_dossier(d1, 'capture_retenue', (select id from ids where nom = 'CAP2'), 'Capture b confirmée par les deux responsables');
  select statut into st from public.matchs where id = m1;
  insert into resultats (test, ok, detail) values ('Vraie capture retenue : match validé', st = 'valide', st);
  insert into resultats (test, ok, detail) values ('Vraie capture « retenue », l''autre « écartée »',
    (select statut from public.captures where id = (select id from ids where nom = 'CAP2')) = 'retenue'
    and (select statut from public.captures where id = (select id from ids where nom = 'CAP1')) = 'ecartee', '');
  select statut into st from public.dossiers where id = d1;
  select count(*) into n from public.notifications where texte like 'Le dossier n° ' || d1 || '%tranché%';
  insert into resultats (test, ok, detail) values ('Dossier tranché, convoqués avertis', st = 'tranche' and n = 2, st || ', ' || n || ' notification(s)');

  v := public.sanctionner(jsonb_build_object('membre_id', (select id from ids where nom = 'B'), 'type', 'avertissement', 'motif', 'Capture trompeuse'));
  perform public.sanctionner_dossier(v, d1);
  begin ch := public.captures_a_supprimer(d1);
    insert into resultats (test, ok, detail) values ('Avec sanction : captures écartées gardées jusqu''à la fin du recours', false, 'possible tout de suite');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Avec sanction : captures écartées gardées jusqu''à la fin du recours', true, sqlerrm); end;
  perform public.decider_sanction(v, 'lever', 'Simple malentendu');
  ch := public.captures_a_supprimer(d1);
  insert into resultats (test, ok, detail) values ('Sanction levée : suppression possible, seule la capture écartée est visée', array_length(ch, 1) = 1 and ch[1] = m1 || '/a.jpg', array_to_string(ch, ', '));
  perform public.noter_captures_supprimees(d1);
  select count(*) into n from public.registre where match_id = m1 and detail like '%supprimée%';
  insert into resultats (test, ok, detail) values ('Suppression notée au registre (historique gardé)', n = 1, n || ' événement(s)');

  begin perform public.valider_synthese(d2, 'Trop tôt');
    insert into resultats (test, ok, detail) values ('Synthèse : seulement après la décision', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Synthèse : seulement après la décision', true, sqlerrm); end;
  perform public.valider_synthese(d1, 'Synthèse : la capture b était la bonne ; avertissement levé.');
  select statut into st from public.dossiers where id = d1;
  insert into resultats (test, ok, detail) values ('Synthèse validée : dossier archivé', st = 'archive', st);

  perform public.trancher_dossier(d2, 'match_annule', null, 'Résultat introuvable');
  select statut into st from public.matchs where id = m2;
  select count(*) into n from public.captures where match_id = m2 and statut = 'ecartee';
  insert into resultats (test, ok, detail) values ('Match annulé : toutes ses captures écartées', st = 'annule' and n = 2, st || ', ' || n || ' écartée(s)');
  ch := public.captures_a_supprimer(d2);
  insert into resultats (test, ok, detail) values ('Sans sanction : suppression possible tout de suite', array_length(ch, 1) = 2, array_length(ch, 1) || ' fichier(s)');
end $$;
reset role;

-- ---------- Discussion fermée après la décision ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000010a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010a1', true);
set local role authenticated;
do $$ begin
  begin perform public.ecrire_litige((select id from ids where nom = 'D1'), 'Encore un mot');
    insert into resultats (test, ok, detail) values ('Discussion fermée à la décision', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Discussion fermée à la décision', true, sqlerrm); end;
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
