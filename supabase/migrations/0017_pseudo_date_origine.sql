-- =====================================================================
-- LEAGUE UV — DFMM · Pseudo à la date d'origine · migration 0017
-- Constat de Katana du 22/11/2026 : dans M-2 (18/11/2026), des membres réinscrits avec leur ancien matricule
-- restent « à identifier » (le site les suggère seulement).
-- Cause : à l'approbation avec un ancien matricule, la date d'adhésion reprend la date d'origine (0 h, Madagascar),
-- mais le pseudo du compte de jeu garde la date de la nouvelle inscription ; pour un match joué avant, le site
-- dit « pseudo connu à une autre date » et ne relie pas la ligne tout seul.
-- Correction (accord de Katana du 22/11/2026) :
--  1. decider_inscription : avec un ancien matricule, le premier pseudo de chaque compte de jeu du membre prend
--     aussi la date d'origine (seulement s'il commençait plus tard) ;
--  2. membres déjà réinscrits : même correction, une seule fois.
-- Aucune règle changée. Ne supprime rien : change seulement la date de début du premier pseudo.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- =====================================================================
begin;

-- Premier pseudo de chaque compte de jeu d'un membre : début ramené à p_debut s'il commençait plus tard.
create function public.pseudos_a_date_origine(p_membre bigint, p_debut timestamptz) returns integer
language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  update public.pseudos_historique h set debut = p_debut
  where h.compte_id in (select c.id from public.comptes_jeu c where c.membre_id = p_membre)
    and h.debut > p_debut
    and not exists (select 1 from public.pseudos_historique x
                    where x.compte_id = h.compte_id and (x.debut, x.id) < (h.debut, h.id));
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.pseudos_a_date_origine(bigint, timestamptz) from public, anon, authenticated;

-- ---------- Décision sur une inscription (administrateur) : identique à 0002, plus le point 1 ----------
create or replace function public.decider_inscription(p_membre bigint, p_decision text, p_motif text default null,
                                                      p_matricule_ancien integer default null)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; a public.matricules_anciens%rowtype; v_mat integer; v_debut timestamptz;
begin
  if not public.est_admin() then raise exception 'Accès réservé à l''administrateur.'; end if;
  select * into m from public.membres where id = p_membre for update;
  if not found then raise exception 'Candidature introuvable.'; end if;
  if m.statut not in ('en_attente', 'precisions') then raise exception 'Cette candidature a déjà été traitée.'; end if;

  if p_decision in ('refuser', 'precisions') then
    if coalesce(trim(p_motif), '') = '' then raise exception 'Le motif est obligatoire.'; end if;
    update public.membres set statut = case when p_decision = 'refuser' then 'refuse' else 'precisions' end,
      decision = jsonb_build_object('type', p_decision, 'motif', trim(p_motif), 'date', now()) where id = p_membre;
    insert into public.journal (type, objet, decision, motif)
    values ('Inscription', p_membre::text, case when p_decision = 'refuser' then 'Candidature refusée' else 'Précisions demandées' end, trim(p_motif));
    return null;
  elsif p_decision <> 'approuver' then
    raise exception 'Décision inconnue.';
  end if;

  if p_matricule_ancien is not null then
    select * into a from public.matricules_anciens where matricule = p_matricule_ancien for update;
    if not found then raise exception 'Ancien matricule DFMM-% introuvable dans la liste importée.', p_matricule_ancien; end if;
    if a.repris_par is not null then raise exception 'L''ancien matricule DFMM-% est déjà repris.', p_matricule_ancien; end if;
    v_mat := a.matricule;
    v_debut := (a.date_approbation::timestamp) at time zone 'Indian/Antananarivo';
    update public.matricules_anciens set repris_par = p_membre where matricule = v_mat;
  else
    loop
      v_mat := nextval('public.matricule_seq');
      exit when not exists (select 1 from public.membres where matricule = v_mat)
            and not exists (select 1 from public.matricules_anciens where matricule = v_mat);
    end loop;
    v_debut := now();
  end if;
  if exists (select 1 from public.membres where matricule = v_mat) then raise exception 'Le matricule DFMM-% existe déjà.', v_mat; end if;

  update public.membres set statut = 'actif', matricule = v_mat, date_approbation = v_debut,
    decision = jsonb_build_object('type', 'approuver', 'motif', nullif(trim(coalesce(p_motif, '')), ''), 'date', now(),
                                  'reprise', p_matricule_ancien is not null)
  where id = p_membre;
  insert into public.periodes (membre_id, debut) values (p_membre, v_debut);
  update public.comptes_jeu set statut = 'actif' where membre_id = p_membre and statut = 'en_pause';
  insert into public.comptes_periodes (compte_id, debut) select id, v_debut from public.comptes_jeu where membre_id = p_membre and statut = 'actif';
  -- 0017 : ancien matricule = le premier pseudo prend aussi la date d'origine.
  if p_matricule_ancien is not null then perform public.pseudos_a_date_origine(p_membre, v_debut); end if;
  insert into public.journal (type, objet, decision, motif)
  values ('Inscription', 'DFMM-' || v_mat, 'Inscription approuvée, matricule DFMM-' || v_mat
          || case when p_matricule_ancien is not null then ' repris (date d''origine conservée)' else ' attribué' end, nullif(trim(coalesce(p_motif, '')), ''));
  return v_mat;
end $$;

-- ---------- Point 2 : membres déjà réinscrits avec leur ancien matricule ----------
do $$
declare r record; n integer := 0;
begin
  for r in select m.id, m.date_approbation from public.membres m
           join public.matricules_anciens a on a.repris_par = m.id
           where m.date_approbation is not null
  loop
    n := n + public.pseudos_a_date_origine(r.id, r.date_approbation);
  end loop;
  raise notice 'Pseudos ramenés à la date d''origine : %', n;
end $$;

commit;
