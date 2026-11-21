-- =====================================================================
-- LEAGUE UV — DFMM · Lot 2A « inscription et approbation » · migration 0002
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute des colonnes, des tables et des fonctions.
-- =====================================================================
begin;

-- ---------- Fiche membre : empreintes et décision ----------
-- Empreintes codées (SHA-256) de l'e-mail et du lien Facebook : repèrent une
-- réinscription, même après effacement des données (décision Q10).
alter table public.membres
  add column empreinte_email    text unique,
  add column empreinte_facebook text unique,
  add column decision           jsonb,
  add column donnees_effacees   boolean not null default false;

alter table public.membres drop constraint membres_statut_check;
alter table public.membres add constraint membres_statut_check
  check (statut in ('en_attente','precisions','actif','refuse','retire','exclu'));

-- ---------- Données personnelles (administrateur et membre concerné seulement) ----------
create table public.membres_prives (
  membre_id      bigint primary key references public.membres(id) on delete restrict,
  nom_reel       text,
  email          text,
  date_naissance date,
  genre          text check (genre in ('Homme','Femme','Préfère ne pas le dire')),
  facebook       text,
  clan           text,
  residence      text check (residence in ('Madagascar','Étranger')),
  province       text,
  zone           text,
  pays           text,
  comprend_mg    boolean,
  parle_mg       boolean,
  origine_mg     boolean not null default false,
  acceptations   jsonb not null default '{}'::jsonb,
  capture_profil text,
  modifie_le     timestamptz not null default now()
);

-- ---------- Périodes actives des comptes de jeu ----------
create table public.comptes_periodes (
  id        bigint generated always as identity primary key,
  compte_id bigint not null references public.comptes_jeu(id) on delete restrict,
  debut     timestamptz not null,
  fin       timestamptz check (fin is null or fin > debut)
);

-- ---------- Anciens matricules (DFMM-1 à DFMM-25), importés par fichier ----------
create table public.matricules_anciens (
  matricule        integer primary key check (matricule > 0),
  nom_gamer        text,
  date_approbation date not null,
  repris_par       bigint unique references public.membres(id)
);

-- ---------- Capture du profil : stockage privé ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profils', 'profils', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "profils : lecture administrateur" on storage.objects for select to authenticated
  using (bucket_id = 'profils' and (select public.est_admin()));

-- ---------- Création d'une inscription (appelée seulement par la fonction serveur) ----------
create function public.creer_inscription(p jsonb) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint; v_cpt bigint;
begin
  if coalesce(p->>'user_id', '') = '' or coalesce(trim(p->>'nom_gamer'), '') = '' or coalesce(trim(p->>'uid'), '') = ''
     or coalesce(trim(p->>'pseudo'), '') = '' or coalesce(p->>'empreinte_email', '') = '' or coalesce(p->>'empreinte_facebook', '') = '' then
    raise exception 'Inscription incomplète.';
  end if;
  if exists (select 1 from public.membres where empreinte_email = p->>'empreinte_email' or empreinte_facebook = p->>'empreinte_facebook') then
    raise exception 'DOUBLON_INSCRIPTION';
  end if;
  if exists (select 1 from public.comptes_jeu where uid = trim(p->>'uid')) then
    raise exception 'DOUBLON_UID';
  end if;
  insert into public.membres (user_id, nom_gamer, statut, empreinte_email, empreinte_facebook)
  values ((p->>'user_id')::uuid, trim(p->>'nom_gamer'), 'en_attente', p->>'empreinte_email', p->>'empreinte_facebook')
  returning id into v_id;
  insert into public.membres_prives (membre_id, nom_reel, email, date_naissance, genre, facebook, clan, residence,
    province, zone, pays, comprend_mg, parle_mg, origine_mg, acceptations, capture_profil)
  values (v_id, p->>'nom_reel', p->>'email', nullif(p->>'date_naissance', '')::date, p->>'genre', p->>'facebook',
    nullif(p->>'clan', ''), p->>'residence', nullif(p->>'province', ''), nullif(p->>'zone', ''), nullif(p->>'pays', ''),
    (p->>'comprend_mg')::boolean, (p->>'parle_mg')::boolean, coalesce((p->>'origine_mg')::boolean, false),
    coalesce(p->'acceptations', '{}'::jsonb), nullif(p->>'capture_profil', ''));
  insert into public.comptes_jeu (membre_id, uid, pseudo, statut) values (v_id, trim(p->>'uid'), trim(p->>'pseudo'), 'en_pause')
  returning id into v_cpt;
  insert into public.pseudos_historique (compte_id, pseudo, debut) values (v_cpt, trim(p->>'pseudo'), now());
  insert into public.journal (type, objet, decision, auteur)
  values ('Inscription', v_id::text, 'Candidature reçue : ' || trim(p->>'nom_gamer'), (p->>'user_id')::uuid);
  return v_id;
end $$;

-- ---------- Décision sur une inscription (administrateur) ----------
-- Approuver : nouveau matricule (suite à partir de DFMM-26) ou reprise d'un ancien matricule,
-- avec sa date d'approbation d'origine comptée à partir de 0 h (heure de Madagascar).
create function public.decider_inscription(p_membre bigint, p_decision text, p_motif text default null,
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
  insert into public.journal (type, objet, decision, motif)
  values ('Inscription', 'DFMM-' || v_mat, 'Inscription approuvée, matricule DFMM-' || v_mat
          || case when p_matricule_ancien is not null then ' repris (date d''origine conservée)' else ' attribué' end, nullif(trim(coalesce(p_motif, '')), ''));
  return v_mat;
end $$;

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.membres_prives     enable row level security;
alter table public.comptes_periodes   enable row level security;
alter table public.matricules_anciens enable row level security;

revoke all on public.membres_prives, public.comptes_periodes, public.matricules_anciens from anon, authenticated;
grant select, update on public.membres_prives to authenticated;
grant select, insert, update, delete on public.comptes_periodes, public.matricules_anciens to authenticated;

revoke all on function public.creer_inscription(jsonb) from public, anon, authenticated;
grant execute on function public.creer_inscription(jsonb) to service_role;
revoke all on function public.decider_inscription(bigint, text, text, integer) from public, anon;
grant execute on function public.decider_inscription(bigint, text, text, integer) to authenticated;

create policy "admin gère" on public.membres_prives for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siennes" on public.membres_prives for select to authenticated
  using (membre_id in (select public.mes_membres()));

create policy "admin gère" on public.comptes_periodes for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siennes" on public.comptes_periodes for select to authenticated
  using (compte_id in (select c.id from public.comptes_jeu c where c.membre_id in (select public.mes_membres())));

create policy "admin gère" on public.matricules_anciens for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));

commit;
