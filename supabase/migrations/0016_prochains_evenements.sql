-- =====================================================================
-- LEAGUE UV — DFMM · Prochains événements · migration 0016
-- Décisions de Katana du 22/11/2026 (incidents du M-3) et plan validé le 22/11/2026 (« 1 B, 2 oui ») :
--  - calendrier automatique des matchs de Katana : chaque mercredi et samedi à 16 h 05 ; rotation fixe des cartes
--    en boucle ; date reportée (carte manquante) = la date suivante garde sa carte ; date annulée = pas de carte,
--    la rotation continue ; premier match du calendrier : mercredi 25/11/2026 sur Ascension ;
--  - code et mot de passe de la salle : saisis par l'organisateur (Katana pour ses matchs, l'organisateur d'un match
--    libre), visibles seulement par les membres actifs non suspendus, jusqu'à 1 h (plage_fin_h) après le début ;
--  - « Je participe » (matchs de Katana) : nombre visible par tous, noms visibles par Katana seulement ;
--  - événements communautaires créés par Katana ;
--  - retard pour tous les matchs : colonne « début annoncé » des matchs de Katana (fin hors plage = match en attente,
--    comme les matchs libres ; début annoncé obligatoire, à taper par Katana pour les matchs joués avant le 25/11).
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 6 réglages, 4 tables, 2 colonnes aux matchs, des fonctions ; complète enregistrer_match
-- et le contrôle des longueurs de texte. Crée la première date du calendrier (25/11/2026, Ascension).
-- =====================================================================
begin;

-- ---------- Réglages (Administration > Paramètres > Calendrier) ----------
insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('calendrier_jour_1',          '3',       'jour',   'Jour des matchs de Katana (1er jour)',                                       'Calendrier', 1),
  ('calendrier_jour_2',          '6',       'jour',   'Jour des matchs de Katana (2e jour)',                                        'Calendrier', 2),
  ('calendrier_heure',           '"16:05"', 'heure',  'Heure de début des matchs de Katana',                                        'Calendrier', 3),
  ('salle_ouverture_min',        '15',      'entier', 'Ouverture de la salle, avant le début (min)',                                'Calendrier', 4),
  ('rotation_cartes',            '"Craqué, Ascension, Ligne de tranchées, Accident de train, Canal d''Akh, Faille"', 'texte',
                                            'Rotation des cartes des matchs de Katana (dans l''ordre, séparées par des virgules)', 'Calendrier', 5),
  ('calendrier_dates_affichees', '4',       'entier', 'Dates du calendrier préparées à l''avance',                                  'Calendrier', 6);

-- ---------- Calendrier des matchs de Katana : une ligne par date ----------
-- statut : prevu (le match a lieu ou a eu lieu), reporte (carte manquante : la date suivante prend sa carte),
-- annule (pas de carte, la rotation continue). La carte est calculée par calendrier_recalculer().
create table public.jours_match (
  id         bigint generated always as identity primary key,
  jour       date not null unique,
  debut      timestamptz not null,
  carte      text,
  statut     text not null default 'prevu' check (statut in ('prevu', 'reporte', 'annule')),
  motif      text,
  cree_le    timestamptz not null default clock_timestamp(),
  modifie_le timestamptz
);

-- ---------- Code et mot de passe de la salle (membres : lus seulement par les fonctions) ----------
create table public.salles (
  id           bigint generated always as identity primary key,
  jour_id      bigint unique references public.jours_match(id) on delete cascade,
  creneau_id   bigint unique references public.creneaux(id) on delete cascade,
  code         text,
  mot_de_passe text,
  saisi_par    bigint references public.membres(id),     -- null : Katana
  modifie_le   timestamptz not null default clock_timestamp(),
  check ((jour_id is null) <> (creneau_id is null))
);

-- ---------- « Je participe » (matchs de Katana) ----------
create table public.participations (
  jour_id   bigint not null references public.jours_match(id) on delete cascade,
  membre_id bigint not null references public.membres(id),
  cree_le   timestamptz not null default clock_timestamp(),
  primary key (jour_id, membre_id)
);

-- ---------- Événements communautaires (créés par Katana) ----------
create table public.evenements (
  id          bigint generated always as identity primary key,
  titre       text not null check (trim(titre) <> ''),
  description text,
  debut       timestamptz not null,
  fin         timestamptz check (fin is null or fin > debut),
  retire_le   timestamptz,
  cree_le     timestamptz not null default clock_timestamp(),
  modifie_le  timestamptz
);
create index evenements_debut on public.evenements (debut);

-- ---------- Matchs de Katana : date du calendrier et début annoncé ----------
alter table public.matchs
  add column jour_id       bigint unique references public.jours_match(id),
  add column debut_annonce timestamptz;                -- heure de début annoncée (match de Katana)

-- =====================================================================
-- Outils internes
-- =====================================================================
create function public.liste_cartes() returns text[]
language sql stable security definer set search_path = ''
as $$ select coalesce(array_agg(trim(x) order by n) filter (where trim(x) <> ''), '{}')
      from unnest(string_to_array(public.lire_param('rotation_cartes') #>> '{}', ',')) with ordinality as t(x, n) $$;

create function public.debut_jour(p_jour date) returns timestamptz
language sql stable security definer set search_path = ''
as $$ select (p_jour + (public.lire_param('calendrier_heure') #>> '{}')::time) at time zone 'Indian/Antananarivo' $$;

create function public.plage_fin() returns interval
language sql stable security definer set search_path = ''
as $$ select make_interval(mins => ((public.lire_param('plage_fin_h') #>> '{}')::numeric * 60)::int) $$;

-- Carte de chaque date. La première date du calendrier et les dates passées gardent leur carte (historique) ;
-- les dates à venir sont recalculées : prevu = carte suivante de la rotation, reporte = même carte à la date suivante,
-- annule = pas de carte. Les dates à venir prennent aussi l'heure de début réglée.
create function public.calendrier_recalculer() returns void
language plpgsql security definer set search_path = ''
as $$
declare r record; v_cartes text[] := public.liste_cartes(); n int; idx int := 0; premier boolean := true; pos int; v_carte text;
begin
  n := coalesce(array_length(v_cartes, 1), 0);
  for r in select * from public.jours_match order by jour for update loop
    if premier or (r.debut <= clock_timestamp() and (r.carte is not null or r.statut = 'annule')) then
      if r.carte is not null then
        pos := array_position(v_cartes, r.carte);
        if pos is not null then idx := pos - 1 + case when r.statut = 'prevu' then 1 else 0 end; end if;
      end if;
    else
      if r.statut = 'annule' or n = 0 then v_carte := null;
      else v_carte := v_cartes[(idx % n) + 1]; if r.statut = 'prevu' then idx := idx + 1; end if;
      end if;
      update public.jours_match set carte = v_carte,
             debut = case when r.debut > clock_timestamp() and r.statut = 'prevu' then public.debut_jour(r.jour) else r.debut end
       where id = r.id and (carte is distinct from v_carte
             or (r.debut > clock_timestamp() and r.statut = 'prevu' and debut is distinct from public.debut_jour(r.jour)));
    end if;
    premier := false;
  end loop;
end $$;

-- Prépare les dates à venir (mercredi et samedi par défaut) jusqu'à « calendrier_dates_affichees » dates futures.
create function public.calendrier_preparer() returns void
language plpgsql security definer set search_path = ''
as $$
declare v_j1 int := (public.lire_param('calendrier_jour_1') #>> '{}')::int; v_j2 int := (public.lire_param('calendrier_jour_2') #>> '{}')::int;
        v_n int := greatest(1, coalesce((public.lire_param('calendrier_dates_affichees') #>> '{}')::int, 4));
        v_d date; v_futures int; i int := 0; v_ajout boolean := false;
begin
  perform pg_advisory_xact_lock(hashtext('dfmm_calendrier'));
  select max(jour) into v_d from public.jours_match;
  if v_d is null then v_d := (clock_timestamp() at time zone 'Indian/Antananarivo')::date - 1; end if;
  select count(*) into v_futures from public.jours_match where debut > clock_timestamp();
  while v_futures < v_n and i < 800 loop
    v_d := v_d + 1; i := i + 1;
    if extract(dow from v_d)::int in (v_j1, v_j2) then
      insert into public.jours_match (jour, debut) values (v_d, public.debut_jour(v_d)) on conflict (jour) do nothing;
      v_ajout := true;
      if public.debut_jour(v_d) > clock_timestamp() then v_futures := v_futures + 1; end if;
    end if;
  end loop;
  if v_ajout then perform public.calendrier_recalculer(); end if;
end $$;

-- Une date peut être reportée, annulée ou rétablie tant que la date suivante n'a pas commencé.
create function public.jour_modifiable(p_jour bigint) returns boolean
language sql stable security definer set search_path = ''
as $$ select not exists (select 1 from public.jours_match a join public.jours_match b on b.jour > a.jour
                         where a.id = p_jour and b.debut <= clock_timestamp()) $$;

-- Membre actif non suspendu (ou Katana) : droit de voir le code et le mot de passe d'une salle.
create function public.voit_code_salle() returns boolean
language sql stable security definer set search_path = ''
as $$ select (select public.est_admin()) or exists (
        select 1 from public.membres m where m.user_id = (select auth.uid()) and m.statut = 'actif' and m.matricule is not null
          and not public.est_suspendu(m.id, clock_timestamp())) $$;

-- =====================================================================
-- Membres : lecture de la rubrique, « Je participe », code de la salle d'un match libre
-- =====================================================================
create function public.prochains_evenements() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_m bigint := public.mon_membre_lecteur(); v_admin boolean := (select public.est_admin());
        v_code boolean; v_actif bigint; v_plage interval := public.plage_fin(); v_n int; v_res jsonb;
begin
  if v_m is null and not v_admin then raise exception 'Réservé aux membres.'; end if;
  perform public.calendrier_preparer();
  v_code := public.voit_code_salle();
  select m.id into v_actif from public.membres m where m.id = v_m and m.statut = 'actif' and not public.est_suspendu(m.id, clock_timestamp());
  v_n := greatest(1, coalesce((public.lire_param('calendrier_dates_affichees') #>> '{}')::int, 4)) + 2;
  select jsonb_build_object(
    'maintenant', clock_timestamp(),
    'voit_code', v_code,
    'peut_participer', v_actif is not null,
    'admin', v_admin,
    'rotation', to_jsonb(public.liste_cartes()),
    'heure', public.lire_param('calendrier_heure'),
    'salle_ouverture_min', public.lire_param('salle_ouverture_min'),
    'jours', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', j.id, 'jour', j.jour, 'debut', j.debut, 'fin_plage', j.debut + v_plage,
        'carte', case when j.statut = 'annule' then null else j.carte end, 'statut', j.statut, 'motif', j.motif,
        'reporte_de', (select case when p.statut = 'reporte' then p.jour end from public.jours_match p
                       where p.jour < j.jour and p.statut <> 'annule' order by p.jour desc limit 1),
        'participants', (select count(*) from public.participations x where x.jour_id = j.id),
        'moi', v_m is not null and exists (select 1 from public.participations x where x.jour_id = j.id and x.membre_id = v_m),
        'noms', case when v_admin then coalesce((select jsonb_agg(jsonb_build_object('matricule', mb.matricule, 'nom_gamer', mb.nom_gamer) order by x.cree_le)
                                                 from public.participations x join public.membres mb on mb.id = x.membre_id where x.jour_id = j.id), '[]'::jsonb) end,
        'code', case when v_code and j.statut = 'prevu' and clock_timestamp() < j.debut + v_plage then s.code end,
        'mot_de_passe', case when v_code and j.statut = 'prevu' and clock_timestamp() < j.debut + v_plage then s.mot_de_passe end,
        'salle_saisie', s.id is not null and j.statut = 'prevu' and clock_timestamp() < j.debut + v_plage
      ) order by j.jour)
      from (select * from public.jours_match where debut + v_plage > clock_timestamp() order by jour limit v_n) j
      left join public.salles s on s.jour_id = j.id), '[]'::jsonb),
    'libres', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'debut', c.debut, 'fin_plage', c.debut + v_plage,
        'organisateur', jsonb_build_object('matricule', o.matricule, 'nom_gamer', o.nom_gamer),
        'haavk', jsonb_build_object('matricule', h.matricule, 'nom_gamer', h.nom_gamer),
        'gti', jsonb_build_object('matricule', g.matricule, 'nom_gamer', g.nom_gamer),
        'moi_organisateur', v_m is not null and c.organisateur_id = v_m,
        'code', case when v_code or (v_actif is not null and c.organisateur_id = v_actif) then s.code end,
        'mot_de_passe', case when v_code or (v_actif is not null and c.organisateur_id = v_actif) then s.mot_de_passe end,
        'salle_saisie', s.id is not null
      ) order by c.debut)
      from public.creneaux c
      join public.membres o on o.id = c.organisateur_id join public.membres h on h.id = c.resp_haavk_id join public.membres g on g.id = c.resp_gti_id
      left join public.salles s on s.creneau_id = c.id
      where c.statut = 'annonce' and c.debut + v_plage > clock_timestamp()), '[]'::jsonb),
    'evenements', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'titre', e.titre, 'description', e.description, 'debut', e.debut, 'fin', e.fin) order by e.debut)
      from public.evenements e
      where e.retire_le is null and coalesce(e.fin, e.debut + interval '1 day') > clock_timestamp()), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

-- « Je participe » (p_oui = vrai) ou « Je ne participe plus » (faux), jusqu'au début du match.
create function public.participer(p_jour bigint, p_oui boolean) returns void
language plpgsql security definer set search_path = ''
as $$
declare m public.membres; j public.jours_match%rowtype;
begin
  m := public.mon_membre_actif();
  select * into j from public.jours_match where id = p_jour;
  if not found then raise exception 'Date introuvable.'; end if;
  if j.statut <> 'prevu' then raise exception 'Ce match est % : impossible de s''inscrire.', case when j.statut = 'reporte' then 'reporté' else 'annulé' end; end if;
  if clock_timestamp() >= j.debut then raise exception 'Le match a déjà commencé.'; end if;
  if p_oui then insert into public.participations (jour_id, membre_id) values (p_jour, m.id) on conflict do nothing;
  else delete from public.participations where jour_id = p_jour and membre_id = m.id;
  end if;
end $$;

-- Code et mot de passe d'une salle. p = {jour_id | creneau_id, code, mot_de_passe} ; les deux vides = effacés.
-- Date du calendrier : Katana seulement. Match libre : son organisateur seulement (membre actif non suspendu).
-- Possible jusqu'à 1 h (plage_fin_h) après le début.
create function public.noter_salle(p jsonb) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_jour bigint := nullif(p->>'jour_id', '')::bigint; v_cr bigint := nullif(p->>'creneau_id', '')::bigint;
        v_code text := nullif(trim(coalesce(p->>'code', '')), ''); v_mdp text := nullif(trim(coalesce(p->>'mot_de_passe', '')), '');
        v_debut timestamptz; v_par bigint := null; j public.jours_match%rowtype; c public.creneaux%rowtype; m public.membres;
begin
  if (v_jour is null) = (v_cr is null) then raise exception 'Indiquez la date du calendrier ou le match libre.'; end if;
  perform public.verifier_longueur(v_code, 'court', 'code de la salle');
  perform public.verifier_longueur(v_mdp, 'court', 'mot de passe de la salle');
  if v_jour is not null then
    if not (select public.est_admin()) then raise exception 'Réservé à Katana, organisateur de ce match.'; end if;
    select * into j from public.jours_match where id = v_jour;
    if not found then raise exception 'Date introuvable.'; end if;
    if j.statut <> 'prevu' then raise exception 'Ce match n''est pas prévu (reporté ou annulé).'; end if;
    v_debut := j.debut;
  else
    m := public.mon_membre_actif();
    select * into c from public.creneaux where id = v_cr;
    if not found then raise exception 'Match libre introuvable.'; end if;
    if c.organisateur_id <> m.id then raise exception 'Seul l''organisateur du match libre saisit le code de la salle.'; end if;
    if c.statut <> 'annonce' then raise exception 'Ce match libre n''est pas annoncé (retenu, refusé ou annulé).'; end if;
    v_debut := c.debut; v_par := m.id;
  end if;
  if clock_timestamp() >= v_debut + public.plage_fin() then raise exception 'Le match est terminé : le code ne peut plus être changé.'; end if;
  if v_code is null and v_mdp is null then
    delete from public.salles where jour_id is not distinct from v_jour and creneau_id is not distinct from v_cr;
  elsif v_jour is not null then
    insert into public.salles (jour_id, code, mot_de_passe, saisi_par) values (v_jour, v_code, v_mdp, null)
    on conflict (jour_id) do update set code = excluded.code, mot_de_passe = excluded.mot_de_passe, saisi_par = null, modifie_le = clock_timestamp();
  else
    insert into public.salles (creneau_id, code, mot_de_passe, saisi_par) values (v_cr, v_code, v_mdp, v_par)
    on conflict (creneau_id) do update set code = excluded.code, mot_de_passe = excluded.mot_de_passe, saisi_par = excluded.saisi_par, modifie_le = clock_timestamp();
  end if;
end $$;

-- =====================================================================
-- Katana : calendrier (report, annulation, rétablissement)
-- =====================================================================
create function public.calendrier_admin() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare v_plage interval := public.plage_fin();
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  perform public.calendrier_preparer();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', j.id, 'jour', j.jour, 'debut', j.debut, 'carte', j.carte, 'statut', j.statut, 'motif', j.motif,
      'modifiable', public.jour_modifiable(j.id), 'passe', j.debut <= clock_timestamp(),
      'salle_ouverte', clock_timestamp() < j.debut + v_plage,
      'code', s.code, 'mot_de_passe', s.mot_de_passe,
      'match_id', mt.id, 'match_statut', mt.statut,
      'noms', coalesce((select jsonb_agg(jsonb_build_object('matricule', mb.matricule, 'nom_gamer', mb.nom_gamer) order by x.cree_le)
                        from public.participations x join public.membres mb on mb.id = x.membre_id where x.jour_id = j.id), '[]'::jsonb)
    ) order by j.jour)
    from public.jours_match j left join public.salles s on s.jour_id = j.id left join public.matchs mt on mt.jour_id = j.id
    where j.jour >= (clock_timestamp() at time zone 'Indian/Antananarivo')::date - 14), '[]'::jsonb);
end $$;

-- p_decision : reporter (carte manquante), annuler, retablir. Motif facultatif.
create function public.decider_jour(p_jour bigint, p_decision text, p_motif text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare j public.jours_match%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), '');
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  perform public.verifier_longueur(v_motif, 'long', 'motif');
  select * into j from public.jours_match where id = p_jour for update;
  if not found then raise exception 'Date introuvable.'; end if;
  if not public.jour_modifiable(p_jour) then raise exception 'La date suivante a déjà commencé : cette date ne peut plus être changée.'; end if;
  if p_decision in ('reporter', 'annuler') then
    if j.statut <> 'prevu' then raise exception 'Cette date est déjà reportée ou annulée.'; end if;
    if exists (select 1 from public.matchs where jour_id = p_jour) then raise exception 'Un match est déjà saisi pour cette date.'; end if;
    update public.jours_match set statut = case when p_decision = 'reporter' then 'reporte' else 'annule' end,
           motif = coalesce(v_motif, case when p_decision = 'reporter' then 'Carte manquante' end), modifie_le = clock_timestamp()
     where id = p_jour;
  elsif p_decision = 'retablir' then
    if j.statut = 'prevu' then raise exception 'Cette date est déjà prévue.'; end if;
    update public.jours_match set statut = 'prevu', motif = null, modifie_le = clock_timestamp() where id = p_jour;
  else
    raise exception 'Décision inconnue.';
  end if;
  insert into public.journal (type, objet, decision)
  values ('Calendrier', to_char(j.jour, 'DD/MM/YYYY'),
          case p_decision when 'reporter' then 'Date reportée' when 'annuler' then 'Date annulée' else 'Date rétablie' end
          || coalesce(' : ' || v_motif, ''));
  perform public.calendrier_recalculer();
end $$;

-- =====================================================================
-- Matchs de Katana : date du calendrier et début annoncé (enregistrer_match complétée)
-- =====================================================================
create or replace function public.enregistrer_match(p jsonb) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint := nullif(p->>'id', '')::bigint; m public.matchs%rowtype; l jsonb; i int := 0;
        v_membre bigint; v_res text; v_phase boolean; v_jour bigint := nullif(p->>'jour_id', '')::bigint; j public.jours_match%rowtype;
        v_debut timestamptz := nullif(p->>'debut_annonce', '')::timestamptz; v_carte text := nullif(trim(p->>'carte'), '');
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  if v_jour is not null then
    select * into j from public.jours_match where id = v_jour;
    if not found then raise exception 'Date du calendrier introuvable.'; end if;
    if j.statut <> 'prevu' then raise exception 'Cette date du calendrier est reportée ou annulée.'; end if;
    if exists (select 1 from public.matchs where jour_id = v_jour and id is distinct from v_id) then raise exception 'Un match est déjà saisi pour cette date du calendrier.'; end if;
    v_debut := coalesce(v_debut, j.debut); v_carte := coalesce(v_carte, j.carte);
  end if;
  if v_id is null then
    select (valeur = 'true'::jsonb) into v_phase from public.parametres where cle = 'phase_demarrage';
    if not exists (select 1 from public.saisons where id = (p->>'saison_id')::bigint) then raise exception 'Choisissez une saison.'; end if;
    insert into public.matchs (saison_id, type, demarrage, carte, mode, fin, notes, jour_id, debut_annonce)
    values ((p->>'saison_id')::bigint, 'katana', coalesce(v_phase, false), v_carte, nullif(trim(p->>'mode'), ''),
            nullif(p->>'fin', '')::timestamptz, nullif(trim(p->>'notes'), ''), v_jour, v_debut)
    returning id into v_id;
    insert into public.registre (match_id, type, detail)
    values (v_id, 'match_declare', 'Match de Katana enregistré' || case when coalesce(v_phase, false) then ' (saisie de démarrage)' else '' end
            || case when v_jour is not null then ' (calendrier du ' || to_char(j.jour, 'DD/MM/YYYY') || ')' else '' end);
  else
    select * into m from public.matchs where id = v_id for update;
    if not found then raise exception 'Match introuvable.'; end if;
    if m.statut not in ('brouillon', 'attente') then raise exception 'Ce match est déjà tranché : repassez-le en brouillon pour le modifier.'; end if;
    update public.matchs set saison_id = (p->>'saison_id')::bigint, carte = v_carte, mode = nullif(trim(p->>'mode'), ''),
           fin = nullif(p->>'fin', '')::timestamptz, notes = nullif(trim(p->>'notes'), ''), modifie_le = now(),
           jour_id = case when m.type = 'katana' and p ? 'jour_id' then v_jour else jour_id end,
           debut_annonce = case when m.type = 'katana' and (p ? 'debut_annonce' or v_jour is not null) then v_debut else debut_annonce end
    where id = v_id;
  end if;
  delete from public.match_lignes where match_id = v_id;
  for l in select * from jsonb_array_elements(coalesce(p->'lignes', '[]'::jsonb)) loop
    i := i + 1;
    v_membre := null; v_res := coalesce(nullif(l->>'resolution', ''), 'non_inscrit');
    if nullif(l->>'compte_id', '') is not null then
      select membre_id into v_membre from public.comptes_jeu where id = (l->>'compte_id')::bigint;
      if v_membre is null then raise exception 'Ligne % : compte de jeu introuvable.', i; end if;
      if v_res not in ('auto', 'manuel') then v_res := 'manuel'; end if;
    elsif v_res in ('auto', 'manuel') then v_res := 'non_inscrit';
    end if;
    insert into public.match_lignes (match_id, rang, faction, pseudo, compte_id, membre_id, resolution,
                                     score, elim, morts, assist, med, ing, obj, tac)
    values (v_id, i, nullif(l->>'faction', ''), trim(coalesce(l->>'pseudo', '')), nullif(l->>'compte_id', '')::bigint, v_membre, v_res,
            nullif(l->>'score', '')::numeric, nullif(l->>'elim', '')::numeric, nullif(l->>'morts', '')::numeric, nullif(l->>'assist', '')::numeric,
            nullif(l->>'med', '')::numeric, nullif(l->>'ing', '')::numeric, nullif(l->>'obj', '')::numeric, nullif(l->>'tac', '')::numeric);
  end loop;
  return v_id;
end $$;

-- =====================================================================
-- Longueurs maximales (PR A) : événements et motifs du calendrier
-- =====================================================================
create or replace function public.longueurs_textes() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name in ('messages', 'messages_litige') then
    perform public.verifier_longueur(new.texte, 'long', 'message');
  elsif tg_table_name = 'sanctions' then
    perform public.verifier_longueur(new.contestation, 'long', 'contestation');
  elsif tg_table_name = 'creneaux' then
    perform public.verifier_longueur(new.motif, 'long', 'motif');
  elsif tg_table_name = 'demandes' then
    perform public.verifier_longueur(new.details->>'pseudo', 'court', 'pseudo');
    perform public.verifier_longueur(new.details->>'pseudo_declare', 'court', 'pseudo');
    perform public.verifier_longueur(new.details->>'uid', 'court', 'UID');
    perform public.verifier_longueur(new.details->>'motif', 'long', 'motif');
  elsif tg_table_name = 'membres' then
    perform public.verifier_longueur(new.nom_gamer, 'court', 'nom de gamer');
  elsif tg_table_name = 'membres_prives' then
    perform public.verifier_longueur(new.nom_reel, 'court', 'nom réel');
    perform public.verifier_longueur(new.email, 'court', 'e-mail');
    perform public.verifier_longueur(new.clan, 'court', 'clan');
    perform public.verifier_longueur(new.pays, 'court', 'pays');
    perform public.verifier_longueur(new.facebook, 'long', 'lien Facebook');
  elsif tg_table_name = 'evenements' then
    perform public.verifier_longueur(new.titre, 'court', 'titre');
    perform public.verifier_longueur(new.description, 'long', 'description');
  end if;
  return new;
end $$;
create trigger longueurs_textes before insert or update of titre, description on public.evenements
  for each row execute function public.longueurs_textes();

-- =====================================================================
-- Droits
-- =====================================================================
alter table public.jours_match enable row level security;
alter table public.salles enable row level security;
alter table public.participations enable row level security;
alter table public.evenements enable row level security;
revoke all on public.jours_match, public.salles, public.participations, public.evenements from anon, authenticated;
-- Calendrier, participations et salles : lecture directe par l'administrateur seulement (sauvegarde) ;
-- les membres passent par prochains_evenements(), qui contrôle qui voit le code.
grant select on public.jours_match, public.participations, public.salles to authenticated;
create policy "admin lit" on public.jours_match for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.participations for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.salles for select to authenticated using ((select public.est_admin()));
-- Événements : Katana crée, modifie et retire (comme les actualités) ; les membres lisent par prochains_evenements().
grant select, insert, update on public.evenements to authenticated;
create policy "admin gère" on public.evenements for all to authenticated using ((select public.est_admin())) with check ((select public.est_admin()));
grant select, insert, update, delete on public.jours_match, public.salles, public.participations, public.evenements to service_role;

revoke all on function public.liste_cartes(), public.debut_jour(date), public.plage_fin(), public.calendrier_recalculer(),
  public.calendrier_preparer(), public.jour_modifiable(bigint), public.voit_code_salle() from public, anon, authenticated;
revoke all on function public.prochains_evenements(), public.participer(bigint, boolean), public.noter_salle(jsonb),
  public.calendrier_admin(), public.decider_jour(bigint, text, text) from public, anon;
grant execute on function public.prochains_evenements(), public.participer(bigint, boolean), public.noter_salle(jsonb),
  public.calendrier_admin(), public.decider_jour(bigint, text, text) to authenticated;

-- ---------- Première date du calendrier : mercredi 25/11/2026 sur Ascension (décision de Katana du 22/11/2026) ----------
insert into public.jours_match (jour, debut, carte) values ('2026-11-25', public.debut_jour('2026-11-25'), 'Ascension');

commit;
