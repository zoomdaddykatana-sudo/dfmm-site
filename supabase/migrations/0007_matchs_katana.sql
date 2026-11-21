-- =====================================================================
-- LEAGUE UV — DFMM · Lot 3A « matchs de Katana » · migration 0007
-- Saisons, matchs, lignes de joueurs, captures (stockage privé) et registre des événements
-- (cahier, sections 4 et 5). À exécuter UNE fois dans Supabase. Ne supprime rien : ajoute
-- une colonne aux saisons (fin confirmée), 4 tables, un espace de stockage privé « captures » et des fonctions.
-- Les contrôles du cahier (16 joueurs, écart 1, 50 %, délai…) sont faits par le site (js/regles.js)
-- avant la validation ; la base garde les règles qui ne doivent jamais être contournées.
-- =====================================================================
begin;

-- ---------- Saisons : la date de fin officielle est souvent annoncée tard par le jeu ----------
alter table public.saisons add column fin_confirmee boolean not null default false;

-- ---------- Matchs ----------
create table public.matchs (
  id                bigint generated always as identity primary key,
  saison_id         bigint not null references public.saisons(id),
  type              text not null default 'katana' check (type in ('katana', 'libre')),
  demarrage         boolean not null default false,   -- « saisie de démarrage » : sans délai de 10 min
  carte             text,
  mode              text,
  fin               timestamptz,                       -- heure de fin lue sur la capture
  statut            text not null default 'brouillon'
                    check (statut in ('brouillon', 'valide', 'attente', 'refuse', 'annule')),
  motif             text,
  notes             text,
  valide_le         timestamptz,
  attente_decide_le timestamptz,                       -- match en attente tranché : classement suivant si après la coupure
  cree_le           timestamptz not null default now(),
  modifie_le        timestamptz not null default now()
);
create index matchs_saison on public.matchs (saison_id, statut);

-- ---------- Une ligne par joueur lu sur la capture ----------
create table public.match_lignes (
  id           bigint generated always as identity primary key,
  match_id     bigint not null references public.matchs(id) on delete cascade,
  rang         integer not null check (rang > 0),
  faction      text check (faction in ('HAAVK', 'GTI')),
  pseudo       text not null,                          -- tel que lu sur la capture
  compte_id    bigint references public.comptes_jeu(id),
  membre_id    bigint references public.membres(id),
  resolution   text not null default 'non_inscrit'
               check (resolution in ('auto', 'manuel', 'a_identifier', 'non_inscrit', 'non_inscrit_confirme')),
  identifie_le timestamptz,                            -- ligne identifiée après la validation : classements suivants
  score numeric check (score >= 0), elim numeric check (elim >= 0), morts numeric check (morts >= 0),
  assist numeric check (assist >= 0), med numeric check (med >= 0), ing numeric check (ing >= 0),
  obj numeric check (obj >= 0), tac numeric check (tac >= 0),
  unique (match_id, rang),
  check ((compte_id is null) = (membre_id is null))
);
create index match_lignes_membre on public.match_lignes (membre_id);

-- ---------- Captures : l'heure d'envoi est celle du serveur ----------
create table public.captures (
  id          bigint generated always as identity primary key,
  match_id    bigint not null references public.matchs(id),
  chemin      text not null unique,                    -- fichier dans l'espace de stockage « captures »
  envoyee_le  timestamptz not null default clock_timestamp(),
  envoyee_par uuid,
  statut      text not null default 'recue' check (statut in ('recue', 'retenue', 'refusee', 'ecartee')),
  motif       text
);

-- ---------- Registre (section 5) : un événement par ligne, jamais modifié ----------
create table public.registre (
  id        bigint generated always as identity primary key,
  date      timestamptz not null default clock_timestamp(),
  match_id  bigint references public.matchs(id),
  type      text not null check (type in ('match_declare', 'capture_recue', 'capture_acceptee', 'capture_refusee',
                                          'match_en_attente', 'litige_ouvert', 'decision', 'sanction')),
  membre_id bigint references public.membres(id),
  auteur    uuid default auth.uid(),
  detail    text
);
create index registre_match on public.registre (match_id, date);

-- ---------- Espace de stockage privé des captures de match ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('captures', 'captures', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy "captures : lecture administrateur" on storage.objects for select to authenticated
  using (bucket_id = 'captures' and (select public.est_admin()));
create policy "captures : dépôt administrateur" on storage.objects for insert to authenticated
  with check (bucket_id = 'captures' and (select public.est_admin()));

-- Heure d'envoi et auteur fixés par le serveur, jamais par le téléphone ; événement « capture reçue ».
create function public.captures_avant_ajout() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare s text;
begin
  select statut into s from public.matchs where id = new.match_id;
  if s is null then raise exception 'Match introuvable.'; end if;
  if s not in ('brouillon', 'attente') then raise exception 'Ce match est déjà tranché : repassez-le en brouillon pour ajouter une capture.'; end if;
  new.envoyee_le := clock_timestamp();
  new.envoyee_par := (select auth.uid());
  new.statut := 'recue';
  new.motif := null;
  return new;
end $$;
create trigger captures_avant_ajout before insert on public.captures
for each row execute function public.captures_avant_ajout();

create function public.captures_apres_ajout() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.registre (match_id, type, detail) values (new.match_id, 'capture_recue', 'Capture reçue');
  return null;
end $$;
create trigger captures_apres_ajout after insert on public.captures
for each row execute function public.captures_apres_ajout();

create function public.registre_sans_modification() returns trigger
language plpgsql set search_path = ''
as $$ begin raise exception 'Le registre ne se modifie pas.'; end $$;
create trigger registre_sans_modification before update or delete on public.registre
for each row execute function public.registre_sans_modification();

-- ---------- Saison active : une seule à la fois ----------
create function public.activer_saison(p_saison bigint) returns void
language plpgsql security definer set search_path = ''
as $$
declare n text;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select nom into n from public.saisons where id = p_saison;
  if n is null then raise exception 'Saison introuvable.'; end if;
  update public.saisons set active = false where active and id <> p_saison;
  update public.saisons set active = true, statut = case when statut = 'preparation' then 'en_cours' else statut end where id = p_saison;
  insert into public.journal (type, objet, decision) values ('Saison', n, 'Saison rendue active');
end $$;

-- ---------- Enregistrer un match (brouillon ou en attente) et ses lignes ----------
-- p : {id?, saison_id, carte, mode, fin, notes, lignes:[{faction, pseudo, compte_id, resolution, score…tac}]}
create function public.enregistrer_match(p jsonb) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint := nullif(p->>'id', '')::bigint; m public.matchs%rowtype; l jsonb; i int := 0;
        v_membre bigint; v_res text; v_phase boolean;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  if v_id is null then
    select (valeur = 'true'::jsonb) into v_phase from public.parametres where cle = 'phase_demarrage';
    if not exists (select 1 from public.saisons where id = (p->>'saison_id')::bigint) then raise exception 'Choisissez une saison.'; end if;
    insert into public.matchs (saison_id, type, demarrage, carte, mode, fin, notes)
    values ((p->>'saison_id')::bigint, 'katana', coalesce(v_phase, false), nullif(trim(p->>'carte'), ''), nullif(trim(p->>'mode'), ''),
            nullif(p->>'fin', '')::timestamptz, nullif(trim(p->>'notes'), ''))
    returning id into v_id;
    insert into public.registre (match_id, type, detail)
    values (v_id, 'match_declare', 'Match de Katana enregistré' || case when coalesce(v_phase, false) then ' (saisie de démarrage)' else '' end);
  else
    select * into m from public.matchs where id = v_id for update;
    if not found then raise exception 'Match introuvable.'; end if;
    if m.statut not in ('brouillon', 'attente') then raise exception 'Ce match est déjà tranché : repassez-le en brouillon pour le modifier.'; end if;
    update public.matchs set saison_id = (p->>'saison_id')::bigint, carte = nullif(trim(p->>'carte'), ''), mode = nullif(trim(p->>'mode'), ''),
           fin = nullif(p->>'fin', '')::timestamptz, notes = nullif(trim(p->>'notes'), ''), modifie_le = now()
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

-- ---------- Trancher un match : valider, mettre en attente, refuser, annuler, repasser en brouillon ----------
create function public.decider_match(p_match bigint, p_decision text, p_motif text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare m public.matchs%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), ''); n int; v_lib text;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into m from public.matchs where id = p_match for update;
  if not found then raise exception 'Match introuvable.'; end if;
  if p_decision not in ('valider', 'attente', 'refuser', 'annuler', 'brouillon') then raise exception 'Décision inconnue.'; end if;
  if p_decision <> 'valider' and v_motif is null then raise exception 'Le motif est obligatoire.'; end if;

  if p_decision = 'valider' then
    if m.statut not in ('brouillon', 'attente') then raise exception 'Seul un brouillon ou un match en attente se valide.'; end if;
    if m.fin is null then raise exception 'Heure de fin du match manquante.'; end if;
    select count(*) into n from public.captures where match_id = m.id and statut in ('recue', 'retenue');
    if n = 0 then raise exception 'Ajoutez au moins une capture avant de valider.'; end if;
    select count(*) into n from public.match_lignes where match_id = m.id;
    if n = 0 then raise exception 'Aucun joueur saisi.'; end if;
    update public.matchs set statut = 'valide', valide_le = clock_timestamp(), motif = null, modifie_le = now(),
           attente_decide_le = case when m.statut = 'attente' then clock_timestamp() else attente_decide_le end
    where id = m.id;
    insert into public.registre (match_id, type, detail)
      select m.id, 'capture_acceptee', 'Capture retenue' from public.captures where match_id = m.id and statut = 'recue';
    update public.captures set statut = 'retenue' where match_id = m.id and statut = 'recue';
    v_lib := 'Match validé (' || n || ' joueurs)';
  elsif p_decision = 'attente' then
    if m.statut <> 'brouillon' then raise exception 'Seul un brouillon passe en attente.'; end if;
    update public.matchs set statut = 'attente', motif = v_motif, modifie_le = now() where id = m.id;
    insert into public.registre (match_id, type, detail) values (m.id, 'match_en_attente', v_motif);
    v_lib := 'Match mis en attente';
  elsif p_decision = 'refuser' then
    if m.statut not in ('brouillon', 'attente') then raise exception 'Seul un brouillon ou un match en attente se refuse.'; end if;
    update public.matchs set statut = 'refuse', motif = v_motif, modifie_le = now(),
           attente_decide_le = case when m.statut = 'attente' then clock_timestamp() else attente_decide_le end
    where id = m.id;
    insert into public.registre (match_id, type, detail)
      select m.id, 'capture_refusee', v_motif from public.captures where match_id = m.id and statut in ('recue', 'retenue');
    update public.captures set statut = 'refusee', motif = v_motif where match_id = m.id and statut in ('recue', 'retenue');
    v_lib := 'Match refusé (gardé, non compté)';
  elsif p_decision = 'annuler' then
    if m.statut = 'annule' then raise exception 'Ce match est déjà annulé.'; end if;
    update public.matchs set statut = 'annule', motif = v_motif, modifie_le = now() where id = m.id;
    v_lib := 'Match annulé pour tous';
  else
    if m.statut not in ('valide', 'refuse', 'annule', 'attente') then raise exception 'Ce match est déjà un brouillon.'; end if;
    update public.matchs set statut = 'brouillon', valide_le = null, motif = v_motif, modifie_le = now() where id = m.id;
    update public.captures set statut = 'recue', motif = null where match_id = m.id and statut in ('retenue', 'refusee');
    v_lib := 'Match repassé en brouillon (' || m.statut || ' avant)';
  end if;
  insert into public.registre (match_id, type, detail) values (m.id, 'decision', v_lib || coalesce(' — ' || v_motif, ''));
  insert into public.journal (type, objet, decision, motif) values ('Match', 'M-' || m.id, v_lib, v_motif);
end $$;

-- ---------- Identifier une ligne « à identifier » après la validation (compte pour les classements suivants) ----------
create function public.identifier_ligne(p_ligne bigint, p_compte bigint) returns void
language plpgsql security definer set search_path = ''
as $$
declare l public.match_lignes%rowtype; s text; v_membre bigint; v_mat integer;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into l from public.match_lignes where id = p_ligne for update;
  if not found then raise exception 'Ligne introuvable.'; end if;
  select statut into s from public.matchs where id = l.match_id;
  if s <> 'valide' then raise exception 'Pour un match non validé, corrigez la ligne dans le brouillon.'; end if;
  if l.resolution <> 'a_identifier' then raise exception 'Cette ligne n''est pas à identifier.'; end if;
  if p_compte is null then
    update public.match_lignes set resolution = 'non_inscrit_confirme', identifie_le = clock_timestamp() where id = l.id;
  else
    select c.membre_id, m.matricule into v_membre, v_mat from public.comptes_jeu c join public.membres m on m.id = c.membre_id where c.id = p_compte;
    if v_membre is null then raise exception 'Compte de jeu introuvable.'; end if;
    if exists (select 1 from public.match_lignes where match_id = l.match_id and membre_id = v_membre) then
      raise exception 'Ce joueur est déjà sur une autre ligne de ce match.';
    end if;
    update public.match_lignes set compte_id = p_compte, membre_id = v_membre, resolution = 'manuel', identifie_le = clock_timestamp() where id = l.id;
  end if;
  insert into public.registre (match_id, type, membre_id, detail)
  values (l.match_id, 'decision', v_membre, 'Ligne « ' || l.pseudo || ' » identifiée après la validation : '
          || coalesce('DFMM-' || v_mat, 'joueur non inscrit') || ' (classements suivants)');
end $$;

-- =====================================================================
-- Règles d'accès : administrateur seulement (le public ne voit que les classements publiés)
-- =====================================================================
alter table public.matchs       enable row level security;
alter table public.match_lignes enable row level security;
alter table public.captures     enable row level security;
alter table public.registre     enable row level security;
revoke all on public.matchs, public.match_lignes, public.captures, public.registre from anon, authenticated;
grant select on public.matchs, public.match_lignes, public.registre to authenticated;
grant select, insert on public.captures to authenticated;
create policy "admin lit" on public.matchs       for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.match_lignes for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.registre     for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.captures     for select to authenticated using ((select public.est_admin()));
create policy "admin ajoute" on public.captures  for insert to authenticated with check ((select public.est_admin()));
grant select, insert, update, delete on public.matchs, public.match_lignes, public.captures, public.registre to service_role;

revoke all on function public.activer_saison(bigint), public.enregistrer_match(jsonb),
                       public.decider_match(bigint, text, text), public.identifier_ligne(bigint, bigint) from public, anon;
grant execute on function public.activer_saison(bigint), public.enregistrer_match(jsonb),
                          public.decider_match(bigint, text, text), public.identifier_ligne(bigint, bigint) to authenticated;
revoke all on function public.captures_avant_ajout(), public.captures_apres_ajout(), public.registre_sans_modification() from public, anon, authenticated;

commit;
