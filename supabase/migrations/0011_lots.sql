-- =====================================================================
-- LEAGUE UV — DFMM · Titres et lots · migration 0011
-- Cahier, section 8 : un lot au plus par joueur, dans l'ordre de priorité des 11 catégories ;
-- redistribution au joueur suivant sans lot ; co-lauréats sans lot ; lot non attribué si personne
-- n'est éligible. Les lots ne sont jamais publiés tant que sponsors et moyens ne sont pas confirmés :
-- cette table est réservée à l'administrateur. L'attribution s'enregistre à partir du classement
-- final publié (figé). À exécuter UNE fois dans Supabase. Ne supprime rien : ajoute une table et 2 fonctions.
-- =====================================================================
begin;

create table public.lots (
  id                 bigint generated always as identity primary key,
  saison_id          bigint not null references public.saisons(id),
  categorie          text not null check (categorie in ('most_elim', 'most_med', 'most_ing', 'most_obj', 'most_tac', 'best_surv',
                                                        'best_elim', 'best_med', 'best_ing', 'best_obj', 'best_tac')),
  description        text,                       -- ce que contient le lot (sponsor, montant…)
  confirme           boolean not null default false,
  beneficiaire_id    bigint references public.membres(id),
  statut_attribution text,
  explication        text,
  publication_id     bigint references public.publications(id),
  attribue_le        timestamptz,
  remis_le           timestamptz,
  unique (saison_id, categorie)
);

-- Enregistrer l'attribution calculée sur le classement final publié.
-- p_resultats : [{categorie, beneficiaire_matricule (nombre ou null), statut, explication}]
create function public.enregistrer_attribution(p_publication bigint, p_resultats jsonb) returns int
language plpgsql security definer set search_path = ''
as $$
declare pub public.publications%rowtype; r jsonb; v_membre bigint; n int := 0; v_vus bigint[] := '{}'; v_nom text;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into pub from public.publications where id = p_publication;
  if not found or pub.type <> 'final' then raise exception 'L''attribution se fait sur le classement final publié.'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_resultats, '[]'::jsonb)) loop
    v_membre := null;
    if nullif(r->>'beneficiaire_matricule', '') is not null then
      select id into v_membre from public.membres where matricule = (r->>'beneficiaire_matricule')::int;
      if v_membre is null then raise exception 'Bénéficiaire DFMM-% introuvable.', r->>'beneficiaire_matricule'; end if;
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

create function public.marquer_lot_remis(p_lot bigint) returns void
language plpgsql security definer set search_path = ''
as $$
declare l public.lots%rowtype; v_mat integer;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into l from public.lots where id = p_lot for update;
  if not found then raise exception 'Lot introuvable.'; end if;
  if l.beneficiaire_id is null then raise exception 'Ce lot n''a pas de bénéficiaire.'; end if;
  update public.lots set remis_le = clock_timestamp() where id = l.id;
  select matricule into v_mat from public.membres where id = l.beneficiaire_id;
  insert into public.journal (type, objet, decision) values ('Lots', 'DFMM-' || v_mat, 'Lot remis (' || l.categorie || ')');
end $$;

-- =====================================================================
-- Règles d'accès : administrateur seulement (lots jamais publiés)
-- =====================================================================
alter table public.lots enable row level security;
revoke all on public.lots from anon, authenticated;
grant select, insert, update, delete on public.lots to authenticated;
create policy "admin gère" on public.lots for all to authenticated using ((select public.est_admin())) with check ((select public.est_admin()));
grant select, insert, update, delete on public.lots to service_role;

revoke all on function public.enregistrer_attribution(bigint, jsonb), public.marquer_lot_remis(bigint) from public, anon;
grant execute on function public.enregistrer_attribution(bigint, jsonb), public.marquer_lot_remis(bigint) to authenticated;

commit;
