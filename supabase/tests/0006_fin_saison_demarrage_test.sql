-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0006 (fin de saison, phase de démarrage)
-- À exécuter APRÈS la migration 0006. Un faux administrateur seulement ; tout est annulé à la fin.
-- Le résultat s'affiche dans un message rouge voulu (« FIN DU TEST … »).
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;

insert into auth.users (id, email) values ('00000000-0000-4000-8000-00000000ad06', 'faux.admin6@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad06');

-- ---------- 1. Contenu des paramètres ----------
do $$
declare n int; v jsonb;
begin
  select count(*) into n from public.parametres where cle = 'classement_final_jours';
  insert into resultats (test, ok, detail) values ('Ancien réglage « 7 jours après la fin » retiré', n = 0, n || ' ligne(s)');
  select valeur into v from public.parametres where cle = 'verification_finale_h';
  insert into resultats (test, ok, detail) values ('Vérification finale : 48 h', v = '48'::jsonb, coalesce(v::text, 'absent'));
  select valeur into v from public.parametres where cle = 'phase_demarrage';
  insert into resultats (test, ok, detail) values ('Phase de démarrage : oui au départ', v = 'true'::jsonb, coalesce(v::text, 'absent'));
end $$;

-- ---------- 2. Lecture publique (le site lit les réglages sans connexion) ----------
set local role anon;
do $$
declare n int;
begin
  select count(*) into n from public.parametres where cle in ('verification_finale_h', 'phase_demarrage');
  insert into resultats (test, ok, detail) values ('Visiteur : lit les 2 nouveaux réglages', n = 2, n || ' réglage(s)');
  begin
    update public.parametres set valeur = 'false' where cle = 'phase_demarrage';
    get diagnostics n = row_count;
    insert into resultats (test, ok, detail) values ('Visiteur : ne change pas la phase de démarrage', n = 0, n || ' ligne(s) changée(s)');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne change pas la phase de démarrage', true, 'refusé');
  end;
end $$;
reset role;

-- ---------- 3. Administrateur : change les valeurs, contrôle du type ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad06"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad06', true);
set local role authenticated;
do $$
declare n int;
begin
  update public.parametres set valeur = 'false' where cle = 'phase_demarrage';
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Admin : passe la phase de démarrage à « non »', n = 1, n || ' ligne(s)');
  select count(*) into n from public.parametres_historique where cle = 'phase_demarrage';
  insert into resultats (test, ok, detail) values ('Le changement est gardé dans l''historique', n = 1, n || ' ligne(s)');
  begin
    update public.parametres set valeur = '"beaucoup"' where cle = 'verification_finale_h';
    insert into resultats (test, ok, detail) values ('Vérification finale : un nombre entier obligatoire', false, 'accepté');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Vérification finale : un nombre entier obligatoire', true, sqlerrm);
  end;
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
