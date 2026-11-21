-- =====================================================================
-- LEAGUE UV — DFMM · Test du lot 2B (comptes, demandes, retrait, réintégration)
-- À exécuter dans Supabase APRÈS la migration 0004 : SQL Editor > New query > Run.
-- Faux membres seulement (anciens matricules fictifs 99011 et 99012 : le compteur
-- des vrais matricules n'est jamais utilisé). Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad04', 'faux.admin4@test.invalid'),
  ('00000000-0000-4000-8000-0000000004a1', 'faux.4a@test.invalid'),
  ('00000000-0000-4000-8000-0000000004b1', 'faux.4b@test.invalid'),
  ('00000000-0000-4000-8000-0000000004c1', 'faux.4c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad04');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99011, 'Faux 4A', '2026-11-18'), (99012, 'Faux 4B', '2026-11-18');

-- Création des faux membres A et B (actifs) et du faux candidat C (en attente)
set local role service_role;
do $$
begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000004a1','nom_gamer','Faux 4A','email','4a@x','facebook','fb/4a','pseudo','PseudoA1','uid','9940001','empreinte_email','e4a','empreinte_facebook','f4a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000004b1','nom_gamer','Faux 4B','email','4b@x','facebook','fb/4b','pseudo','PseudoB1','uid','9940002','empreinte_email','e4b','empreinte_facebook','f4b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'C', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000004c1','nom_gamer','Faux 4C','email','4c@x','facebook','fb/4c','pseudo','PseudoC1','uid','9940003','empreinte_email','e4c','empreinte_facebook','f4c','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad04"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad04', true);
set local role authenticated;
do $$ begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99011);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99012);
end $$;
reset role;

-- ---------- 1. Membre A : demandes ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000004a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000004a1', true);
set local role authenticated;
do $$
declare n int; idb bigint;
begin
  begin perform public.demander_compte2('PseudoA2', '9940011', 'Nouveau téléphone', null, false);
    insert into resultats (test, ok, detail) values ('A : 2e compte sans capture refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : 2e compte sans capture refusé', true, sqlerrm); end;
  begin perform public.demander_compte2('PseudoA2', '9940011', 'Nouveau téléphone', '00000000-0000-4000-8000-0000000004b1/x.jpg', false);
    insert into resultats (test, ok, detail) values ('A : capture dans le dossier d''un autre refusée', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : capture dans le dossier d''un autre refusée', true, sqlerrm); end;
  begin perform public.demander_compte2('PseudoA2', '9940002', 'UID de B', '00000000-0000-4000-8000-0000000004a1/x.jpg', false);
    insert into resultats (test, ok, detail) values ('A : UID d''un autre membre refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : UID d''un autre membre refusé', true, sqlerrm); end;
  perform public.demander_compte2('PseudoA2', '9940011', 'Nouveau téléphone', '00000000-0000-4000-8000-0000000004a1/x.jpg', false);
  insert into resultats (test, ok, detail) values ('A : demande de 2e compte déposée', true, '');
  begin perform public.demander_compte2('PseudoA3', '9940012', 'Encore', '00000000-0000-4000-8000-0000000004a1/y.jpg', false);
    insert into resultats (test, ok, detail) values ('A : une seule demande de 2e compte à la fois', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : une seule demande de 2e compte à la fois', true, sqlerrm); end;
  select c.id into idb from public.comptes_jeu c where c.uid = '9940002';
  insert into resultats (test, ok, detail) values ('A : ne voit pas les comptes de B', idb is null, coalesce(idb::text, 'invisible'));
  begin perform public.decider_demande((select id from public.demandes limit 1), 'accepter');
    insert into resultats (test, ok, detail) values ('A : ne peut pas décider d''une demande', false, 'décidé');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : ne peut pas décider d''une demande', true, sqlerrm); end;
  begin perform public.activer_compte(1, 1);
    insert into resultats (test, ok, detail) values ('A : n''active pas un compte en direct', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('A : n''active pas un compte en direct', true, 'refusé'); end;
  begin insert into public.notifications (membre_id, texte) values ((select id from public.membres limit 1), 'Faux message');
    insert into resultats (test, ok, detail) values ('A : ne crée pas de notification', false, 'créée');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('A : ne crée pas de notification', true, 'refusé'); end;
  begin insert into storage.objects (bucket_id, name) values ('profils', '00000000-0000-4000-8000-0000000004a1/z.jpg');
    insert into resultats (test, ok, detail) values ('A : dépose une capture dans son dossier', true, '');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('A : dépose une capture dans son dossier', false, 'refusé'); end;
  begin insert into storage.objects (bucket_id, name) values ('profils', '00000000-0000-4000-8000-0000000004b1/z.jpg');
    insert into resultats (test, ok, detail) values ('A : ne dépose rien dans le dossier de B', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('A : ne dépose rien dans le dossier de B', true, 'refusé'); end;
end $$;
reset role;

-- ---------- 2. Candidat C (en attente) ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000004c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000004c1', true);
set local role authenticated;
do $$ begin
  begin perform public.demander_retrait('test');
    insert into resultats (test, ok, detail) values ('C (en attente) : aucune démarche de membre', false, 'permise');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('C (en attente) : aucune démarche de membre', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 3. Membre B : une demande en cours ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000004b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000004b1', true);
set local role authenticated;
do $$ begin perform public.demander_compte2('PseudoB2', '9940021', 'Second compte', '00000000-0000-4000-8000-0000000004b1/b.jpg', false); end $$;
reset role;

-- ---------- 4. Administrateur : décisions ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad04"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad04', true);
set local role authenticated;
do $$
declare da bigint; ida bigint; n int; s text;
begin
  ida := (select id from ids where nom = 'A');
  select id into da from public.demandes where membre_id = ida and type = 'compte2';
  begin perform public.decider_demande(da, 'precisions', ' ');
    insert into resultats (test, ok, detail) values ('Admin : précisions sans motif impossibles', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Admin : précisions sans motif impossibles', true, sqlerrm); end;
  perform public.decider_demande(da, 'accepter');
  select count(*) into n from public.comptes_jeu where membre_id = ida;
  select statut into s from public.comptes_jeu where uid = '9940011';
  insert into resultats (test, ok, detail) values ('Admin : 2e compte ajouté, en pause', n = 2 and s = 'en_pause', n || ' compte(s), ' || s);
end $$;
reset role;

-- ---------- 5. Membre A : limite, changement de compte actif, délai ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000004a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000004a1', true);
set local role authenticated;
do $$
declare c2 bigint;
begin
  begin perform public.demander_compte2('PseudoA3', '9940012', 'Troisième', '00000000-0000-4000-8000-0000000004a1/y.jpg', false);
    insert into resultats (test, ok, detail) values ('A : pas de 3e compte (limite réglable : 2)', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : pas de 3e compte (limite réglable : 2)', true, sqlerrm); end;
  select id into c2 from public.comptes_jeu where uid = '9940011';
  perform public.demander_compte_actif(c2, 'Je joue sur mon nouveau téléphone');
  insert into resultats (test, ok, detail) values ('A : demande de changement de compte actif déposée', true, '');
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad04"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad04', true);
set local role authenticated;
do $$
declare ida bigint; s1 text; s2 text; n int; dc timestamptz;
begin
  ida := (select id from ids where nom = 'A');
  perform public.decider_demande((select id from public.demandes where membre_id = ida and type = 'compte_actif'), 'accepter');
  select statut into s1 from public.comptes_jeu where uid = '9940001';
  select statut into s2 from public.comptes_jeu where uid = '9940011';
  insert into resultats (test, ok, detail) values ('Admin : changement accepté, un seul compte actif', s1 = 'en_pause' and s2 = 'actif', 'ancien ' || s1 || ', nouveau ' || s2);
  select count(*) into n from public.comptes_periodes cp join public.comptes_jeu c on c.id = cp.compte_id where c.membre_id = ida and cp.fin is null;
  insert into resultats (test, ok, detail) values ('Admin : une seule période de compte ouverte', n = 1, n || ' période(s) ouverte(s)');
  select dernier_changement_compte into dc from public.membres where id = ida;
  insert into resultats (test, ok, detail) values ('Admin : la date du changement lance le délai', dc is not null, coalesce(dc::text, 'vide'));
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000004a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000004a1', true);
set local role authenticated;
do $$
declare c1 bigint; n int; nb int;
begin
  select id into c1 from public.comptes_jeu where uid = '9940001';
  begin perform public.demander_compte_actif(c1, 'Retour');
    insert into resultats (test, ok, detail) values ('A : nouveau changement avant 7 jours refusé', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('A : nouveau changement avant 7 jours refusé', true, sqlerrm); end;
  select count(*) into n from public.notifications;
  insert into resultats (test, ok, detail) values ('A : reçoit ses notifications', n >= 2, n || ' notification(s)');
  update public.notifications set lu = true
    where membre_id in (select id from public.membres where user_id = '00000000-0000-4000-8000-0000000004a1');
  get diagnostics nb = row_count;
  insert into resultats (test, ok, detail) values ('A : marque ses notifications comme lues', nb = n, nb || ' ligne(s)');
  begin update public.notifications set texte = 'modifié'
    where membre_id in (select id from public.membres where user_id = '00000000-0000-4000-8000-0000000004a1');
    insert into resultats (test, ok, detail) values ('A : ne réécrit pas une notification', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('A : ne réécrit pas une notification', true, 'refusé'); end;
  -- Retrait automatique
  perform public.demander_retrait('Pause études');
end $$;
reset role;

-- ---------- 6. Administrateur : effets du retrait, puis réintégration ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad04"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad04', true);
set local role authenticated;
do $$
declare ida bigint; idb bigint; s text; n1 int; n2 int; nb int; c1 bigint;
begin
  ida := (select id from ids where nom = 'A'); idb := (select id from ids where nom = 'B');
  select statut into s from public.membres where id = ida;
  select count(*) into n1 from public.periodes where membre_id = ida and fin is null;
  select count(*) into n2 from public.comptes_jeu where membre_id = ida and statut = 'actif';
  insert into resultats (test, ok, detail) values ('Retrait automatique : statut, période fermée, comptes en pause', s = 'retire' and n1 = 0 and n2 = 0, s || ', ' || n1 || ' période ouverte, ' || n2 || ' compte actif');
  select count(*) into nb from public.demandes where membre_id = idb and statut = 'en_attente';
  insert into resultats (test, ok, detail) values ('Retrait de A : la demande de B n''est pas touchée', nb = 1, nb || ' demande(s) de B en attente');
  select id into c1 from public.comptes_jeu where uid = '9940001';
  perform public.reintegrer_membre(ida, c1, 'Retour après les examens');
  select statut into s from public.membres where id = ida;
  select count(*) into n1 from public.periodes where membre_id = ida;
  select statut into s from public.comptes_jeu where id = c1;
  insert into resultats (test, ok, detail) values ('Réintégration : même fiche, nouvelle période, compte actif', n1 = 2 and s = 'actif', n1 || ' période(s), compte ' || s);
  begin perform public.reintegrer_membre(ida, c1);
    insert into resultats (test, ok, detail) values ('Réintégration : seulement pour un membre retiré', false, 'rejouée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Réintégration : seulement pour un membre retiré', true, sqlerrm); end;
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
