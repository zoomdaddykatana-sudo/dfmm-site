-- =====================================================================
-- LEAGUE UV — DFMM · Lot « socle » · migration 0001
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Crée les tables de base, les règles d'accès (RLS) et les paramètres
-- de la section 10 du cahier. Aucune donnée personnelle ici.
-- =====================================================================
begin;

-- ---------- Administrateur ----------
create table public.admins (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  ajoute_le timestamptz not null default now()
);

create function public.est_admin() returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admins a where a.user_id = (select auth.uid())) $$;

-- ---------- Paramètres réglables (section 10 + réglages du site) ----------
create table public.parametres (
  cle        text primary key check (cle ~ '^[a-z0-9_]+$'),
  valeur     jsonb not null,
  type       text not null check (type in ('entier','decimal','heure','jour','booleen','texte')),
  libelle    text not null,
  section    text not null,
  ordre      integer not null default 0,
  modifie_le timestamptz not null default now(),
  modifie_par uuid
);

create table public.parametres_historique (
  id              bigint generated always as identity primary key,
  cle             text not null references public.parametres(cle),
  ancienne_valeur jsonb,
  nouvelle_valeur jsonb,
  modifie_le      timestamptz not null default now(),
  modifie_par     uuid
);

-- Contrôle du type de la valeur et historique de chaque changement.
create function public.parametres_avant_maj() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.cle is distinct from old.cle or new.type is distinct from old.type then
    raise exception 'Seule la valeur d''un paramètre peut être modifiée.';
  end if;
  if new.type = 'entier' and not (jsonb_typeof(new.valeur) = 'number'
       and (new.valeur #>> '{}')::numeric = trunc((new.valeur #>> '{}')::numeric)
       and (new.valeur #>> '{}')::numeric >= 0) then
    raise exception 'Valeur invalide pour % : nombre entier positif attendu.', new.cle;
  elsif new.type = 'decimal' and not (jsonb_typeof(new.valeur) = 'number' and (new.valeur #>> '{}')::numeric >= 0) then
    raise exception 'Valeur invalide pour % : nombre positif attendu.', new.cle;
  elsif new.type = 'heure' and not (jsonb_typeof(new.valeur) = 'string' and (new.valeur #>> '{}') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
    raise exception 'Valeur invalide pour % : heure HH:MM attendue.', new.cle;
  elsif new.type = 'jour' and not (jsonb_typeof(new.valeur) = 'number' and (new.valeur #>> '{}') in ('0','1','2','3','4','5','6')) then
    raise exception 'Valeur invalide pour % : jour de 0 (dimanche) à 6 (samedi) attendu.', new.cle;
  elsif new.type = 'booleen' and jsonb_typeof(new.valeur) <> 'boolean' then
    raise exception 'Valeur invalide pour % : oui ou non attendu.', new.cle;
  elsif new.type = 'texte' and jsonb_typeof(new.valeur) <> 'string' then
    raise exception 'Valeur invalide pour % : texte attendu.', new.cle;
  end if;
  new.modifie_le := now();
  new.modifie_par := (select auth.uid());
  if new.valeur is distinct from old.valeur then
    insert into public.parametres_historique (cle, ancienne_valeur, nouvelle_valeur, modifie_par)
    values (old.cle, old.valeur, new.valeur, new.modifie_par);
  end if;
  return new;
end $$;

create trigger parametres_avant_maj before update on public.parametres
for each row execute function public.parametres_avant_maj();

insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('participants_min',              '16',      'entier',  'Participants minimum par match',                          'Matchs', 1),
  ('ecart_factions_max',            '1',       'entier',  'Écart maximum entre HAAVK et GTI (joueurs)',              'Matchs', 2),
  ('seuil_membres_pct',             '50',      'entier',  'Seuil de membres confirmés (%, arrondi vers le bas)',     'Matchs', 3),
  ('delai_capture_min',             '10',      'entier',  'Délai d''envoi des captures après l''heure de fin (min)', 'Matchs', 4),
  ('delai_declaration_h',           '2',       'entier',  'Déclaration d''un match libre, au moins (h avant)',       'Matchs', 5),
  ('plage_fin_h',                   '1',       'entier',  'Plage de l''heure de fin après l''heure annoncée (h)',     'Matchs', 6),
  ('coupure_jour',                  '6',       'jour',    'Jour de la coupure',                                      'Classements', 1),
  ('coupure_heure',                 '"16:00"', 'heure',   'Heure de la coupure',                                     'Classements', 2),
  ('publication_jour',              '0',       'jour',    'Jour de publication du provisoire',                       'Classements', 3),
  ('periodicite_jours',             '14',      'entier',  'Jours entre deux classements provisoires',                'Classements', 4),
  ('classement_final_jours',        '7',       'entier',  'Classement final, au plus tard (jours après la fin de saison)', 'Classements', 5),
  ('reclamation_h',                 '48',      'entier',  'Réclamation sur un classement publié (h)',                'Classements', 6),
  ('comptes_max',                   '2',       'entier',  'Comptes de jeu par matricule',                            'Comptes', 1),
  ('comptes_actifs_max',            '1',       'entier',  'Comptes actifs en même temps',                            'Comptes', 2),
  ('delai_changement_compte_jours', '7',       'entier',  'Délai entre deux changements de compte actif (jours)',    'Comptes', 3),
  ('convocation_h',                 '12',      'entier',  'Confirmation d''une convocation (h)',                     'Litiges', 1),
  ('attente_h',                     '48',      'entier',  'Traitement d''un match en attente (h après la fin)',      'Litiges', 2),
  ('recours_h',                     '48',      'entier',  'Recours contre une sanction (h après la décision)',       'Sanctions', 1),
  ('suspension_max_jours',          '14',      'entier',  'Durée maximum d''une suspension (jours)',                 'Sanctions', 2),
  ('alerte_facteur',                '2.5',     'decimal', 'Alerte de performance : fois la moyenne du joueur',       'Alertes', 1),
  ('alerte_ecart_elim',             '10',      'entier',  'Alerte de performance : éliminations en plus, au moins',  'Alertes', 2),
  ('alerte_ecart_score',            '1000',    'entier',  'Alerte de performance : points de score en plus, au moins', 'Alertes', 3),
  ('version_test',                  'true',    'booleen', 'Site en version de test',                                 'Site', 1),
  ('inscriptions_ouvertes',         'false',   'booleen', 'Inscriptions ouvertes',                                   'Site', 2),
  ('matchs_libres_ouverts',         'false',   'booleen', 'Matchs libres ouverts',                                   'Site', 3);

-- ---------- Saisons ----------
create table public.saisons (
  id                 bigint generated always as identity primary key,
  nom                text not null,
  debut              date not null,
  fin                date not null check (fin > debut),
  premier_provisoire date,
  statut             text not null default 'preparation'
                     check (statut in ('preparation','en_cours','cloture','terminee')),
  active             boolean not null default false,
  cree_le            timestamptz not null default now()
);
create unique index saisons_une_active on public.saisons (active) where active;

-- ---------- Membres (données personnelles ajoutées au lot « membres ») ----------
-- Matricules DFMM-1 à DFMM-25 importés à la main ; les nouveaux commencent à DFMM-26.
create sequence public.matricule_seq start with 26 minvalue 1;

create table public.membres (
  id               bigint generated always as identity primary key,
  user_id          uuid unique references auth.users(id) on delete set null,
  matricule        integer unique check (matricule > 0),
  nom_gamer        text not null,
  statut           text not null default 'en_attente'
                   check (statut in ('en_attente','actif','refuse','retire','exclu')),
  date_approbation timestamptz,
  cree_le          timestamptz not null default now()
);

create function public.mes_membres() returns setof bigint
language sql stable security definer set search_path = ''
as $$ select m.id from public.membres m where m.user_id = (select auth.uid()) $$;

create table public.periodes (
  id        bigint generated always as identity primary key,
  membre_id bigint not null references public.membres(id) on delete restrict,
  debut     timestamptz not null,
  fin       timestamptz check (fin is null or fin > debut)
);

create table public.comptes_jeu (
  id        bigint generated always as identity primary key,
  membre_id bigint not null references public.membres(id) on delete restrict,
  uid       text not null unique,
  pseudo    text not null,
  statut    text not null default 'en_pause' check (statut in ('actif','en_pause','remplace')),
  ajoute_le timestamptz not null default now()
);

create table public.pseudos_historique (
  id        bigint generated always as identity primary key,
  compte_id bigint not null references public.comptes_jeu(id) on delete restrict,
  pseudo    text not null,
  debut     timestamptz not null default now(),
  fin       timestamptz
);

-- ---------- Journal des décisions (administrateur seulement) ----------
create table public.journal (
  id       bigint generated always as identity primary key,
  date     timestamptz not null default now(),
  type     text not null,
  objet    text,
  decision text not null,
  motif    text,
  auteur   uuid default auth.uid()
);

-- ---------- Classements publiés (publics, figés) ----------
create table public.publications (
  id        bigint generated always as identity primary key,
  saison_id bigint not null references public.saisons(id),
  type      text not null check (type in ('provisoire','final')),
  numero    integer,
  publie_le timestamptz not null default now(),
  coupure   timestamptz not null,
  contenu   jsonb not null
);

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.admins                enable row level security;
alter table public.parametres            enable row level security;
alter table public.parametres_historique enable row level security;
alter table public.saisons               enable row level security;
alter table public.membres               enable row level security;
alter table public.periodes              enable row level security;
alter table public.comptes_jeu           enable row level security;
alter table public.pseudos_historique    enable row level security;
alter table public.journal               enable row level security;
alter table public.publications          enable row level security;

-- Droits de base : rien pour personne, puis seulement le nécessaire.
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.est_admin() to anon, authenticated;
grant execute on function public.mes_membres() to authenticated;

grant select on public.parametres, public.saisons, public.publications to anon, authenticated;
grant select on public.admins, public.parametres_historique, public.membres, public.periodes,
                public.comptes_jeu, public.pseudos_historique, public.journal to authenticated;
grant update (valeur) on public.parametres to authenticated;
grant insert, update, delete on public.saisons, public.membres, public.periodes, public.comptes_jeu,
                public.pseudos_historique, public.journal, public.publications to authenticated;

-- Public (visiteurs, membres, administrateur) : lecture
create policy "lecture publique" on public.parametres   for select to anon, authenticated using (true);
create policy "lecture publique" on public.saisons      for select to anon, authenticated using (true);
create policy "lecture publique" on public.publications for select to anon, authenticated using (true);

-- Administrateur : écriture
create policy "admin modifie" on public.parametres for update to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "admin gère" on public.saisons      for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "admin gère" on public.publications for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "admin gère" on public.journal      for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "admin lit" on public.parametres_historique for select to authenticated
  using ((select public.est_admin()));

-- La liste des administrateurs : chacun voit seulement sa propre ligne. Aucune écriture par le site.
create policy "voir sa ligne" on public.admins for select to authenticated
  using (user_id = (select auth.uid()));

-- Membres : l'administrateur voit et gère tout ; un membre ne voit que ses propres lignes.
create policy "admin gère" on public.membres for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre se voit" on public.membres for select to authenticated
  using (user_id = (select auth.uid()));

create policy "admin gère" on public.periodes for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siennes" on public.periodes for select to authenticated
  using (membre_id in (select public.mes_membres()));

create policy "admin gère" on public.comptes_jeu for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siens" on public.comptes_jeu for select to authenticated
  using (membre_id in (select public.mes_membres()));

create policy "admin gère" on public.pseudos_historique for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siens" on public.pseudos_historique for select to authenticated
  using (compte_id in (select c.id from public.comptes_jeu c where c.membre_id in (select public.mes_membres())));

commit;
