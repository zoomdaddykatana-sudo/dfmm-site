-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0019 (délai de traitement des inscriptions)
-- À exécuter APRÈS la migration 0019. Aucune donnée personnelle. Tout est annulé à la fin.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;

-- ---------- 1. Réglage en place ----------
do $$
declare v text; s text; t text;
begin
  select valeur::text, section, type into v, s, t from public.parametres where cle = 'delai_traitement_h';
  insert into resultats (test, ok, detail) values ('Réglage « delai_traitement_h » à 48, entier, section Site',
    v = '48' and s = 'Site' and t = 'entier', coalesce(v || ' / ' || t || ' / ' || s, 'absent'));
end $$;

-- ---------- 2. Un visiteur le lit (le site l'affiche avant toute connexion) ----------
set local role anon;
do $$
declare n int;
begin
  select count(*) into n from public.parametres where cle = 'delai_traitement_h';
  insert into resultats (test, ok, detail) values ('Visiteur : lit le délai', n = 1, n || ' ligne(s)');
end $$;
reset role;

-- ---------- 3. Un visiteur ne le modifie pas ----------
set local role anon;
do $$
declare n int;
begin
  begin
    update public.parametres set valeur = '1' where cle = 'delai_traitement_h';
    get diagnostics n = row_count;
    insert into resultats (test, ok, detail) values ('Visiteur : ne modifie pas le délai', n = 0, n || ' ligne(s) modifiée(s)');
  exception when insufficient_privilege then
    insert into resultats (test, ok, detail) values ('Visiteur : ne modifie pas le délai', true, 'refusé');
  end;
end $$;
reset role;

-- ---------- 4. Valeur invalide refusée (contrôle existant des réglages) ----------
do $$ begin
  begin
    update public.parametres set valeur = '"deux jours"' where cle = 'delai_traitement_h';
    insert into resultats (test, ok, detail) values ('Texte refusé pour un délai en heures', false, 'accepté');
  exception when raise_exception then
    insert into resultats (test, ok, detail) values ('Texte refusé pour un délai en heures', true, sqlerrm);
  end;
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
