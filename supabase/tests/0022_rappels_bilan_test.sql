-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0022 (bilan des envois de rappels)
-- À exécuter APRÈS la migration 0022. Faux téléphones seulement (adresses push.test.invalid, faux compte
-- 00000000-…-0022). Aucune notification n'est envoyée. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

-- ---------- 1. Plus aucune modification sans condition WHERE (refusée par Supabase pour les appels de l'API) ----------
do $$
declare n int; v text;
begin
  select count(*), string_agg(p.proname, ', ') into n, v
    from pg_proc p, regexp_matches(p.prosrc, '(update\s+[a-z_.]+\s+(?:[a-z]+\s+)?set\s[^;]*;)', 'gi') m
   where p.pronamespace = 'public'::regnamespace and m[1] !~* '\swhere\s';
  insert into resultats (test, ok, detail) values ('Aucune fonction ne modifie sans condition WHERE', n = 0, coalesce(v, 'aucune'));
end $$;

-- ---------- 2. Bilan des envois noté par le rôle serveur ----------
insert into auth.users (id, email) values ('00000000-0000-4000-8000-000000000022', 'faux.admin22@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-000000000022') on conflict do nothing;
do $$
declare x bigint;
begin
  insert into public.abonnements_push (user_id, endpoint, p256dh, auth)
  values ('00000000-0000-4000-8000-000000000022', 'https://push.test.invalid/ok', repeat('A', 87), repeat('a', 22)) returning id into x;
  insert into ids values ('ok', x);
  insert into public.abonnements_push (user_id, endpoint, p256dh, auth)
  values ('00000000-0000-4000-8000-000000000022', 'https://push.test.invalid/parti', repeat('B', 87), repeat('b', 22)) returning id into x;
  insert into ids values ('parti', x);
  insert into public.rappels_envoyes (cle) values ('essai:test0022');
end $$;

-- Pour imiter Supabase : la base locale n'a pas l'extension qui refuse les modifications sans WHERE ;
-- elle est essayée si elle existe (vrai projet), sans erreur sinon.
do $$ begin execute 'load ''safeupdate'''; exception when others then null; end $$;
set local role service_role;
do $$
declare ok boolean := true; msg text := '';
begin
  begin
    perform public.rappels_resultats(jsonb_build_object(
      'envois', jsonb_build_array(jsonb_build_object('id', (select id from ids where nom = 'ok'), 'http', 201),
                                  jsonb_build_object('id', (select id from ids where nom = 'parti'), 'http', 410)),
      'cles', jsonb_build_object('essai:test0022', 1)));
  exception when others then ok := false; msg := sqlerrm;
  end;
  insert into resultats (test, ok, detail) values ('Rôle serveur : rappels_resultats s''exécute sans erreur', ok, msg);
end $$;
reset role;

do $$
begin
  insert into resultats (test, ok, detail) values ('Envoi réussi noté sur le téléphone',
    exists (select 1 from public.abonnements_push where endpoint = 'https://push.test.invalid/ok' and dernier_envoi is not null and echecs = 0), '');
  insert into resultats (test, ok, detail) values ('Téléphone désinscrit (410) oublié',
    not exists (select 1 from public.abonnements_push where endpoint = 'https://push.test.invalid/parti'), '');
  insert into resultats (test, ok, detail) values ('Nombre de téléphones atteints noté sur le rappel',
    (select destinataires from public.rappels_envoyes where cle = 'essai:test0022') = 1, '');
  insert into resultats (test, ok, detail) values ('Bilan du dernier envoi noté (1 reçu, 0 échec, 1 oublié)',
    (select dernier_bilan->>'envoyes' = '1' and dernier_bilan->>'echecs' = '0' and dernier_bilan->>'oublies' = '1' from prive.rappels_config),
    (select coalesce(dernier_bilan::text, 'vide') from prive.rappels_config));
  insert into resultats (test, ok, detail) values ('rappels_resultats toujours refusé aux personnes connectées',
    not has_function_privilege('authenticated', 'public.rappels_resultats(jsonb)', 'EXECUTE')
    and has_function_privilege('service_role', 'public.rappels_resultats(jsonb)', 'EXECUTE'), '');
  insert into resultats (test, ok, detail) values ('rappels_reveil refusé au rôle serveur et aux personnes connectées',
    not has_function_privilege('authenticated', 'public.rappels_reveil()', 'EXECUTE')
    and not has_function_privilege('service_role', 'public.rappels_reveil()', 'EXECUTE'), '');
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
