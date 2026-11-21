-- =====================================================================
-- LEAGUE UV — DFMM · Lot 4A « sanctions » · migration 0009
-- Cahier, section 9 : avertissement, suspension (14 jours au plus, date de fin fixée par Katana),
-- exclusion, retrait des statistiques d'un joueur dans un match ; recours de 48 h ; levée = matchs
-- recomptés ; aucune sanction publiée. À exécuter UNE fois dans Supabase. Ne supprime rien :
-- ajoute une table et des fonctions, et renforce 2 fonctions existantes (démarches bloquées
-- pendant une suspension ; retrait soumis à Katana quand une sanction ou un match en attente est en cours).
-- =====================================================================
begin;

create table public.sanctions (
  id                bigint generated always as identity primary key,
  membre_id         bigint not null references public.membres(id),
  type              text not null check (type in ('avertissement', 'suspension', 'exclusion', 'retrait_statistiques')),
  categorie         text,                                   -- ligne du tableau-guide du cahier (facultatif)
  motif             text not null check (length(trim(motif)) > 0),   -- communiqué au joueur
  debut             timestamptz not null,
  fin               timestamptz,                            -- suspension seulement
  match_id          bigint references public.matchs(id),    -- retrait des statistiques (et lien éventuel)
  compte_actif_id   bigint references public.comptes_jeu(id), -- exclusion : compte actif à remettre en cas de levée
  recours_jusqu     timestamptz not null,
  contestation      text,
  conteste_le       timestamptz,
  statut            text not null default 'active' check (statut in ('active', 'levee')),
  decision_recours  text check (decision_recours in ('maintenue', 'levee')),
  motif_recours     text,
  recours_decide_le timestamptz,
  cree_le           timestamptz not null default clock_timestamp(),
  check ((type = 'suspension') = (fin is not null)),
  check (fin is null or fin > debut),
  check (type <> 'retrait_statistiques' or match_id is not null)
);
create index sanctions_membre on public.sanctions (membre_id, type, statut);

-- ---------- Outils ----------
create function public.est_suspendu(p_membre bigint, p_t timestamptz) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.sanctions where membre_id = p_membre and type = 'suspension'
                       and statut = 'active' and debut <= p_t and p_t < fin) $$;

create function public.libelle_sanction(p_type text) returns text
language sql immutable set search_path = ''
as $$ select case p_type when 'avertissement' then 'Avertissement' when 'suspension' then 'Suspension'
                         when 'exclusion' then 'Exclusion' else 'Statistiques d''un match retirées' end $$;

create function public.date_mg(p_t timestamptz) returns text
language sql stable set search_path = ''
as $$ select to_char(p_t at time zone 'Indian/Antananarivo', 'DD/MM/YYYY à HH24"h"MI') $$;

-- Démarches du membre : refusées pendant une suspension (le membre peut toujours contester et lire).
create or replace function public.mon_membre_actif() returns public.membres
language plpgsql stable security definer set search_path = ''
as $$
declare m public.membres%rowtype;
begin
  select * into m from public.membres where user_id = (select auth.uid());
  if not found then raise exception 'Aucune fiche membre liée à ce compte.'; end if;
  if m.statut <> 'actif' then raise exception 'Cette démarche est réservée aux membres actifs.'; end if;
  if public.est_suspendu(m.id, clock_timestamp()) then
    raise exception 'Démarche impossible pendant une suspension. Vous pouvez contester la sanction dans « Mon compte » pendant le délai prévu.';
  end if;
  return m;
end $$;

-- Retrait : automatique, sauf si une suspension ou un match en attente le concernant est en cours (Katana décide).
create or replace function public.demander_retrait(p_motif text default null) returns text
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; v_raison text;
begin
  select * into m from public.membres where user_id = (select auth.uid());
  if not found then raise exception 'Aucune fiche membre liée à ce compte.'; end if;
  if m.statut <> 'actif' then raise exception 'Cette démarche est réservée aux membres actifs.'; end if;
  if exists (select 1 from public.demandes where membre_id = m.id and type = 'retrait' and statut in ('en_attente', 'precisions')) then
    raise exception 'Une demande de retrait est déjà en cours.';
  end if;
  if public.est_suspendu(m.id, clock_timestamp()) then v_raison := 'sanction en cours';
  elsif exists (select 1 from public.match_lignes l join public.matchs x on x.id = l.match_id where l.membre_id = m.id and x.statut = 'attente') then
    v_raison := 'match en attente';
  end if;
  if v_raison is not null then
    insert into public.demandes (membre_id, type, details)
    values (m.id, 'retrait', jsonb_build_object('motif', nullif(trim(coalesce(p_motif, '')), ''), 'raison', v_raison));
    insert into public.journal (type, objet, decision, motif) values ('Demande', 'DFMM-' || m.matricule, 'Demande de retrait soumise à Katana', v_raison);
    perform public.notifier(m.id, 'Votre demande de retrait est transmise à Katana, qui décidera (' || v_raison || ').');
    return 'en_attente';
  end if;
  insert into public.demandes (membre_id, type, details, statut, decide_le, motif_decision)
  values (m.id, 'retrait', jsonb_build_object('motif', nullif(trim(coalesce(p_motif, '')), '')), 'acceptee', clock_timestamp(), 'Retrait automatique');
  perform public.appliquer_retrait(m.id, p_motif);
  return 'retire';
end $$;

-- ---------- Sanctionner (administrateur) ----------
-- p : {membre_id, type, motif, categorie?, fin_jour? (AAAA-MM-JJ, dernier jour de suspension inclus), match_id?}
create function public.sanctionner(p jsonb) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; v_type text := p->>'type'; v_motif text := nullif(trim(coalesce(p->>'motif', '')), '');
        v_t timestamptz := clock_timestamp(); v_fin timestamptz; v_jour date; v_max int; v_auj date; v_match bigint;
        v_cpt bigint; v_id bigint; v_recours timestamptz; v_txt text;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into m from public.membres where id = (p->>'membre_id')::bigint for update;
  if not found or m.matricule is null then raise exception 'Membre introuvable.'; end if;
  if v_type not in ('avertissement', 'suspension', 'exclusion', 'retrait_statistiques') then raise exception 'Type de sanction inconnu.'; end if;
  if v_motif is null then raise exception 'Le motif est obligatoire : il est communiqué au joueur.'; end if;
  if v_type in ('avertissement', 'suspension', 'exclusion') and m.statut <> 'actif' then raise exception 'Ce membre n''est pas actif.'; end if;

  if v_type = 'suspension' then
    v_jour := nullif(p->>'fin_jour', '')::date;
    if v_jour is null then raise exception 'Indiquez le dernier jour de la suspension.'; end if;
    v_max := (public.lire_param('suspension_max_jours') #>> '{}')::int;
    v_auj := (v_t at time zone 'Indian/Antananarivo')::date;
    if v_jour < v_auj then raise exception 'Le dernier jour de la suspension est déjà passé.'; end if;
    if v_jour > v_auj + v_max then raise exception 'Suspension de % jours au plus : dernier jour possible le %.', v_max, to_char(v_auj + v_max, 'DD/MM/YYYY'); end if;
    if public.est_suspendu(m.id, v_t) then raise exception 'Ce membre est déjà suspendu.'; end if;
    v_fin := ((v_jour + 1)::timestamp) at time zone 'Indian/Antananarivo';
  elsif v_type = 'retrait_statistiques' then
    v_match := nullif(p->>'match_id', '')::bigint;
    if not exists (select 1 from public.match_lignes where match_id = v_match and membre_id = m.id) then
      raise exception 'Ce joueur ne figure pas dans le match M-%.', v_match;
    end if;
    if exists (select 1 from public.sanctions where membre_id = m.id and match_id = v_match and type = 'retrait_statistiques' and statut = 'active') then
      raise exception 'Les statistiques de ce joueur sont déjà retirées pour ce match.';
    end if;
  elsif v_type = 'exclusion' then
    select id into v_cpt from public.comptes_jeu where membre_id = m.id and statut = 'actif' limit 1;
    update public.membres set statut = 'exclu' where id = m.id;
    update public.periodes set fin = v_t where membre_id = m.id and fin is null;
    update public.comptes_periodes set fin = v_t where fin is null and compte_id in (select id from public.comptes_jeu where membre_id = m.id);
    update public.comptes_jeu set statut = 'en_pause' where membre_id = m.id and statut = 'actif';
    update public.demandes set statut = 'annulee', decide_le = v_t, motif_decision = 'Annulée par une décision de Katana'
     where membre_id = m.id and statut in ('en_attente', 'precisions');
  end if;
  if v_type <> 'retrait_statistiques' then v_match := nullif(p->>'match_id', '')::bigint; end if;

  v_recours := v_t + make_interval(hours => (public.lire_param('recours_h') #>> '{}')::int);
  insert into public.sanctions (membre_id, type, categorie, motif, debut, fin, match_id, compte_actif_id, recours_jusqu)
  values (m.id, v_type, nullif(trim(coalesce(p->>'categorie', '')), ''), v_motif, v_t, v_fin, v_match, v_cpt, v_recours)
  returning id into v_id;

  v_txt := public.libelle_sanction(v_type);
  insert into public.journal (type, objet, decision, motif)
  values ('Sanction', 'DFMM-' || m.matricule, v_txt || case when v_fin is not null then ' jusqu''au ' || public.date_mg(v_fin) else '' end
          || case when v_match is not null then ' (match M-' || v_match || ')' else '' end, v_motif);
  if v_match is not null then
    insert into public.registre (match_id, type, membre_id, detail) values (v_match, 'sanction', m.id, v_txt);
  end if;
  perform public.notifier(m.id, 'Décision de Katana : ' || v_txt
    || case when v_fin is not null then ' jusqu''au ' || public.date_mg(v_fin) || ' (vos matchs de cette période ne comptent pas, aucune demande ni capture)' else '' end
    || case when v_type = 'retrait_statistiques' then ' (match M-' || v_match || ')' else '' end
    || '. Motif : ' || v_motif || '. Vous pouvez contester jusqu''au ' || public.date_mg(v_recours) || ' dans « Mon compte ».');
  return v_id;
end $$;

-- ---------- Contester (le membre, dans le délai de recours) ----------
create function public.contester_sanction(p_sanction bigint, p_texte text) returns void
language plpgsql security definer set search_path = ''
as $$
declare s public.sanctions%rowtype; v_txt text := nullif(trim(coalesce(p_texte, '')), '');
begin
  select * into s from public.sanctions where id = p_sanction for update;
  if not found or s.membre_id not in (select public.mes_membres()) then raise exception 'Sanction introuvable.'; end if;
  if s.statut <> 'active' then raise exception 'Cette sanction est levée.'; end if;
  if s.conteste_le is not null then raise exception 'Vous avez déjà contesté cette sanction.'; end if;
  if clock_timestamp() > s.recours_jusqu then raise exception 'Le délai de contestation est dépassé : la décision est définitive.'; end if;
  if v_txt is null then raise exception 'Expliquez pourquoi vous contestez.'; end if;
  update public.sanctions set contestation = v_txt, conteste_le = clock_timestamp() where id = s.id;
  insert into public.journal (type, objet, decision)
  select 'Sanction', 'DFMM-' || matricule, 'Contestation reçue : ' || public.libelle_sanction(s.type) from public.membres where id = s.membre_id;
end $$;

-- ---------- Recours ou levée (administrateur) : « maintenir » une sanction contestée, ou « lever » ----------
create function public.decider_sanction(p_sanction bigint, p_decision text, p_motif text) returns void
language plpgsql security definer set search_path = ''
as $$
declare s public.sanctions%rowtype; m public.membres%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), ''); v_t timestamptz := clock_timestamp();
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into s from public.sanctions where id = p_sanction for update;
  if not found then raise exception 'Sanction introuvable.'; end if;
  if v_motif is null then raise exception 'Le motif est obligatoire.'; end if;
  if s.statut <> 'active' then raise exception 'Cette sanction est déjà levée.'; end if;
  select * into m from public.membres where id = s.membre_id for update;
  if p_decision = 'maintenir' then
    if s.conteste_le is null then raise exception 'Cette sanction n''est pas contestée.'; end if;
    if s.decision_recours is not null then raise exception 'La contestation est déjà tranchée.'; end if;
    update public.sanctions set decision_recours = 'maintenue', motif_recours = v_motif, recours_decide_le = v_t where id = s.id;
    perform public.notifier(m.id, 'Votre contestation est examinée : la décision (' || public.libelle_sanction(s.type) || ') est maintenue. Motif : ' || v_motif);
  elsif p_decision = 'lever' then
    update public.sanctions set statut = 'levee', recours_decide_le = v_t, motif_recours = v_motif,
           decision_recours = case when s.conteste_le is not null and s.decision_recours is null then 'levee' else decision_recours end
    where id = s.id;
    if s.type = 'exclusion' and m.statut = 'exclu' then
      update public.membres set statut = 'actif' where id = m.id;
      update public.periodes set fin = null where membre_id = m.id and fin = s.debut;
      if s.compte_actif_id is not null then
        update public.comptes_periodes set fin = null where compte_id = s.compte_actif_id and fin = s.debut;
        update public.comptes_jeu set statut = 'actif' where id = s.compte_actif_id;
      end if;
    end if;
    perform public.notifier(m.id, 'Décision levée : ' || public.libelle_sanction(s.type) || '. Les matchs concernés sont recomptés. Motif : ' || v_motif);
  else
    raise exception 'Décision inconnue.';
  end if;
  insert into public.journal (type, objet, decision, motif)
  values ('Sanction', 'DFMM-' || m.matricule, case when p_decision = 'lever' then 'Sanction levée : ' else 'Sanction maintenue après contestation : ' end || public.libelle_sanction(s.type), v_motif);
  if s.match_id is not null then
    insert into public.registre (match_id, type, membre_id, detail)
    values (s.match_id, 'decision', m.id, case when p_decision = 'lever' then 'Sanction levée' else 'Sanction maintenue' end);
  end if;
end $$;

-- =====================================================================
-- Règles d'accès : jamais publiques ; le membre ne voit que les siennes
-- =====================================================================
alter table public.sanctions enable row level security;
revoke all on public.sanctions from anon, authenticated;
grant select on public.sanctions to authenticated;
create policy "admin lit" on public.sanctions for select to authenticated using ((select public.est_admin()));
create policy "membre voit les siennes" on public.sanctions for select to authenticated using (membre_id in (select public.mes_membres()));
grant select, insert, update, delete on public.sanctions to service_role;

revoke all on function public.est_suspendu(bigint, timestamptz), public.libelle_sanction(text), public.date_mg(timestamptz) from public, anon, authenticated;
revoke all on function public.sanctionner(jsonb), public.contester_sanction(bigint, text), public.decider_sanction(bigint, text, text) from public, anon;
grant execute on function public.sanctionner(jsonb), public.contester_sanction(bigint, text), public.decider_sanction(bigint, text, text) to authenticated;

commit;
