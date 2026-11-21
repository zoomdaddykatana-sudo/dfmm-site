-- =====================================================================
-- LEAGUE UV — DFMM · Test des règles d'accès du lot « socle »
-- À exécuter dans Supabase : SQL Editor > New query > coller > Run.
-- Crée un faux administrateur et deux faux membres, vérifie les accès,
-- puis ANNULE TOUT : le test finit volontairement par un message
-- d'erreur qui résume le résultat. Rien n'est gardé dans la base.
-- =====================================================================
begin;

create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated;
grant all on sequence resultats_n_seq to anon, authenticated;

-- ---------- Données fictives ----------
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000ad01', 'faux.admin@test.invalid'),
  ('00000000-0000-4000-8000-00000000a001', 'faux.membre.a@test.invalid'),
  ('00000000-0000-4000-8000-00000000b001', 'faux.membre.b@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000ad01');
insert into public.membres (user_id, matricule, nom_gamer, statut) values
  ('00000000-0000-4000-8000-00000000a001', 99001, 'Faux A', 'actif'),
  ('00000000-0000-4000-8000-00000000b001', 99002, 'Faux B', 'actif');
insert into public.periodes (membre_id, debut)
  select id, now() - interval '1 day' from public.membres where matricule in (99001, 99002);
insert into public.comptes_jeu (membre_id, uid, pseudo, statut)
  select id, '9900' || matricule, 'Pseudo' || matricule, 'actif' from public.membres where matricule in (99001, 99002);
insert into public.pseudos_historique (compte_id, pseudo)
  select id, pseudo from public.comptes_jeu where uid in ('990099001', '990099002');
insert into public.journal (type, decision) values ('Test', 'Entrée fictive');

-- ---------- 1. Visiteur non connecté ----------
select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
declare n int;
begin
  select count(*) into n from public.parametres;
  insert into resultats (test, ok, detail) values ('Visiteur : lit les paramètres', n >= 25, n || ' paramètres');
  select public.est_admin()::int into n;
  insert into resultats (test, ok, detail) values ('Visiteur : n''est pas administrateur', n = 0, '');
  begin
    perform 1 from public.membres;
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas les membres', false, 'lecture permise');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas les membres', true, 'refusé');
  end;
  begin
    perform 1 from public.journal;
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas le journal', false, 'lecture permise');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne lit pas le journal', true, 'refusé');
  end;
  begin
    update public.parametres set valeur = '5' where cle = 'participants_min';
    insert into resultats (test, ok, detail) values ('Visiteur : ne modifie pas un paramètre', false, 'modification permise');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne modifie pas un paramètre', true, 'refusé');
  end;
end $$;
reset role;

-- ---------- 2. Faux membre A ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000a001"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000a001', true);
set local role authenticated;
do $$
declare n int; m int;
begin
  select count(*), max(matricule) into n, m from public.membres;
  insert into resultats (test, ok, detail) values ('Membre A : voit seulement sa fiche', n = 1 and m = 99001, n || ' fiche(s)');
  select count(*) into n from public.periodes;
  insert into resultats (test, ok, detail) values ('Membre A : voit seulement ses périodes', n = 1, n || ' ligne(s)');
  select count(*) into n from public.comptes_jeu;
  insert into resultats (test, ok, detail) values ('Membre A : voit seulement ses comptes', n = 1, n || ' ligne(s)');
  select count(*) into n from public.pseudos_historique;
  insert into resultats (test, ok, detail) values ('Membre A : voit seulement ses pseudos', n = 1, n || ' ligne(s)');
  select count(*) into n from public.journal;
  insert into resultats (test, ok, detail) values ('Membre A : ne lit pas le journal', n = 0, n || ' ligne(s)');
  select count(*) into n from public.parametres_historique;
  insert into resultats (test, ok, detail) values ('Membre A : ne lit pas l''historique des paramètres', n = 0, n || ' ligne(s)');
  select count(*) into n from public.admins;
  insert into resultats (test, ok, detail) values ('Membre A : ne voit pas la liste des administrateurs', n = 0, n || ' ligne(s)');
  select public.est_admin()::int into n;
  insert into resultats (test, ok, detail) values ('Membre A : n''est pas administrateur', n = 0, '');
  update public.parametres set valeur = '5' where cle = 'participants_min';
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Membre A : ne modifie pas un paramètre', n = 0, n || ' ligne(s) modifiée(s)');
  update public.membres set statut = 'exclu' where matricule = 99002;
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Membre A : ne modifie pas la fiche d''un autre', n = 0, n || ' ligne(s)');
  update public.membres set statut = 'exclu' where matricule = 99001;
  get diagnostics n = row_count;
  insert into resultats (test, ok, detail) values ('Membre A : ne change pas son propre statut', n = 0, n || ' ligne(s)');
  begin
    insert into public.admins (user_id) values ('00000000-0000-4000-8000-00000000a001');
    insert into resultats (test, ok, detail) values ('Membre A : ne peut pas se déclarer administrateur', false, 'ajout permis');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Membre A : ne peut pas se déclarer administrateur', true, 'refusé');
  end;
  begin
    insert into public.membres (nom_gamer, statut, matricule) values ('Intrus', 'actif', 99003);
    insert into resultats (test, ok, detail) values ('Membre A : ne crée pas de fiche membre', false, 'ajout permis');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Membre A : ne crée pas de fiche membre', true, 'refusé');
  end;
end $$;
reset role;

-- ---------- 3. Faux administrateur ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000ad01"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000ad01', true);
set local role authenticated;
do $$
declare n int; v jsonb;
begin
  select public.est_admin()::int into n;
  insert into resultats (test, ok, detail) values ('Admin : est reconnu administrateur', n = 1, '');
  select count(*) into n from public.membres where matricule in (99001, 99002);
  insert into resultats (test, ok, detail) values ('Admin : voit toutes les fiches', n = 2, n || ' fiche(s)');
  select count(*) into n from public.journal;
  insert into resultats (test, ok, detail) values ('Admin : lit le journal', n >= 1, n || ' ligne(s)');
  update public.parametres set valeur = '17' where cle = 'participants_min';
  get diagnostics n = row_count;
  select valeur into v from public.parametres where cle = 'participants_min';
  insert into resultats (test, ok, detail) values ('Admin : modifie un paramètre', n = 1 and v = '17'::jsonb, 'valeur ' || v::text);
  select count(*) into n from public.parametres_historique
    where cle = 'participants_min' and modifie_par = '00000000-0000-4000-8000-00000000ad01';
  insert into resultats (test, ok, detail) values ('Admin : le changement est gardé dans l''historique', n = 1, n || ' ligne(s)');
  begin
    update public.parametres set valeur = '"abc"' where cle = 'participants_min';
    insert into resultats (test, ok, detail) values ('Admin : valeur invalide refusée', false, 'acceptée');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Admin : valeur invalide refusée', true, 'refusée');
  end;
  begin
    update public.parametres set valeur = '"25:00"' where cle = 'coupure_heure';
    insert into resultats (test, ok, detail) values ('Admin : heure invalide refusée', false, 'acceptée');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Admin : heure invalide refusée', true, 'refusée');
  end;
end $$;
reset role;

-- ---------- Résultat (puis tout est annulé) ----------
do $$
declare total int; echecs int; liste text;
begin
  select count(*), count(*) filter (where not ok) into total, echecs from resultats;
  select string_agg(n || '. ' || test || ' (' || detail || ')', ' | ' order by n) into liste from resultats where not ok;
  raise exception 'FIN DU TEST : % réussi(s) sur %. % Rien n''a été gardé dans la base (ce message apparaît comme une erreur exprès, pour tout annuler).',
    total - echecs, total,
    case when echecs = 0 then 'Tout est bon.' else 'ÉCHECS : ' || liste || '.' end;
end $$;
