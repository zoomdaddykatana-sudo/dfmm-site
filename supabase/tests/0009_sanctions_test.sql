-- =====================================================================
-- LEAGUE UV — DFMM · Test du lot 4A (sanctions)
-- À exécuter APRÈS la migration 0009. Faux membres seulement (anciens matricules fictifs 99041 et
-- 99042), fausse saison, faux match. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad09', 'faux.admin9@test.invalid'),
  ('00000000-0000-4000-8000-0000000009a1', 'faux.9a@test.invalid'),
  ('00000000-0000-4000-8000-0000000009b1', 'faux.9b@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad09');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99041, 'Faux 9A', '2026-11-18'), (99042, 'Faux 9B', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000009a1','nom_gamer','Faux 9A','email','9a@x','facebook','fb/9a','pseudo','Neuf A','uid','9990001','empreinte_email','e9a','empreinte_facebook','f9a','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000009b1','nom_gamer','Faux 9B','email','9b@x','facebook','fb/9b','pseudo','Neuf B','uid','9990002','empreinte_email','e9b','empreinte_facebook','f9b','residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad09"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad09', true);
set local role authenticated;
do $$
declare s bigint; v_m bigint;
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99041);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99042);
  insert into public.saisons (nom, debut, fin) values ('Saison test 0009', '2026-11-10', '2027-01-21') returning id into s;
  v_m := public.enregistrer_match(jsonb_build_object('saison_id', s, 'fin', '2026-11-18T16:40:00+03:00', 'lignes', jsonb_build_array(
    jsonb_build_object('faction','HAAVK','pseudo','Neuf A','compte_id',(select id from public.comptes_jeu where uid = '9990001'),'resolution','auto','score',100,'elim',1,'morts',1,'assist',1,'med',0,'ing',0,'obj',0,'tac',0))));
  insert into ids values ('M', v_m);
end $$;
reset role;

-- ---------- 1. Un membre ne sanctionne pas ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000009b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000009b1', true);
set local role authenticated;
do $$ begin
  begin perform public.sanctionner(jsonb_build_object('membre_id', (select id from ids where nom = 'A'), 'type', 'avertissement', 'motif', 'x'));
    insert into resultats (test, ok, detail) values ('Membre : ne sanctionne pas', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Membre : ne sanctionne pas', true, sqlerrm); end;
end $$;
reset role;

-- ---------- 2. Suspension : 14 jours au plus, démarches bloquées, retrait soumis à Katana ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad09"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad09', true);
set local role authenticated;
do $$
declare a bigint := (select id from ids where nom = 'A'); auj date := (now() at time zone 'Indian/Antananarivo')::date; v bigint; n int;
begin
  begin perform public.sanctionner(jsonb_build_object('membre_id', a, 'type', 'suspension', 'motif', 'Test', 'fin_jour', (auj + 15)::text));
    insert into resultats (test, ok, detail) values ('Suspension de plus de 14 jours refusée', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Suspension de plus de 14 jours refusée', true, sqlerrm); end;
  begin perform public.sanctionner(jsonb_build_object('membre_id', a, 'type', 'suspension', 'motif', '  ', 'fin_jour', (auj + 3)::text));
    insert into resultats (test, ok, detail) values ('Motif obligatoire', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Motif obligatoire', true, sqlerrm); end;
  v := public.sanctionner(jsonb_build_object('membre_id', a, 'type', 'suspension', 'motif', 'Comportement toxique répété', 'fin_jour', (auj + 3)::text));
  insert into ids values ('SUSP', v);
  insert into resultats (test, ok, detail) values ('Suspension enregistrée, effet immédiat', exists (select 1 from public.sanctions where membre_id = a and type = 'suspension' and statut = 'active' and debut <= clock_timestamp() and clock_timestamp() < fin), '');
  insert into resultats (test, ok, detail) values ('Fin de la suspension : lendemain du dernier jour, 0 h à Madagascar',
    (select fin from public.sanctions where id = v) = ((auj + 4)::timestamp at time zone 'Indian/Antananarivo'), (select fin::text from public.sanctions where id = v));
  select count(*) into n from public.notifications where membre_id = a and texte like 'Décision de Katana : Suspension%';
  insert into resultats (test, ok, detail) values ('Le joueur est averti (motif, fin, délai de contestation)', n = 1, n || ' notification(s)');
  begin perform public.sanctionner(jsonb_build_object('membre_id', a, 'type', 'suspension', 'motif', 'Encore', 'fin_jour', (auj + 2)::text));
    insert into resultats (test, ok, detail) values ('Pas deux suspensions en même temps', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Pas deux suspensions en même temps', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000009a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000009a1', true);
set local role authenticated;
do $$
declare r text; n int;
begin
  begin perform public.demander_compte2('Autre', '9990009', 'test', 'x/y.jpg', false);
    insert into resultats (test, ok, detail) values ('Suspendu : aucune demande', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Suspendu : aucune demande', true, sqlerrm); end;
  r := public.demander_retrait('Je pars');
  select count(*) into n from public.membres where id = (select id from ids where nom = 'A') and statut = 'actif';
  insert into resultats (test, ok, detail) values ('Suspendu : le retrait est soumis à Katana, pas automatique', r = 'en_attente' and n = 1, r);
  select count(*) into n from public.sanctions;
  insert into resultats (test, ok, detail) values ('Le joueur voit sa sanction', n = 1, n || ' sanction(s)');
  perform public.contester_sanction((select id from ids where nom = 'SUSP'), 'Je n''étais pas là');
  begin perform public.contester_sanction((select id from ids where nom = 'SUSP'), 'Encore');
    insert into resultats (test, ok, detail) values ('Une seule contestation', false, 'acceptée');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Une seule contestation', true, sqlerrm); end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000009b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000009b1', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.sanctions;
  insert into resultats (test, ok, detail) values ('Un autre membre ne voit pas la sanction', n = 0, n || ' sanction(s)');
  begin perform public.contester_sanction((select id from ids where nom = 'SUSP'), 'x');
    insert into resultats (test, ok, detail) values ('Un autre membre ne conteste pas', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Un autre membre ne conteste pas', true, sqlerrm); end;
end $$;
reset role;
set local role anon;
do $$
declare n int;
begin
  begin select count(*) into n from public.sanctions;
    insert into resultats (test, ok, detail) values ('Visiteur : aucune sanction visible', false, n || ' ligne(s)');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : aucune sanction visible', true, 'refusé'); end;
end $$;
reset role;

-- ---------- 3. Recours : maintenir puis lever ; exclusion et levée ; retrait de statistiques ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad09"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad09', true);
set local role authenticated;
do $$
declare a bigint := (select id from ids where nom = 'A'); b bigint := (select id from ids where nom = 'B'); s bigint := (select id from ids where nom = 'SUSP');
        v bigint; n int; st text;
begin
  perform public.decider_sanction(s, 'maintenir', 'Témoignages concordants');
  select decision_recours into st from public.sanctions where id = s;
  insert into resultats (test, ok, detail) values ('Contestation tranchée : maintenue', st = 'maintenue', st);
  perform public.decider_sanction(s, 'lever', 'Nouvel élément');
  insert into resultats (test, ok, detail) values ('Levée : plus suspendu (matchs recomptés)', not exists (select 1 from public.sanctions where membre_id = a and type = 'suspension' and statut = 'active' and debut <= clock_timestamp() and clock_timestamp() < fin), '');

  v := public.sanctionner(jsonb_build_object('membre_id', b, 'type', 'exclusion', 'motif', 'Farming'));
  select count(*) into n from public.membres where id = b and statut = 'exclu';
  insert into resultats (test, ok, detail) values ('Exclusion : statut exclu, période fermée, comptes inactifs',
    n = 1 and not exists (select 1 from public.periodes where membre_id = b and fin is null)
    and not exists (select 1 from public.comptes_jeu where membre_id = b and statut = 'actif'), '');
  perform public.decider_sanction(v, 'lever', 'Erreur');
  insert into resultats (test, ok, detail) values ('Exclusion levée : membre actif, période et compte rouverts',
    exists (select 1 from public.membres where id = b and statut = 'actif')
    and exists (select 1 from public.periodes where membre_id = b and fin is null)
    and exists (select 1 from public.comptes_jeu where membre_id = b and statut = 'actif'), '');

  v := public.sanctionner(jsonb_build_object('membre_id', a, 'type', 'retrait_statistiques', 'motif', 'Compte prêté', 'match_id', (select id from ids where nom = 'M')));
  select count(*) into n from public.registre where match_id = (select id from ids where nom = 'M') and type = 'sanction';
  insert into resultats (test, ok, detail) values ('Retrait des statistiques d''un match : noté au registre du match', n = 1, n || ' événement(s)');
  begin perform public.sanctionner(jsonb_build_object('membre_id', b, 'type', 'retrait_statistiques', 'motif', 'x', 'match_id', (select id from ids where nom = 'M')));
    insert into resultats (test, ok, detail) values ('Retrait refusé pour un joueur absent du match', false, 'accepté');
  exception when raise_exception then insert into resultats (test, ok, detail) values ('Retrait refusé pour un joueur absent du match', true, sqlerrm); end;
  perform public.sanctionner(jsonb_build_object('membre_id', a, 'type', 'avertissement', 'motif', 'Divulgation, première fois'));
  select count(*) into n from public.journal where type = 'Sanction';
  insert into resultats (test, ok, detail) values ('Chaque décision est notée au journal', n >= 6, n || ' ligne(s)');
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
