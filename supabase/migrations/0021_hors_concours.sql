-- =====================================================================
-- LEAGUE UV — DFMM · Membre « hors concours » · migration 0021
-- Décisions de Katana du 25/11/2026 : Katana (DFMM-6, relié à sa connexion administrateur) joue aussi.
-- Un membre déclaré hors concours figure au classement à titre indicatif (« HC » à la place du rang),
-- n'est jamais lauréat, ne reçoit aucun lot, et ses statistiques n'entrent pas dans le calcul du seuil
-- BEST (médiane) ni du Q1. Ses lignes de match comptent normalement pour le seuil de 50 % et pour les
-- contrôles des matchs. Le calcul du classement est fait par le site (js/regles.js, L.classer) ;
-- la base garde ici l'indicateur, sa modification (journal) et le refus d'un lot.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 1 colonne et 1 fonction, et complète enregistrer_attribution.
-- =====================================================================
begin;

-- ---------- Indicateur ----------
alter table public.membres add column hors_concours boolean not null default false;

-- ---------- Déclarer ou retirer le statut (administrateur, motif obligatoire, journal) ----------
create function public.definir_hors_concours(p_membre bigint, p_valeur boolean, p_motif text) returns void
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; v_motif text := nullif(btrim(coalesce(p_motif, '')), '');
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  if p_valeur is null then raise exception 'Choisissez oui ou non.'; end if;
  if v_motif is null then raise exception 'Le motif est obligatoire.'; end if;
  select * into m from public.membres where id = p_membre for update;
  if not found or m.matricule is null then raise exception 'Membre introuvable.'; end if;
  if m.hors_concours = p_valeur then
    raise exception 'DFMM-% est déjà %.', m.matricule, case when p_valeur then 'hors concours' else 'en concours' end;
  end if;
  update public.membres set hors_concours = p_valeur where id = m.id;
  insert into public.journal (type, objet, decision, motif)
  values ('Membre', 'DFMM-' || m.matricule,
          case when p_valeur then 'Déclaré hors concours (au classement sans titre ni lot)' else 'Remis en concours' end, v_motif);
end $$;

revoke all on function public.definir_hors_concours(bigint, boolean, text) from public, anon;
grant execute on function public.definir_hors_concours(bigint, boolean, text) to authenticated;

-- ---------- Lots : identique à 0011, plus le refus d'un bénéficiaire hors concours ----------
create or replace function public.enregistrer_attribution(p_publication bigint, p_resultats jsonb) returns int
language plpgsql security definer set search_path = ''
as $$
declare pub public.publications%rowtype; r jsonb; v_membre bigint; v_hc boolean; n int := 0; v_vus bigint[] := '{}'; v_nom text;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into pub from public.publications where id = p_publication;
  if not found or pub.type <> 'final' then raise exception 'L''attribution se fait sur le classement final publié.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_resultats, '[]'::jsonb)) loop
    v_membre := null;
    if nullif(r->>'beneficiaire_matricule', '') is not null then
      select id, hors_concours into v_membre, v_hc from public.membres where matricule = (r->>'beneficiaire_matricule')::int;
      if v_membre is null then raise exception 'Bénéficiaire DFMM-% introuvable.', r->>'beneficiaire_matricule'; end if;
      if v_hc then raise exception 'DFMM-% est hors concours : il ne reçoit aucun lot.', r->>'beneficiaire_matricule'; end if;
      if v_membre = any(v_vus) then raise exception 'Un joueur ne reçoit qu''un lot au plus (DFMM-%).', r->>'beneficiaire_matricule'; end if;
      v_vus := v_vus || v_membre;
    end if;
    update public.lots set beneficiaire_id = v_membre, statut_attribution = r->>'statut', explication = r->>'explication',
           publication_id = pub.id, attribue_le = clock_timestamp(), remis_le = case when beneficiaire_id is distinct from v_membre then null else remis_le end
     where saison_id = pub.saison_id and categorie = r->>'categorie' and confirme;
    if found then n := n + 1; end if;
  end loop;
  select nom into v_nom from public.saisons where id = pub.saison_id;
  insert into public.journal (type, objet, decision) values ('Lots', v_nom, 'Attribution enregistrée sur le classement final : ' || n || ' lot(s) confirmé(s), ' || coalesce(array_length(v_vus, 1), 0) || ' bénéficiaire(s)');
  return n;
end $$;

commit;
