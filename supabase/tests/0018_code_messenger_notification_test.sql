-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0018 (code Messenger dans les notifications)
-- À exécuter APRÈS la migration 0018. Faux candidats seulement (adresses @test.invalid, UID 99180xx,
-- ancien matricule fictif 99181). Aucun nouveau matricule n'est attribué (le compteur ne bouge pas).
-- Tout est annulé à la fin (message rouge voulu).
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000018ad', 'faux.admin18@test.invalid'),
  ('00000000-0000-4000-8000-0000000018a1', 'faux.18a@test.invalid'),
  ('00000000-0000-4000-8000-0000000018b1', 'faux.18b@test.invalid'),
  ('00000000-0000-4000-8000-0000000018c1', 'faux.18c@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000018ad');
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values (99181, 'Ancien 181', '2026-11-18');

-- ---------- 1. Trois fausses candidatures (rôle serveur) : A et B avec un code, C sans code ----------
set local role service_role;
do $$
declare k text; u text;
begin
  foreach k in array array['a', 'b', 'c'] loop
    u := '00000000-0000-4000-8000-0000000018' || k || '1';
    insert into ids select upper(k), public.creer_inscription(jsonb_build_object('user_id', u, 'nom_gamer', 'Faux 18' || upper(k),
      'email', '18' || k || '@test.invalid', 'facebook', 'facebook.com/faux18' || k, 'pseudo', 'Pseudo18' || upper(k),
      'uid', '991800' || (ascii(k) - 96), 'empreinte_email', 'e18' || k, 'empreinte_facebook', 'f18' || k,
      'residence', 'Madagascar', 'comprend_mg', true, 'parle_mg', true, 'origine_mg', true,
      'code_messenger', case when k = 'c' then null else 'UV-' || upper(k) || 'B1234' end));
  end loop;
end $$;
reset role;

do $$
declare n int; t text; s text;
begin
  select count(*), max(texte), max(sujet) into n, t, s from public.notifications where membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Inscription avec code : 1 notification du code, non lue',
    n = 1 and s = 'code_messenger' and t like '%UV-AB1234%' and t like '%page Facebook DFMM%'
    and exists (select 1 from public.notifications where membre_id = (select id from ids where nom = 'A') and not lu), n || ' · ' || coalesce(t, '—'));
  select count(*) into n from public.notifications where membre_id = (select id from ids where nom = 'C');
  insert into resultats (test, ok, detail) values ('Inscription sans code : aucune notification', n = 0, n || ' notification(s)');
end $$;

-- ---------- 2. Le joueur voit sa notification et signale l'envoi du code ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000018a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000018a1', true);
set local role authenticated;
do $$
declare n int; le1 timestamptz; le2 timestamptz;
begin
  select count(*) into n from public.notifications where sujet = 'code_messenger';
  insert into resultats (test, ok, detail) values ('Le joueur voit seulement sa notification du code', n = 1, n || ' visible(s)');
  le1 := public.signaler_code_envoye();
  select code_signale_le into le2 from public.membres_prives where membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('« J''ai envoyé le code » : date notée, lisible par le joueur', le1 is not null and le1 = le2, coalesce(le2::text, '—'));
  le2 := public.signaler_code_envoye();
  insert into resultats (test, ok, detail) values ('Signalé une 2e fois : la 1re date est gardée', le2 = le1, le2::text);
end $$;
do $$
begin
  update public.membres_prives set code_signale_le = null where membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Le joueur ne peut pas changer la date lui-même',
    (select code_signale_le from public.membres_prives where membre_id = (select id from ids where nom = 'A')) is not null, 'ligne gardée');
end $$;
reset role;

-- C (sans code) : refus clair.
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000018c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000018c1', true);
set local role authenticated;
do $$
begin
  perform public.signaler_code_envoye();
  insert into resultats (test, ok, detail) values ('Sans code : signalement refusé', false, 'accepté');
exception when raise_exception then
  insert into resultats (test, ok, detail) values ('Sans code : signalement refusé', true, sqlerrm);
end $$;
reset role;

-- Visiteur non connecté : refusé.
select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
  perform public.signaler_code_envoye();
  insert into resultats (test, ok, detail) values ('Visiteur : signalement refusé', false, 'accepté');
exception when insufficient_privilege or raise_exception then
  insert into resultats (test, ok, detail) values ('Visiteur : signalement refusé', true, sqlerrm);
end $$;
reset role;

-- ---------- 3. Katana voit la date ; approbation de A (ancien matricule) et refus de B ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000018ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000018ad', true);
set local role authenticated;
do $$
declare le timestamptz;
begin
  select code_signale_le into le from public.membres_prives where membre_id = (select id from ids where nom = 'A');
  insert into resultats (test, ok, detail) values ('Katana voit la date du signalement', le is not null, coalesce(le::text, '—'));
  perform public.decider_inscription((select id from ids where nom = 'A'), 'precisions', 'Faux motif de test');
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99181);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'refuser', 'Faux refus de test');
end $$;
reset role;
do $$
declare n_code int; n_non_lu int; t text;
begin
  select count(*) filter (where sujet = 'code_messenger'), count(*) filter (where sujet = 'code_messenger' and not lu)
  into n_code, n_non_lu from public.notifications where membre_id = (select id from ids where nom = 'A');
  select texte into t from public.notifications where membre_id = (select id from ids where nom = 'A') and texte like 'Votre inscription est approuvée%';
  insert into resultats (test, ok, detail) values ('Précisions demandées : la notification du code reste ; approuvé : elle est classée (lue)',
    n_code = 1 and n_non_lu = 0, n_code || ' code · ' || n_non_lu || ' non lue(s)');
  insert into resultats (test, ok, detail) values ('Approuvé : notification « inscription approuvée » avec le matricule',
    t like '%DFMM-99181%', coalesce(t, '—'));
  select count(*) filter (where not lu) into n_non_lu from public.notifications where membre_id = (select id from ids where nom = 'B') and sujet = 'code_messenger';
  insert into resultats (test, ok, detail) values ('Refusé : notification du code classée, pas de message d''approbation',
    n_non_lu = 0 and not exists (select 1 from public.notifications where membre_id = (select id from ids where nom = 'B') and texte like 'Votre inscription est approuvée%'),
    n_non_lu || ' non lue(s)');
end $$;

-- Après l'approbation : le signalement n'est plus possible.
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000018a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000018a1', true);
set local role authenticated;
do $$
begin
  perform public.signaler_code_envoye();
  insert into resultats (test, ok, detail) values ('Inscription approuvée : signalement refusé', false, 'accepté');
exception when raise_exception then
  insert into resultats (test, ok, detail) values ('Inscription approuvée : signalement refusé', true, sqlerrm);
end $$;
reset role;

-- ---------- 4. Les fonctions internes ne sont pas appelables par le site ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000018ad"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000018ad', true);
set local role authenticated;
do $$
begin
  perform public.texte_notif_code('UV-ZZZ999');
  insert into resultats (test, ok, detail) values ('Fonction interne du texte : refusée aux connectés', false, 'acceptée');
exception when insufficient_privilege then
  insert into resultats (test, ok, detail) values ('Fonction interne du texte : refusée aux connectés', true, sqlerrm);
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
