-- =====================================================================
-- LEAGUE UV — DFMM · Lot 2B « comptes et demandes » · migration 0004
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute une colonne, deux tables et des fonctions.
-- =====================================================================
begin;

alter table public.membres add column dernier_changement_compte timestamptz;

-- ---------- Demandes des membres (le membre ne change jamais lui-même son statut) ----------
create table public.demandes (
  id             bigint generated always as identity primary key,
  membre_id      bigint not null references public.membres(id) on delete restrict,
  type           text not null check (type in ('compte2','compte_actif','retrait','pseudo','effacement')),
  details        jsonb not null default '{}'::jsonb,
  statut         text not null default 'en_attente' check (statut in ('en_attente','precisions','acceptee','refusee','annulee')),
  motif_decision text,
  cree_le        timestamptz not null default clock_timestamp(),
  decide_le      timestamptz
);

-- ---------- Notifications aux membres (pas d'e-mail) ----------
create table public.notifications (
  id        bigint generated always as identity primary key,
  membre_id bigint not null references public.membres(id) on delete restrict,
  texte     text not null,
  lu        boolean not null default false,
  cree_le   timestamptz not null default clock_timestamp()
);

-- ---------- Outils internes (jamais appelés directement par le site) ----------
create function public.lire_param(p_cle text) returns jsonb
language sql stable security definer set search_path = ''
as $$ select valeur from public.parametres where cle = p_cle $$;

create function public.notifier(p_membre bigint, p_texte text) returns void
language sql security definer set search_path = ''
as $$ insert into public.notifications (membre_id, texte) values (p_membre, p_texte) $$;

-- Le membre connecté, s'il est actif ; sinon arrêt avec un message clair.
create function public.mon_membre_actif() returns public.membres
language plpgsql stable security definer set search_path = ''
as $$
declare m public.membres%rowtype;
begin
  select * into m from public.membres where user_id = (select auth.uid());
  if not found then raise exception 'Aucune fiche membre liée à ce compte.'; end if;
  if m.statut <> 'actif' then raise exception 'Cette démarche est réservée aux membres actifs.'; end if;
  return m;
end $$;

-- Rend un compte actif ; les comptes actifs en trop passent « en pause » (limite réglable).
create function public.activer_compte(p_membre bigint, p_compte bigint) returns void
language plpgsql security definer set search_path = ''
as $$
declare c public.comptes_jeu%rowtype; v_max int;
begin
  select * into c from public.comptes_jeu where id = p_compte and membre_id = p_membre for update;
  if not found then raise exception 'Ce compte n''appartient pas à ce membre.'; end if;
  if c.statut = 'remplace' then raise exception 'Un compte remplacé ne peut plus être activé.'; end if;
  if c.statut = 'actif' then return; end if;
  v_max := (public.lire_param('comptes_actifs_max') #>> '{}')::int;
  if (select count(*) from public.comptes_jeu where membre_id = p_membre and statut = 'actif') >= v_max then
    update public.comptes_periodes set fin = clock_timestamp()
     where fin is null and compte_id in (select id from public.comptes_jeu where membre_id = p_membre and statut = 'actif');
    update public.comptes_jeu set statut = 'en_pause' where membre_id = p_membre and statut = 'actif';
  end if;
  update public.comptes_jeu set statut = 'actif' where id = p_compte;
  insert into public.comptes_periodes (compte_id, debut) values (p_compte, clock_timestamp());
end $$;

-- Remplace le pseudo d'un compte et garde l'ancien dans l'historique (avec les dates).
create function public.changer_pseudo(p_compte bigint, p_pseudo text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_actuel text;
begin
  select pseudo into v_actuel from public.comptes_jeu where id = p_compte for update;
  if not found then raise exception 'Compte introuvable.'; end if;
  if v_actuel = p_pseudo then return false; end if;
  update public.pseudos_historique set fin = clock_timestamp() where compte_id = p_compte and fin is null;
  insert into public.pseudos_historique (compte_id, pseudo, debut) values (p_compte, p_pseudo, clock_timestamp());
  update public.comptes_jeu set pseudo = p_pseudo where id = p_compte;
  return true;
end $$;

-- Effets d'un retrait : période fermée, comptes en pause, autres demandes annulées.
create function public.appliquer_retrait(p_membre bigint, p_motif text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.membres set statut = 'retire' where id = p_membre;
  update public.periodes set fin = clock_timestamp() where membre_id = p_membre and fin is null;
  update public.comptes_periodes set fin = clock_timestamp()
   where fin is null and compte_id in (select id from public.comptes_jeu where membre_id = p_membre);
  update public.comptes_jeu set statut = 'en_pause' where membre_id = p_membre and statut = 'actif';
  update public.demandes set statut = 'annulee', decide_le = clock_timestamp(), motif_decision = 'Annulée par le retrait'
   where membre_id = p_membre and statut in ('en_attente', 'precisions') and type <> 'retrait';
  insert into public.journal (type, objet, decision, motif)
  select 'Membre', 'DFMM-' || matricule, 'Retrait du membre', nullif(trim(coalesce(p_motif, '')), '') from public.membres where id = p_membre;
  perform public.notifier(p_membre, 'Votre retrait de la LEAGUE UV est enregistré. Votre matricule, vos statistiques et votre pseudo sont conservés. Vous pouvez demander votre réintégration à Katana à tout moment.');
end $$;

-- =====================================================================
-- Démarches du membre
-- =====================================================================
create function public.demander_compte2(p_pseudo text, p_uid text, p_motif text, p_capture text, p_activer boolean default false)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; v_id bigint; v_max int;
begin
  m := public.mon_membre_actif();
  if coalesce(trim(p_pseudo), '') = '' or coalesce(trim(p_uid), '') = '' or coalesce(trim(p_motif), '') = '' then
    raise exception 'Pseudo, UID et motif sont obligatoires.';
  end if;
  if coalesce(p_capture, '') = '' or p_capture not like ((select auth.uid())::text || '/%') then
    raise exception 'La capture du profil du nouveau compte est obligatoire.';
  end if;
  v_max := (public.lire_param('comptes_max') #>> '{}')::int;
  if (select count(*) from public.comptes_jeu where membre_id = m.id and statut <> 'remplace') >= v_max then
    raise exception 'Vous avez déjà le nombre maximum de comptes (%).', v_max;
  end if;
  if exists (select 1 from public.comptes_jeu where uid = trim(p_uid)) then raise exception 'Cet UID est déjà enregistré.'; end if;
  if exists (select 1 from public.demandes where membre_id = m.id and type = 'compte2' and statut in ('en_attente', 'precisions')) then
    raise exception 'Une demande d''ajout de compte est déjà en cours.';
  end if;
  insert into public.demandes (membre_id, type, details)
  values (m.id, 'compte2', jsonb_build_object('pseudo', trim(p_pseudo), 'uid', trim(p_uid), 'motif', trim(p_motif),
                                              'capture', p_capture, 'activer', coalesce(p_activer, false)))
  returning id into v_id;
  insert into public.journal (type, objet, decision) values ('Demande', 'DFMM-' || m.matricule, 'Demande d''ajout d''un 2e compte reçue');
  return v_id;
end $$;

create function public.demander_compte_actif(p_compte bigint, p_motif text) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; c public.comptes_jeu%rowtype; v_id bigint; v_jours int; v_possible timestamptz;
begin
  m := public.mon_membre_actif();
  if coalesce(trim(p_motif), '') = '' then raise exception 'Le motif est obligatoire.'; end if;
  select * into c from public.comptes_jeu where id = p_compte and membre_id = m.id;
  if not found then raise exception 'Ce compte n''est pas à vous.'; end if;
  if c.statut <> 'en_pause' then raise exception 'Choisissez un compte en pause.'; end if;
  v_jours := (public.lire_param('delai_changement_compte_jours') #>> '{}')::int;
  v_possible := m.dernier_changement_compte + make_interval(days => v_jours);
  if v_possible is not null and clock_timestamp() < v_possible then
    raise exception 'Prochain changement possible le % (heure de Madagascar).', to_char(v_possible at time zone 'Indian/Antananarivo', 'DD/MM/YYYY à HH24:MI');
  end if;
  if exists (select 1 from public.demandes where membre_id = m.id and type = 'compte_actif' and statut in ('en_attente', 'precisions')) then
    raise exception 'Une demande de changement de compte actif est déjà en cours.';
  end if;
  insert into public.demandes (membre_id, type, details)
  values (m.id, 'compte_actif', jsonb_build_object('compte_id', c.id, 'pseudo', c.pseudo, 'uid', c.uid, 'motif', trim(p_motif)))
  returning id into v_id;
  insert into public.journal (type, objet, decision) values ('Demande', 'DFMM-' || m.matricule, 'Demande de changement de compte actif reçue');
  return v_id;
end $$;

-- Retrait : automatique (aucun litige, match en attente ni sanction n'existe encore dans le site).
create function public.demander_retrait(p_motif text default null) returns text
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype;
begin
  m := public.mon_membre_actif();
  insert into public.demandes (membre_id, type, details, statut, decide_le, motif_decision)
  values (m.id, 'retrait', jsonb_build_object('motif', nullif(trim(coalesce(p_motif, '')), '')), 'acceptee', clock_timestamp(), 'Retrait automatique');
  perform public.appliquer_retrait(m.id, p_motif);
  return 'retire';
end $$;

-- =====================================================================
-- Décisions de l'administrateur
-- =====================================================================
create function public.decider_demande(p_demande bigint, p_decision text, p_motif text default null, p_pseudo_valide text default null)
returns text
language plpgsql security definer set search_path = ''
as $$
declare d public.demandes%rowtype; m public.membres%rowtype; v_cpt bigint; v_max int; v_jours int; v_txt text;
begin
  if not public.est_admin() then raise exception 'Accès réservé à l''administrateur.'; end if;
  select * into d from public.demandes where id = p_demande for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if d.statut not in ('en_attente', 'precisions') then raise exception 'Cette demande a déjà été traitée.'; end if;
  select * into m from public.membres where id = d.membre_id for update;
  v_txt := case d.type when 'compte2' then 'ajout d''un 2e compte' when 'compte_actif' then 'changement de compte actif'
           when 'pseudo' then 'changement de pseudo' when 'retrait' then 'retrait' else d.type end;

  if p_decision in ('refuser', 'precisions') then
    if coalesce(trim(p_motif), '') = '' then raise exception 'Le motif est obligatoire.'; end if;
    update public.demandes set statut = case when p_decision = 'refuser' then 'refusee' else 'precisions' end,
      motif_decision = trim(p_motif), decide_le = clock_timestamp() where id = d.id;
    insert into public.journal (type, objet, decision, motif)
    values ('Demande', 'DFMM-' || m.matricule, case when p_decision = 'refuser' then 'Demande refusée : ' else 'Précisions demandées : ' end || v_txt, trim(p_motif));
    perform public.notifier(m.id, case when p_decision = 'refuser' then 'Votre demande (' || v_txt || ') est refusée. Motif : ' else 'Katana demande des précisions sur votre demande (' || v_txt || ') : ' end || trim(p_motif));
    return d.statut;
  elsif p_decision <> 'accepter' then
    raise exception 'Décision inconnue.';
  end if;

  if d.type = 'compte2' then
    v_max := (public.lire_param('comptes_max') #>> '{}')::int;
    if (select count(*) from public.comptes_jeu where membre_id = m.id and statut <> 'remplace') >= v_max then
      raise exception 'Ce membre a déjà le nombre maximum de comptes (%).', v_max;
    end if;
    if exists (select 1 from public.comptes_jeu where uid = d.details->>'uid') then raise exception 'Cet UID est déjà enregistré.'; end if;
    insert into public.comptes_jeu (membre_id, uid, pseudo, statut) values (m.id, d.details->>'uid', d.details->>'pseudo', 'en_pause')
    returning id into v_cpt;
    insert into public.pseudos_historique (compte_id, pseudo, debut) values (v_cpt, d.details->>'pseudo', clock_timestamp());
    if coalesce((d.details->>'activer')::boolean, false) then
      perform public.activer_compte(m.id, v_cpt);
      update public.membres set dernier_changement_compte = clock_timestamp() where id = m.id;
    end if;
  elsif d.type = 'compte_actif' then
    v_jours := (public.lire_param('delai_changement_compte_jours') #>> '{}')::int;
    if m.dernier_changement_compte is not null and clock_timestamp() < m.dernier_changement_compte + make_interval(days => v_jours) then
      raise exception 'Le délai de % jours depuis le dernier changement n''est pas écoulé.', v_jours;
    end if;
    perform public.activer_compte(m.id, (d.details->>'compte_id')::bigint);
    update public.membres set dernier_changement_compte = clock_timestamp() where id = m.id;
  elsif d.type = 'pseudo' then
    if coalesce(trim(p_pseudo_valide), '') = '' then raise exception 'Indiquez le pseudo vérifié.'; end if;
    perform public.changer_pseudo((d.details->>'compte_id')::bigint, trim(p_pseudo_valide));
    d.details := d.details || jsonb_build_object('pseudo_valide', trim(p_pseudo_valide));
  elsif d.type = 'retrait' then
    perform public.appliquer_retrait(m.id, d.details->>'motif');
  else
    raise exception 'Ce type de demande se traite ailleurs.';
  end if;

  update public.demandes set statut = 'acceptee', decide_le = clock_timestamp(), details = d.details,
    motif_decision = nullif(trim(coalesce(p_motif, '')), '') where id = d.id;
  insert into public.journal (type, objet, decision, motif)
  values ('Demande', 'DFMM-' || m.matricule, 'Demande acceptée : ' || v_txt, nullif(trim(coalesce(p_motif, '')), ''));
  if d.type <> 'retrait' then perform public.notifier(m.id, 'Votre demande (' || v_txt || ') est acceptée.'); end if;
  return 'acceptee';
end $$;

-- Réintégration d'un membre retiré : même matricule, nouvelle période à partir de maintenant.
create function public.reintegrer_membre(p_membre bigint, p_compte bigint, p_motif text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype;
begin
  if not public.est_admin() then raise exception 'Accès réservé à l''administrateur.'; end if;
  select * into m from public.membres where id = p_membre for update;
  if not found then raise exception 'Membre introuvable.'; end if;
  if m.statut <> 'retire' then raise exception 'Seul un membre retiré peut être réintégré.'; end if;
  update public.membres set statut = 'actif' where id = p_membre;
  insert into public.periodes (membre_id, debut) values (p_membre, clock_timestamp());
  perform public.activer_compte(p_membre, p_compte);
  insert into public.journal (type, objet, decision, motif)
  values ('Membre', 'DFMM-' || m.matricule, 'Réintégration (même matricule)', nullif(trim(coalesce(p_motif, '')), ''));
  perform public.notifier(p_membre, 'Votre réintégration dans la LEAGUE UV est acceptée. Bon retour !');
end $$;

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.demandes      enable row level security;
alter table public.notifications enable row level security;

revoke all on public.demandes, public.notifications from anon, authenticated;
grant select on public.demandes, public.notifications to authenticated;
grant update (lu) on public.notifications to authenticated;
-- Aucune autre écriture directe : demandes et notifications passent par les fonctions contrôlées ci-dessus.

create policy "admin gère" on public.demandes for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siennes" on public.demandes for select to authenticated
  using (membre_id in (select public.mes_membres()));
create policy "admin gère" on public.notifications for all to authenticated
  using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre voit les siennes" on public.notifications for select to authenticated
  using (membre_id in (select public.mes_membres()));
create policy "membre marque lues" on public.notifications for update to authenticated
  using (membre_id in (select public.mes_membres())) with check (membre_id in (select public.mes_membres()));

-- Le membre dépose la capture de son 2e compte dans son propre dossier du stockage privé.
create policy "profils : dépôt dans son dossier" on storage.objects for insert to authenticated
  with check (bucket_id = 'profils' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Fonctions : les outils internes ne sont jamais appelables par le site.
revoke all on function public.lire_param(text), public.notifier(bigint, text), public.mon_membre_actif(),
  public.activer_compte(bigint, bigint), public.changer_pseudo(bigint, text), public.appliquer_retrait(bigint, text)
  from public, anon, authenticated;
grant execute on function public.changer_pseudo(bigint, text), public.notifier(bigint, text), public.lire_param(text) to service_role;
revoke all on function public.demander_compte2(text, text, text, text, boolean), public.demander_compte_actif(bigint, text),
  public.demander_retrait(text), public.decider_demande(bigint, text, text, text), public.reintegrer_membre(bigint, bigint, text)
  from public, anon;
grant execute on function public.demander_compte2(text, text, text, text, boolean), public.demander_compte_actif(bigint, text),
  public.demander_retrait(text), public.decider_demande(bigint, text, text, text), public.reintegrer_membre(bigint, bigint, text)
  to authenticated;
grant select, insert, update, delete on public.demandes, public.notifications to service_role;

commit;
