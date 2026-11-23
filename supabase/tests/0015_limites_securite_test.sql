-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0015 (limites de sécurité, PR A)
-- À exécuter APRÈS la migration 0015. Faux membres seulement (anciens matricules fictifs 99151 et 99152,
-- adresses @test.invalid). Aucun appel réel à volsever. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000015ad', 'faux.admin15@test.invalid'),
  ('00000000-0000-4000-8000-0000000015a1', 'faux.15a@test.invalid'),
  ('00000000-0000-4000-8000-0000000015b1', 'faux.15b@test.invalid'),
  ('00000000-0000-4000-8000-0000000015c1', 'faux.15c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000015ad');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99151, 'Faux 15A', '2026-11-18'), (99152, 'Faux 15B', '2026-11-18');

set local role service_role;
do $$ begin
  insert into ids select 'A', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000015a1','nom_gamer','Faux 15A',
    'email','15a@test.invalid','facebook','facebook.com/faux15a','pseudo','PKL¬Faux15A','uid','9915001','empreinte_email','e15a','empreinte_facebook','f15a',
    'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
  insert into ids select 'B', public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000015b1','nom_gamer','Faux 15B',
    'email','15b@test.invalid','facebook','facebook.com/faux15b','pseudo','Faux15B','uid','9915002','empreinte_email','e15b','empreinte_facebook','f15b',
    'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000015ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000015ad', true);
set local role authenticated;
do $$ begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99151);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99152);
end $$;
reset role;
insert into ids select 'cA', id from public.comptes_jeu where uid = '9915001';
insert into ids select 'cB', id from public.comptes_jeu where uid = '9915002';
-- B est suspendu (sanction en cours) ; A reçoit un avertissement qu'il peut contester.
insert into public.sanctions (membre_id, type, motif, debut, fin, recours_jusqu)
values ((select id from ids where nom = 'B'), 'suspension', 'Faux motif de test', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '3 days', clock_timestamp() + interval '2 days');
with s as (insert into public.sanctions (membre_id, type, motif, debut, recours_jusqu)
  values ((select id from ids where nom = 'A'), 'avertissement', 'Faux motif de test', clock_timestamp(), clock_timestamp() + interval '2 days') returning id)
insert into ids select 'sA', id from s;

-- ---------- 1. Réglages et contrôles en place ----------
do $$
declare n int; v text;
begin
  select count(*), string_agg(cle || '=' || valeur::text, ', ' order by ordre) into n, v from public.parametres where section = 'Limites' and ordre <= 4;
  insert into resultats (test, ok, detail) values ('4 réglages dans la section Limites (10 par heure, 24 h, 100, 2000 ; un 5e à partir de la migration 0018)',
    n = 4 and v = 'inscriptions_max_heure=10, pseudo_delai_h=24, longueur_max_court=100, longueur_max_long=2000', coalesce(v, 'aucun'));
  select count(*) into n from pg_trigger where tgname = 'longueurs_textes' and not tgisinternal;
  insert into resultats (test, ok, detail) values ('Contrôle de longueur sur 7 tables au moins (8 après la migration 0016)', n >= 7, n || ' table(s)');
end $$;

-- ---------- 2. Accès : ni un membre ni un visiteur n'appellent les fonctions serveur ni ne lisent les compteurs ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000015a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000015a1', true);
set local role authenticated;
do $$
declare n int;
begin
  begin perform public.reserver_essai_inscription();
    insert into resultats (test, ok, detail) values ('Membre : ne réserve pas de place d''inscription', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : ne réserve pas de place d''inscription', true, 'refusé'); end;
  begin perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', (select id from ids where nom = 'cA'), 'X');
    insert into resultats (test, ok, detail) values ('Membre : ne contourne pas la fonction serveur du pseudo', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Membre : ne contourne pas la fonction serveur du pseudo', true, 'refusé'); end;
  select (select count(*) from public.inscription_essais) + (select count(*) from public.declarations_pseudo) into n;
  insert into resultats (test, ok, detail) values ('Membre : ne lit pas les compteurs', n = 0, n || ' ligne(s)');
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.reserver_essai_inscription();
    insert into resultats (test, ok, detail) values ('Visiteur : ne réserve pas de place d''inscription', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : ne réserve pas de place d''inscription', true, 'refusé'); end;
end $$;
reset role;

-- ---------- 3. Limite d'inscriptions par heure (rôle serveur) ----------
update public.parametres set valeur = '3' where cle = 'inscriptions_max_heure';
set local role service_role;
do $$
declare r text := '';
begin
  for i in 1..4 loop r := r || case when public.reserver_essai_inscription() then 'o' else 'n' end; end loop;
  insert into resultats (test, ok, detail) values ('Limite à 3 par heure : 3 places puis refus', r = 'ooon', r);
end $$;
reset role;
update public.inscription_essais set cree_le = clock_timestamp() - interval '2 hours' where cree_le > clock_timestamp() - interval '1 hour';
set local role service_role;
do $$ begin
  insert into resultats (test, ok, detail) values ('Les envois de plus d''une heure ne comptent plus', public.reserver_essai_inscription(), 'place');
end $$;
reset role;

-- ---------- 4. Déclarations de pseudo (rôle serveur, résultats de volsever simulés) ----------
set local role service_role;
do $$
declare cA bigint := (select id from ids where nom = 'cA'); cB bigint := (select id from ids where nom = 'cB'); m text; v text;
begin
  perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, 'PKL¬Nouveau');
  v := public.enregistrer_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, 'PKL¬Nouveau', 'trouve', 'PKL¬Nouveau');
  insert into resultats (test, ok, detail) values ('1re déclaration de A acceptée et notée', v = 'modifie'
    and (select count(*) from public.declarations_pseudo where compte_id = cA) = 1, v);
  begin perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, 'PKL¬Encore');
    insert into resultats (test, ok, detail) values ('2e déclaration dans les 24 h refusée (avant volsever)', false, 'permise');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('2e déclaration dans les 24 h refusée (avant volsever)', m like 'Une seule déclaration de pseudo par compte toutes les 24 h.%', m); end;
  begin perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015b1', cB, 'Faux15B');
    insert into resultats (test, ok, detail) values ('Membre suspendu : déclaration refusée', false, 'permise');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Membre suspendu : déclaration refusée', m like '%pendant une suspension%', m); end;
  begin perform public.enregistrer_declaration_pseudo('00000000-0000-4000-8000-0000000015b1', cB, 'Faux15B', 'trouve', 'Faux15B');
    insert into resultats (test, ok, detail) values ('Membre suspendu : enregistrement refusé aussi', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Membre suspendu : enregistrement refusé aussi', m like '%pendant une suspension%', m); end;
  begin perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cB, 'Vol');
    insert into resultats (test, ok, detail) values ('Compte d''un autre membre refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Compte d''un autre membre refusé', m = 'Choisissez l''un de vos comptes.', m); end;
end $$;
reset role;
update public.declarations_pseudo set cree_le = clock_timestamp() - interval '25 hours' where compte_id = (select id from ids where nom = 'cA');
set local role service_role;
do $$
declare cA bigint := (select id from ids where nom = 'cA'); m text; v text;
begin
  begin perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, repeat('x', 101));
    insert into resultats (test, ok, detail) values ('Pseudo de 101 caractères refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Pseudo de 101 caractères refusé', m = 'Texte trop long (pseudo) : 100 caractères au plus.', m); end;
  perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, 'PKL¬Autre');
  v := public.enregistrer_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, 'PKL¬Autre', 'quota', null);
  insert into resultats (test, ok, detail) values ('Après 24 h : nouvelle déclaration acceptée (en attente)', v = 'attente', v);
  begin perform public.reserver_declaration_pseudo('00000000-0000-4000-8000-0000000015a1', cA, 'PKL¬Troisieme');
    insert into resultats (test, ok, detail) values ('Déclaration en attente : nouvelle déclaration refusée', false, 'permise');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Déclaration en attente : nouvelle déclaration refusée', m like '%déjà en attente%', m); end;
end $$;
reset role;

-- ---------- 5. Longueurs maximales des textes tapés ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000015a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000015a1', true);
set local role authenticated;
do $$
declare m text; n int;
begin
  perform public.ecrire_a_katana(repeat('a', 2000));
  select count(*) into n from public.messages where texte = repeat('a', 2000);
  insert into resultats (test, ok, detail) values ('Message de 2000 caractères accepté', n = 1, n || ' message(s)');
  begin perform public.ecrire_a_katana(repeat('a', 2001));
    insert into resultats (test, ok, detail) values ('Message de 2001 caractères refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Message de 2001 caractères refusé', m = 'Texte trop long (message) : 2000 caractères au plus.', m); end;
  begin perform public.contester_sanction((select id from ids where nom = 'sA'), repeat('c', 2001));
    insert into resultats (test, ok, detail) values ('Contestation de 2001 caractères refusée', false, 'permise');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Contestation de 2001 caractères refusée', m like 'Texte trop long (contestation)%', m); end;
  begin perform public.demander_compte2('Faux15A2', '9915009', repeat('m', 2001), '00000000-0000-4000-8000-0000000015a1/profil2.jpg');
    insert into resultats (test, ok, detail) values ('Motif de demande de 2001 caractères refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Motif de demande de 2001 caractères refusé', m = 'Texte trop long (motif) : 2000 caractères au plus.', m); end;
  begin perform public.demander_compte2(repeat('p', 101), '9915009', 'Deuxième compte', '00000000-0000-4000-8000-0000000015a1/profil2.jpg');
    insert into resultats (test, ok, detail) values ('Pseudo de 2e compte de 101 caractères refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Pseudo de 2e compte de 101 caractères refusé', m = 'Texte trop long (pseudo) : 100 caractères au plus.', m); end;
end $$;
reset role;
set local role service_role;
do $$
declare m text;
begin
  begin perform public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000015c1','nom_gamer',repeat('n', 101),
    'email','15c@test.invalid','facebook','facebook.com/faux15c','pseudo','Faux15C','uid','9915003','empreinte_email','e15c','empreinte_facebook','f15c',
    'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
    insert into resultats (test, ok, detail) values ('Inscription : nom de gamer de 101 caractères refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Inscription : nom de gamer de 101 caractères refusé', m like 'Texte trop long (nom de gamer)%', m); end;
  begin perform public.creer_inscription(jsonb_build_object('user_id','00000000-0000-4000-8000-0000000015c1','nom_gamer','Faux 15C','nom_reel',repeat('r', 101),
    'email','15c@test.invalid','facebook','facebook.com/faux15c','pseudo','Faux15C','uid','9915003','empreinte_email','e15c','empreinte_facebook','f15c',
    'residence','Madagascar','comprend_mg',true,'parle_mg',true,'origine_mg',true));
    insert into resultats (test, ok, detail) values ('Inscription : nom réel de 101 caractères refusé (rien de créé)', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Inscription : nom réel de 101 caractères refusé (rien de créé)',
      m like 'Texte trop long (nom réel)%' and not exists (select 1 from public.membres where empreinte_email = 'e15c'), m); end;
end $$;
reset role;
-- Le réglage s'applique tout de suite.
update public.parametres set valeur = '50' where cle = 'longueur_max_long';
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000015a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000015a1', true);
set local role authenticated;
do $$
declare m text;
begin
  begin perform public.ecrire_a_katana(repeat('a', 51));
    insert into resultats (test, ok, detail) values ('Réglage à 50 : message de 51 caractères refusé', false, 'permis');
  exception when others then m := sqlerrm;
    insert into resultats (test, ok, detail) values ('Réglage à 50 : message de 51 caractères refusé', m = 'Texte trop long (message) : 50 caractères au plus.', m); end;
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
