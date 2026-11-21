-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0003 (droits du rôle serveur)
-- Lecture seule : rien n'est créé ni modifié. Le résultat s'affiche dans
-- un message rouge voulu (« FIN DU TEST … »).
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;

set local role service_role;
do $$
declare v jsonb; n int;
begin
  begin
    select valeur into v from public.parametres where cle = 'inscriptions_ouvertes';
    insert into resultats (test, ok, detail) values ('Serveur : lit le réglage « Inscriptions ouvertes »', v is not null, 'valeur ' || coalesce(v::text, 'vide'));
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Serveur : lit le réglage « Inscriptions ouvertes »', false, 'permission refusée');
  end;
  begin
    select count(*) into n from public.membres;
    insert into resultats (test, ok, detail) values ('Serveur : contrôle les doublons (membres)', true, n || ' fiche(s)');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Serveur : contrôle les doublons (membres)', false, 'permission refusée');
  end;
  begin
    select count(*) into n from public.comptes_jeu;
    insert into resultats (test, ok, detail) values ('Serveur : contrôle les doublons (UID)', true, n || ' compte(s)');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Serveur : contrôle les doublons (UID)', false, 'permission refusée');
  end;
  begin
    perform 1 from public.journal limit 1;
    insert into resultats (test, ok, detail) values ('Serveur : peut écrire le journal', has_table_privilege('service_role', 'public.journal', 'INSERT'), '');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Serveur : peut écrire le journal', false, 'permission refusée');
  end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
  begin
    perform 1 from public.membres;
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit toujours pas les membres', false, 'lecture permise');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit toujours pas les membres', true, 'refusé');
  end;
end $$;
reset role;

do $$
declare total int; echecs int; liste text;
begin
  select count(*), count(*) filter (where not ok) into total, echecs from resultats;
  select string_agg(n || '. ' || test || ' (' || detail || ')', ' | ' order by n) into liste from resultats where not ok;
  raise exception 'FIN DU TEST : % réussi(s) sur %. % Rien n''a été gardé dans la base (ce message apparaît comme une erreur exprès, pour tout annuler).',
    total - echecs, total, case when echecs = 0 then 'Tout est bon.' else 'ÉCHECS : ' || liste || '.' end;
end $$;
