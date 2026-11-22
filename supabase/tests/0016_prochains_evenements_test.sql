-- =====================================================================
-- LEAGUE UV — DFMM · Test de la migration 0016 (prochains événements)
-- À exécuter APRÈS la migration 0016. Faux membres seulement (anciens matricules fictifs 99161 à 99164),
-- fausse saison, faux calendrier, faux match libre, faux événements. Tout est annulé à la fin.
-- Le test remplace le calendrier par un faux (dates à partir du 2e mercredi à venir) le temps du test.
-- =====================================================================
begin;
create temp table resultats (n serial, test text, ok boolean, detail text);
grant all on resultats to anon, authenticated, service_role;
grant all on sequence resultats_n_seq to anon, authenticated, service_role;
create temp table ids (nom text primary key, id bigint);
grant all on ids to anon, authenticated, service_role;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000c1', 'faux.admin16@test.invalid'),
  ('00000000-0000-4000-8000-0000000016a1', 'faux.16a@test.invalid'),
  ('00000000-0000-4000-8000-0000000016b1', 'faux.16b@test.invalid'),
  ('00000000-0000-4000-8000-0000000016c1', 'faux.16c@test.invalid'),
  ('00000000-0000-4000-8000-0000000016d1', 'faux.16d@test.invalid'),
  ('00000000-0000-4000-8000-0000000016e1', 'faux.16e@test.invalid');
insert into public.admins (user_id) values ('00000000-0000-4000-8000-0000000000c1') on conflict do nothing;
insert into public.matricules_anciens (matricule, nom_gamer, date_approbation) values
  (99161, 'Faux 16A', '2026-11-18'), (99162, 'Faux 16B', '2026-11-18'), (99163, 'Faux 16C', '2026-11-18'), (99164, 'Faux 16D', '2026-11-18');

set local role service_role;
do $$
declare k text;
begin
  foreach k in array array['a', 'b', 'c', 'd'] loop
    insert into ids select upper(k), public.creer_inscription(jsonb_build_object('user_id', '00000000-0000-4000-8000-0000000016' || k || '1',
      'nom_gamer', 'Faux 16' || upper(k), 'email', '16' || k || '@x', 'facebook', 'fb/16' || k, 'pseudo', 'Seize ' || upper(k),
      'uid', '99160' || ascii(k), 'empreinte_email', 'e16' || k, 'empreinte_facebook', 'f16' || k, 'residence', 'Madagascar',
      'comprend_mg', true, 'parle_mg', true, 'origine_mg', true));
  end loop;
end $$;
reset role;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);
set local role authenticated;
do $$
begin
  perform public.decider_inscription((select id from ids where nom = 'A'), 'approuver', null, 99161);
  perform public.decider_inscription((select id from ids where nom = 'B'), 'approuver', null, 99162);
  perform public.decider_inscription((select id from ids where nom = 'C'), 'approuver', null, 99163);
  perform public.decider_inscription((select id from ids where nom = 'D'), 'approuver', null, 99164);
end $$;
reset role;

-- ---------- Préparation (rôle propriétaire) : A actif, B suspendu, C exclu, D actif ; faux calendrier ----------
do $$
declare td date := (clock_timestamp() at time zone 'Indian/Antananarivo')::date; d0 date; s bigint;
begin
  insert into ids select 'mA', id from public.membres where matricule = 99161;
  insert into ids select 'mB', id from public.membres where matricule = 99162;
  insert into ids select 'mC', id from public.membres where matricule = 99163;
  insert into ids select 'mD', id from public.membres where matricule = 99164;
  insert into public.sanctions (membre_id, type, motif, debut, fin, recours_jusqu)
  values ((select id from ids where nom = 'mB'), 'suspension', 'Test 0016', clock_timestamp() - interval '1 day', clock_timestamp() + interval '5 days', clock_timestamp() + interval '1 day');
  update public.membres set statut = 'exclu' where id = (select id from ids where nom = 'mC');
  -- Faux calendrier : dates sans match saisi retirées le temps du test ; 1re date = 2e mercredi à venir, Ascension.
  delete from public.jours_match j where not exists (select 1 from public.matchs mt where mt.jour_id = j.id);
  d0 := td + 2 + ((3 - extract(dow from td + 2)::int + 7) % 7);
  insert into ids values ('d0', d0 - date '2000-01-01');
  insert into public.jours_match (jour, debut, carte) values (d0, public.debut_jour(d0), 'Ascension');
  insert into public.saisons (nom, debut, fin) values ('Saison test 0016', td - 30, td + 60) returning id into s;
  insert into ids values ('S', s);
  -- Faux match libre annoncé par A dans 3 h (responsables A et D).
  insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut)
  values (s, (select id from ids where nom = 'mA'), (select id from ids where nom = 'mA'), (select id from ids where nom = 'mD'), clock_timestamp() + interval '3 hours')
  returning id into s;
  insert into ids values ('CR', s);
end $$;

-- ---------- Réglages et calendrier ----------
do $$
declare n int; v text; d0 date := date '2000-01-01' + (select id from ids where nom = 'd0')::int; c text;
begin
  select count(*), string_agg(cle || '=' || valeur::text, ', ' order by ordre) into n, v from public.parametres where section = 'Calendrier';
  insert into resultats (test, ok, detail) values ('6 réglages Calendrier (mercredi, samedi, 16:05, 15 min, 6 cartes, 4 dates)',
    n = 6 and v like 'calendrier_jour_1=3, calendrier_jour_2=6, calendrier_heure="16:05", salle_ouverture_min=15, rotation_cartes="Craqué, Ascension, Ligne de tranchées, Accident de train, Canal d''Akh, Faille", calendrier_dates_affichees=4', coalesce(v, 'aucun'));
  select string_agg(x, ' | ') into v from unnest(public.liste_cartes()) x;
  insert into resultats (test, ok, detail) values ('Rotation lue dans l''ordre', v = 'Craqué | Ascension | Ligne de tranchées | Accident de train | Canal d''Akh | Faille', v);
  perform public.calendrier_preparer();
  select count(*), string_agg(to_char(jour, 'Dy') || ' ' || coalesce(carte, '-'), ', ' order by jour) into n, v from public.jours_match where debut > clock_timestamp();
  insert into resultats (test, ok, detail) values ('4 dates préparées, mercredi et samedi, rotation à partir d''Ascension',
    n = 4 and v = 'Wed Ascension, Sat Ligne de tranchées, Wed Accident de train, Sat Canal d''Akh', v);
  select string_agg(distinct to_char(debut at time zone 'Indian/Antananarivo', 'HH24:MI'), ',') into v from public.jours_match where debut > clock_timestamp();
  insert into resultats (test, ok, detail) values ('Début à 16 h 05 (heure de Madagascar)', v = '16:05', v);
  insert into ids select 'J' || row_number() over (order by jour), id from public.jours_match where debut > clock_timestamp();
  perform public.calendrier_preparer();
  select count(*) into n from public.jours_match where debut > clock_timestamp();
  insert into resultats (test, ok, detail) values ('Préparer une 2e fois n''ajoute rien', n = 4, n || ' date(s)');
end $$;

-- ---------- Membre actif (A) : lecture, participation, refus des démarches de Katana ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000016a1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000016a1', true);
set local role authenticated;
do $$
declare r jsonb; j1 bigint := (select id from ids where nom = 'J1'); ok boolean; n int;
begin
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Membre actif : 4 dates, voit le code, peut participer, pas de noms',
    jsonb_array_length(r->'jours') = 4 and (r->>'voit_code')::boolean and (r->>'peut_participer')::boolean and (r->'jours'->0->'noms') = 'null'::jsonb
    and r->'jours'->0->>'carte' = 'Ascension' and r->'jours'->0->>'code' is null, left(r::text, 200));
  perform public.participer(j1, true);
  perform public.participer(j1, true);
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Je participe : 1 participant, compté une seule fois', (r->'jours'->0->>'participants')::int = 1 and (r->'jours'->0->>'moi')::boolean, r->'jours'->0->>'participants');
  ok := false; begin perform public.noter_salle(jsonb_build_object('jour_id', j1, 'code', '123', 'mot_de_passe', 'x')); exception when others then ok := sqlerrm like '%Katana%'; end;
  insert into resultats (test, ok, detail) values ('Un membre ne saisit pas le code d''un match de Katana', ok, '');
  ok := false; begin perform public.decider_jour(j1, 'reporter'); exception when others then ok := sqlerrm like '%administrateur%'; end;
  insert into resultats (test, ok, detail) values ('Un membre ne reporte pas une date', ok, '');
  select count(*) into n from public.salles;
  insert into resultats (test, ok, detail) values ('Table des salles illisible directement par un membre', n = 0, n || ' ligne(s)');
  select count(*) into n from public.jours_match;
  insert into resultats (test, ok, detail) values ('Calendrier non lisible directement par un membre (passe par la fonction)', n = 0, n || ' ligne(s)');
  -- Match libre de A : code saisi par l'organisateur.
  perform public.noter_salle(jsonb_build_object('creneau_id', (select id from ids where nom = 'CR'), 'code', 'L-555', 'mot_de_passe', 'libre'));
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Match libre : code saisi par l''organisateur et affiché',
    jsonb_array_length(r->'libres') = 1 and r->'libres'->0->>'code' = 'L-555' and (r->'libres'->0->>'moi_organisateur')::boolean, left((r->'libres')::text, 200));
  ok := false; begin perform public.noter_salle(jsonb_build_object('creneau_id', (select id from ids where nom = 'CR'), 'code', repeat('9', 101))); exception when others then ok := sqlerrm like '%trop long%'; end;
  insert into resultats (test, ok, detail) values ('Code trop long refusé', ok, '');
end $$;
reset role;

-- ---------- Membre actif non organisateur (D) ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000016d1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000016d1', true);
set local role authenticated;
do $$
declare r jsonb; ok boolean;
begin
  ok := false; begin perform public.noter_salle(jsonb_build_object('creneau_id', (select id from ids where nom = 'CR'), 'code', 'pirate')); exception when others then ok := sqlerrm like '%organisateur%'; end;
  insert into resultats (test, ok, detail) values ('Un responsable non organisateur ne change pas le code', ok, '');
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Membre actif D : voit le code du match libre, pas l''organisateur',
    r->'libres'->0->>'code' = 'L-555' and not (r->'libres'->0->>'moi_organisateur')::boolean, left((r->'libres')::text, 120));
end $$;
reset role;

-- ---------- Katana : code de la salle, noms des participants, report, annulation, rétablissement ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);
set local role authenticated;
do $$
declare r jsonb; j1 bigint := (select id from ids where nom = 'J1'); j2 bigint := (select id from ids where nom = 'J2');
        j3 bigint := (select id from ids where nom = 'J3'); v text; ok boolean; m bigint;
begin
  perform public.noter_salle(jsonb_build_object('jour_id', j1, 'code', '4242', 'mot_de_passe', 'uv'));
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Katana : code saisi et noms des participants visibles',
    r->'jours'->0->>'code' = '4242' and r->'jours'->0->'noms'->0->>'nom_gamer' = 'Faux 16A', left((r->'jours'->0)::text, 200));
  perform public.decider_jour(j2, 'reporter');
  select string_agg(statut || ' ' || coalesce(carte, '-'), ', ' order by jour) into v from public.jours_match where debut > clock_timestamp();
  insert into resultats (test, ok, detail) values ('Date reportée : la date suivante garde sa carte, la rotation reprend après',
    v = 'prevu Ascension, reporte Ligne de tranchées, prevu Ligne de tranchées, prevu Accident de train', v);
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Rubrique : motif « Carte manquante » et « reporté du » sur la date suivante',
    r->'jours'->1->>'motif' = 'Carte manquante' and r->'jours'->2->>'reporte_de' = r->'jours'->1->>'jour', left((r->'jours'->2)::text, 160));
  perform public.decider_jour(j3, 'annuler', 'Jour férié');
  select string_agg(statut || ' ' || coalesce(carte, '-'), ', ' order by jour) into v from public.jours_match where debut > clock_timestamp();
  insert into resultats (test, ok, detail) values ('Date annulée : pas de carte, la rotation continue au match suivant',
    v = 'prevu Ascension, reporte Ligne de tranchées, annule -, prevu Ligne de tranchées', v);
  perform public.decider_jour(j2, 'retablir'); perform public.decider_jour(j3, 'retablir');
  select string_agg(statut || ' ' || coalesce(carte, '-'), ', ' order by jour) into v from public.jours_match where debut > clock_timestamp();
  insert into resultats (test, ok, detail) values ('Dates rétablies : rotation d''origine',
    v = 'prevu Ascension, prevu Ligne de tranchées, prevu Accident de train, prevu Canal d''Akh', v);
  ok := false; begin perform public.decider_jour(j2, 'retablir'); exception when others then ok := sqlerrm like '%déjà prévue%'; end;
  insert into resultats (test, ok, detail) values ('Rétablir une date déjà prévue : refusé', ok, '');
  select count(*)::text into v from public.journal where type = 'Calendrier';
  insert into resultats (test, ok, detail) values ('Décisions notées au journal', v::int >= 4, v);
  -- Match saisi depuis le calendrier : carte et début annoncé repris de la date.
  m := public.enregistrer_match(jsonb_build_object('saison_id', (select id from ids where nom = 'S'), 'jour_id', j1, 'lignes', '[]'::jsonb));
  select coalesce(carte, '-') || ' ' || coalesce(to_char(debut_annonce at time zone 'Indian/Antananarivo', 'HH24:MI'), '-') into v from public.matchs where id = m;
  insert into resultats (test, ok, detail) values ('Match saisi depuis la date : carte et début annoncé repris', v = 'Ascension 16:05', v);
  ok := false; begin perform public.enregistrer_match(jsonb_build_object('saison_id', (select id from ids where nom = 'S'), 'jour_id', j1)); exception when others then ok := sqlerrm like '%déjà saisi%'; end;
  insert into resultats (test, ok, detail) values ('Un seul match par date du calendrier', ok, '');
  ok := false; begin perform public.decider_jour(j1, 'annuler'); exception when others then ok := sqlerrm like '%déjà saisi%'; end;
  insert into resultats (test, ok, detail) values ('Date avec un match saisi : ni report ni annulation', ok, '');
  m := public.enregistrer_match(jsonb_build_object('saison_id', (select id from ids where nom = 'S'), 'debut_annonce', '2026-11-21T16:00:00+03:00', 'lignes', '[]'::jsonb));
  m := public.enregistrer_match(jsonb_build_object('id', m, 'saison_id', (select id from ids where nom = 'S'), 'debut_annonce', '2026-11-21T16:10:00+03:00', 'lignes', '[]'::jsonb));
  select to_char(debut_annonce at time zone 'Indian/Antananarivo', 'DD/MM HH24:MI') || ' ' || coalesce(jour_id::text, 'sans date') into v from public.matchs where id = m;
  insert into resultats (test, ok, detail) values ('Match ancien : début annoncé tapé par Katana et modifiable', v = '21/11 16:10 sans date', v);
  -- Événements communautaires.
  insert into public.evenements (titre, description, debut) values ('Tournoi test 0016', 'Description', clock_timestamp() + interval '2 days');
  insert into public.evenements (titre, debut, retire_le) values ('Retiré test 0016', clock_timestamp() + interval '2 days', clock_timestamp());
  insert into public.evenements (titre, debut, fin) values ('Passé test 0016', clock_timestamp() - interval '3 days', clock_timestamp() - interval '2 days');
  ok := false; begin insert into public.evenements (titre, debut) values (repeat('x', 101), clock_timestamp()); exception when others then ok := sqlerrm like '%trop long%'; end;
  insert into resultats (test, ok, detail) values ('Titre d''événement trop long refusé', ok, '');
  r := public.calendrier_admin();
  insert into resultats (test, ok, detail) values ('Écran du calendrier de Katana : dates, code, noms, match lié',
    jsonb_array_length(r) >= 4 and r->0->>'code' = '4242' and r->0->>'match_id' is not null and jsonb_array_length(r->0->'noms') = 1, left(r::text, 160));
end $$;
reset role;

-- ---------- Membre suspendu (B) ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000016b1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000016b1', true);
set local role authenticated;
do $$
declare r jsonb; ok boolean;
begin
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Membre suspendu : voit la rubrique mais ni le code ni « Je participe »',
    jsonb_array_length(r->'jours') = 4 and not (r->>'voit_code')::boolean and not (r->>'peut_participer')::boolean
    and r->'jours'->0->>'code' is null and r->'libres'->0->>'code' is null and (r->'jours'->0->>'participants')::int = 1, left(r::text, 160));
  ok := false; begin perform public.participer((select id from ids where nom = 'J1'), true); exception when others then ok := sqlerrm like '%suspension%'; end;
  insert into resultats (test, ok, detail) values ('Membre suspendu : « Je participe » refusé', ok, '');
  insert into resultats (test, ok, detail) values ('Événements : seul l''événement à venir non retiré est affiché',
    jsonb_array_length(r->'evenements') = 1 and r->'evenements'->0->>'titre' = 'Tournoi test 0016', (r->'evenements')::text);
  ok := false; begin insert into public.evenements (titre, debut) values ('Pirate', clock_timestamp()); exception when others then ok := true; end;
  insert into resultats (test, ok, detail) values ('Un membre ne crée pas d''événement', ok, '');
end $$;
reset role;

-- ---------- Membre exclu (C), compte sans fiche, visiteur ----------
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000016c1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000016c1', true);
set local role authenticated;
do $$
declare r jsonb;
begin
  r := public.prochains_evenements();
  insert into resultats (test, ok, detail) values ('Membre exclu : rubrique lisible, sans code', not (r->>'voit_code')::boolean and r->'jours'->0->>'code' is null, left(r::text, 100));
end $$;
reset role;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000016e1"}', true),
       set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000016e1', true);
set local role authenticated;
do $$
declare ok boolean := false;
begin
  begin perform public.prochains_evenements(); exception when others then ok := sqlerrm like '%Réservé aux membres%'; end;
  insert into resultats (test, ok, detail) values ('Compte connecté sans fiche membre : refusé', ok, '');
end $$;
reset role;
set local role anon;
do $$
declare ok boolean := false;
begin
  begin perform public.prochains_evenements(); exception when others then ok := true; end;
  insert into resultats (test, ok, detail) values ('Visiteur non connecté : refusé', ok, '');
end $$;
reset role;

-- ---------- Dates passées : plus modifiables quand la date suivante a commencé ; historique gardé ----------
do $$
declare td date := (clock_timestamp() at time zone 'Indian/Antananarivo')::date; a bigint; b bigint; v text;
begin
  insert into public.jours_match (jour, debut, carte) values (td - 10, public.debut_jour(td - 10), 'Faille') returning id into a;
  insert into public.jours_match (jour, debut) values (td - 6, public.debut_jour(td - 6)) returning id into b;
  perform public.calendrier_recalculer();
  select coalesce(carte, '-') into v from public.jours_match where id = b;
  insert into resultats (test, ok, detail) values ('Après Faille vient Craqué (rotation en boucle)', v = 'Craqué', v);
  insert into resultats (test, ok, detail) values ('Date passée suivie d''une date commencée : non modifiable', not public.jour_modifiable(a), '');
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
