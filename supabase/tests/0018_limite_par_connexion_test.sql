-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0018 (limite d'inscriptions par connexion)
-- À exécuter APRÈS la migration 0018. Aucun membre, aucune donnée personnelle : seulement de fausses
-- empreintes (« test-ip-… »). Aucun appel à volsever. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;

-- ---------- 1. Réglage en place ----------
do $$
declare v text; s text;
begin
  select valeur::text, section into v, s from public.parametres where cle = 'inscriptions_max_heure_ip';
  insert into resultats (test, ok, detail) values ('Réglage « inscriptions_max_heure_ip » à 3, section Limites',
    v = '3' and s = 'Limites', coalesce(v || ' / ' || s, 'absent'));
end $$;

-- ---------- 2. Accès : ni un membre ni un visiteur n'appellent la fonction ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000018a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000018a1', true);
set local role authenticated;
do $$ begin
  begin perform public.reserver_essai_inscription('test-ip-membre');
    insert into resultats (test, ok, detail) values ('Personne connectée : ne réserve pas de place', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Personne connectée : ne réserve pas de place', true, 'refusé'); end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.reserver_essai_inscription('test-ip-visiteur');
    insert into resultats (test, ok, detail) values ('Visiteur : ne réserve pas de place', false, 'permis');
  exception when insufficient_privilege then insert into resultats (test, ok, detail) values ('Visiteur : ne réserve pas de place', true, 'refusé'); end;
end $$;
reset role;

-- ---------- 3. Limite par connexion (rôle serveur), limite commune large ----------
-- Les envois réels de la dernière heure sont repoussés de 2 h pour ce test (annulé à la fin).
update public.inscription_essais set cree_le = clock_timestamp() - interval '2 hours' where cree_le > clock_timestamp() - interval '1 hour';
update public.parametres set valeur = '30' where cle = 'inscriptions_max_heure';
set local role service_role;
do $$
declare r text := '';
begin
  for i in 1..4 loop r := r || public.reserver_essai_inscription('test-ip-A') || ' '; end loop;
  insert into resultats (test, ok, detail) values ('Même connexion : 3 places puis refus', r = 'ok ok ok limite_ip ', r);
  r := public.reserver_essai_inscription('test-ip-B');
  insert into resultats (test, ok, detail) values ('Autre connexion : place accordée', r = 'ok', r);
  r := public.reserver_essai_inscription(null) || ' ' || public.reserver_essai_inscription('  ');
  insert into resultats (test, ok, detail) values ('Adresse inconnue : seule la limite commune compte', r = 'ok ok', r);
end $$;
reset role;

-- ---------- 4. Les envois de plus d'une heure ne comptent plus ----------
update public.inscription_essais set cree_le = clock_timestamp() - interval '2 hours' where empreinte_ip = 'test-ip-A';
set local role service_role;
do $$ declare r text := public.reserver_essai_inscription('test-ip-A');
begin
  insert into resultats (test, ok, detail) values ('Même connexion une heure plus tard : place accordée', r = 'ok', r);
end $$;
reset role;

-- ---------- 5. Limite commune toujours prioritaire ----------
update public.parametres set valeur = to_jsonb((select count(*) from public.inscription_essais
  where cree_le > clock_timestamp() - interval '1 hour')::int) where cle = 'inscriptions_max_heure';
set local role service_role;
do $$ declare r text := public.reserver_essai_inscription('test-ip-C');
begin
  insert into resultats (test, ok, detail) values ('Limite commune atteinte : refus même pour une nouvelle connexion', r = 'limite', r);
end $$;
reset role;

-- ---------- 6. L'ancienne fonction (sans argument) marche toujours ----------
update public.parametres set valeur = '1000' where cle = 'inscriptions_max_heure';
set local role service_role;
do $$ begin
  insert into resultats (test, ok, detail) values ('Ancienne fonction « inscription » : toujours compatible',
    public.reserver_essai_inscription() is true, 'place');
end $$;
reset role;

-- ---------- 7. Empreintes effacées au bout de 24 h ----------
insert into public.inscription_essais (cree_le, empreinte_ip) values (clock_timestamp() - interval '25 hours', 'test-ip-vieux');
set local role service_role;
do $$ begin perform public.reserver_essai_inscription('test-ip-D'); end $$;
reset role;
do $$ declare n int;
begin
  select count(*) into n from public.inscription_essais where empreinte_ip is not null and cree_le < clock_timestamp() - interval '24 hours';
  insert into resultats (test, ok, detail) values ('Aucune empreinte de plus de 24 h gardée', n = 0, n || ' empreinte(s)');
end $$;

-- ---------- Résultat (tout est annulé) ----------
do $$
declare total int; echecs int; liste text;
begin
  select count(*), count(*) filter (where not ok) into total, echecs from resultats;
  select string_agg(n || '. ' || test || ' (' || detail || ')', ' | ' order by n) into liste from resultats where not ok;
  raise exception 'FIN DU TEST : % réussi(s) sur %. % Rien n''a été gardé dans la base (ce message apparaît comme une erreur exprès, pour tout annuler).',
    total - echecs, total, case when echecs = 0 then 'Tout est bon.' else 'ÉCHECS : ' || liste || '.' end;
end $$;
