-- =====================================================================
-- LEAGUE UV — DFMM · Lot 4B « matchs en attente et litiges » · migration 0010
-- Cahier, section 6 : un dossier par match en attente, discussion dans le site (jamais hors site),
-- convocations confirmées sous 12 h, témoins, décision de Katana (vraie capture, match refusé ou
-- annulé), discussion fermée à la décision, synthèse validée puis archivée, captures écartées
-- supprimées (tout de suite sans sanction, après le délai de recours avec sanction).
-- Confidentialité (section 9) : seuls Katana et les personnes convoquées voient un dossier.
-- À exécuter UNE fois dans Supabase. Ne supprime rien : ajoute 3 tables, une colonne aux
-- sanctions, un déclencheur sur les matchs et des fonctions.
-- =====================================================================
begin;

create table public.dossiers (
  id                     bigint generated always as identity primary key,
  match_id               bigint not null unique references public.matchs(id),
  ouvert_le              timestamptz not null default clock_timestamp(),
  est_litige             boolean,                      -- null : à qualifier ; vrai : capture contradictoire ou falsifiée
  faits                  text,                         -- faits constatés
  statut                 text not null default 'ouvert' check (statut in ('ouvert', 'tranche', 'archive')),
  decision               text check (decision in ('capture_retenue', 'match_refuse', 'match_annule')),
  capture_retenue_id     bigint references public.captures(id),
  motif_decision         text,
  decide_le              timestamptz,
  synthese               text,
  synthese_validee_le    timestamptz,
  captures_supprimees_le timestamptz
);

alter table public.sanctions add column dossier_id bigint references public.dossiers(id);

create table public.convocations (
  id          bigint generated always as identity primary key,
  dossier_id  bigint not null references public.dossiers(id),
  membre_id   bigint not null references public.membres(id),
  role        text not null check (role in ('organisateur', 'responsable', 'joueur', 'temoin')),
  convoque_le timestamptz not null default clock_timestamp(),
  confirme_le timestamptz,
  unique (dossier_id, membre_id)
);

create table public.messages_litige (
  id         bigint generated always as identity primary key,
  dossier_id bigint not null references public.dossiers(id),
  membre_id  bigint references public.membres(id),     -- vide : message de Katana
  texte      text not null check (length(trim(texte)) > 0),
  cree_le    timestamptz not null default clock_timestamp()
);
create index messages_litige_dossier on public.messages_litige (dossier_id, cree_le);

-- ---------- Ouverture automatique d'un dossier quand un match passe en attente ----------
create function public.matchs_ouvrir_dossier() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.statut = 'attente' and old.statut is distinct from 'attente'
     and not exists (select 1 from public.dossiers where match_id = new.id) then
    insert into public.dossiers (match_id) values (new.id);
    insert into public.journal (type, objet, decision, motif) values ('Litige', 'M-' || new.id, 'Dossier ouvert (match en attente)', new.motif);
  end if;
  return null;
end $$;
create trigger matchs_ouvrir_dossier after update of statut on public.matchs
for each row execute function public.matchs_ouvrir_dossier();

-- ---------- Outils ----------
create function public.est_convoque(p_dossier bigint) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.convocations where dossier_id = p_dossier and membre_id in (select public.mes_membres())) $$;

-- ---------- Administrateur : qualifier, convoquer, écrire, trancher, valider la synthèse ----------
create function public.qualifier_dossier(p_dossier bigint, p_litige boolean, p_faits text) returns void
language plpgsql security definer set search_path = ''
as $$
declare d public.dossiers%rowtype;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into d from public.dossiers where id = p_dossier for update;
  if not found then raise exception 'Dossier introuvable.'; end if;
  if d.statut <> 'ouvert' then raise exception 'Ce dossier est déjà tranché.'; end if;
  update public.dossiers set est_litige = p_litige, faits = nullif(trim(coalesce(p_faits, '')), '') where id = d.id;
  if p_litige and d.est_litige is distinct from true then
    insert into public.registre (match_id, type, detail) values (d.match_id, 'litige_ouvert', 'Dossier n° ' || d.id || ' : capture contradictoire ou falsifiée');
  end if;
end $$;

create function public.convoquer(p_dossier bigint, p_membre bigint, p_role text) returns void
language plpgsql security definer set search_path = ''
as $$
declare d public.dossiers%rowtype; m public.membres%rowtype; v_h int;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into d from public.dossiers where id = p_dossier;
  if not found then raise exception 'Dossier introuvable.'; end if;
  if d.statut <> 'ouvert' then raise exception 'Ce dossier est déjà tranché.'; end if;
  select * into m from public.membres where id = p_membre;
  if not found or m.matricule is null then raise exception 'Membre introuvable.'; end if;
  if p_role not in ('organisateur', 'responsable', 'joueur', 'temoin') then raise exception 'Rôle inconnu.'; end if;
  if exists (select 1 from public.convocations where dossier_id = d.id and membre_id = m.id) then raise exception 'Ce membre est déjà convoqué.'; end if;
  insert into public.convocations (dossier_id, membre_id, role) values (d.id, m.id, p_role);
  v_h := (public.lire_param('convocation_h') #>> '{}')::int;
  perform public.notifier(m.id, 'Katana vous convoque pour le dossier n° ' || d.id || ' (match M-' || d.match_id || '). Confirmez la réception dans les ' || v_h
    || ' h dans « Mon compte » et restez disponible. Ce dossier est confidentiel : ne divulguez ni la discussion, ni les témoignages, ni les captures.');
  insert into public.journal (type, objet, decision) values ('Litige', 'Dossier n° ' || d.id, 'Convocation de DFMM-' || m.matricule || ' (' || p_role || ')');
end $$;

-- Écrire dans la discussion : Katana ou une personne convoquée, tant que le dossier est ouvert.
create function public.ecrire_litige(p_dossier bigint, p_texte text) returns void
language plpgsql security definer set search_path = ''
as $$
declare d public.dossiers%rowtype; v_membre bigint; v_txt text := nullif(trim(coalesce(p_texte, '')), '');
begin
  select * into d from public.dossiers where id = p_dossier;
  if not found then raise exception 'Dossier introuvable.'; end if;
  if v_txt is null then raise exception 'Le message est vide.'; end if;
  if not (select public.est_admin()) then
    select membre_id into v_membre from public.convocations where dossier_id = d.id and membre_id in (select public.mes_membres());
    if v_membre is null then raise exception 'Dossier introuvable.'; end if;
  end if;
  if d.statut <> 'ouvert' then raise exception 'La discussion est fermée : le dossier est tranché.'; end if;
  insert into public.messages_litige (dossier_id, membre_id, texte) values (d.id, v_membre, v_txt);
end $$;

create function public.confirmer_convocation(p_dossier bigint) returns void
language plpgsql security definer set search_path = ''
as $$
declare c public.convocations%rowtype;
begin
  select * into c from public.convocations where dossier_id = p_dossier and membre_id in (select public.mes_membres()) for update;
  if not found then raise exception 'Convocation introuvable.'; end if;
  if c.confirme_le is null then update public.convocations set confirme_le = clock_timestamp() where id = c.id; end if;
end $$;

-- Trancher : « capture_retenue » (la vraie capture ; les autres sont écartées ; le match est validé),
-- « match_refuse » ou « match_annule » (toutes les captures sont écartées). La discussion se ferme.
create function public.trancher_dossier(p_dossier bigint, p_decision text, p_capture bigint, p_motif text) returns void
language plpgsql security definer set search_path = ''
as $$
declare d public.dossiers%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), ''); v_lib text; c record;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into d from public.dossiers where id = p_dossier for update;
  if not found then raise exception 'Dossier introuvable.'; end if;
  if d.statut <> 'ouvert' then raise exception 'Ce dossier est déjà tranché.'; end if;
  if v_motif is null then raise exception 'Le motif de la décision est obligatoire.'; end if;
  if p_decision = 'capture_retenue' then
    if not exists (select 1 from public.captures where id = p_capture and match_id = d.match_id and statut in ('recue', 'retenue')) then
      raise exception 'Choisissez la vraie capture parmi les captures reçues pour ce match.';
    end if;
    update public.captures set statut = 'ecartee', motif = 'Écartée par la décision du dossier n° ' || d.id
     where match_id = d.match_id and id <> p_capture and statut in ('recue', 'retenue');
    perform public.decider_match(d.match_id, 'valider', null);
    v_lib := 'Vraie capture retenue, match validé';
  elsif p_decision in ('match_refuse', 'match_annule') then
    perform public.decider_match(d.match_id, case when p_decision = 'match_refuse' then 'refuser' else 'annuler' end, v_motif);
    update public.captures set statut = 'ecartee', motif = 'Écartée par la décision du dossier n° ' || d.id
     where match_id = d.match_id and statut in ('recue', 'retenue', 'refusee');
    v_lib := case when p_decision = 'match_refuse' then 'Match refusé' else 'Match annulé pour tous' end;
  else
    raise exception 'Décision inconnue.';
  end if;
  update public.dossiers set statut = 'tranche', decision = p_decision, capture_retenue_id = case when p_decision = 'capture_retenue' then p_capture end,
         motif_decision = v_motif, decide_le = clock_timestamp() where id = d.id;
  insert into public.registre (match_id, type, detail) values (d.match_id, 'decision', 'Dossier n° ' || d.id || ' tranché : ' || v_lib || ' — ' || v_motif);
  insert into public.journal (type, objet, decision, motif) values ('Litige', 'Dossier n° ' || d.id, v_lib, v_motif);
  for c in select membre_id from public.convocations where dossier_id = d.id loop
    perform public.notifier(c.membre_id, 'Le dossier n° ' || d.id || ' (match M-' || d.match_id || ') est tranché : ' || v_lib || '. La discussion est fermée.');
  end loop;
end $$;

create function public.valider_synthese(p_dossier bigint, p_synthese text) returns void
language plpgsql security definer set search_path = ''
as $$
declare d public.dossiers%rowtype;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into d from public.dossiers where id = p_dossier for update;
  if not found then raise exception 'Dossier introuvable.'; end if;
  if d.statut = 'ouvert' then raise exception 'Tranchez d''abord le dossier.'; end if;
  if nullif(trim(coalesce(p_synthese, '')), '') is null then raise exception 'La synthèse est vide.'; end if;
  update public.dossiers set synthese = trim(p_synthese), synthese_validee_le = clock_timestamp(), statut = 'archive' where id = d.id;
  insert into public.journal (type, objet, decision) values ('Litige', 'Dossier n° ' || d.id, 'Synthèse validée, dossier archivé');
end $$;

-- Date à partir de laquelle les captures écartées peuvent être supprimées : tout de suite sans sanction,
-- après le délai de recours (et la réponse à une contestation) avec sanction.
create function public.suppression_captures_le(p_dossier bigint) returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select case
    when d.statut = 'ouvert' then null
    when exists (select 1 from public.sanctions s where s.dossier_id = d.id and s.statut = 'active' and s.conteste_le is not null and s.decision_recours is null) then null
    else greatest(d.decide_le, coalesce((select max(s.recours_jusqu) from public.sanctions s where s.dossier_id = d.id and s.statut = 'active'), d.decide_le))
  end
  from public.dossiers d where d.id = p_dossier
$$;

-- Chemins des captures écartées à supprimer (si la date est atteinte) ; le site supprime les fichiers,
-- puis appelle noter_captures_supprimees. Le registre et la synthèse restent.
create function public.captures_a_supprimer(p_dossier bigint) returns text[]
language plpgsql stable security definer set search_path = ''
as $$
declare d public.dossiers%rowtype; v_le timestamptz;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into d from public.dossiers where id = p_dossier;
  if not found then raise exception 'Dossier introuvable.'; end if;
  v_le := public.suppression_captures_le(d.id);
  if v_le is null then raise exception 'Suppression pas encore possible : dossier ouvert ou contestation en cours.'; end if;
  if clock_timestamp() < v_le then raise exception 'Suppression possible à partir du %.', public.date_mg(v_le); end if;
  return coalesce((select array_agg(chemin order by id) from public.captures where match_id = d.match_id and statut = 'ecartee'), '{}');
end $$;

create function public.noter_captures_supprimees(p_dossier bigint) returns void
language plpgsql security definer set search_path = ''
as $$
declare d public.dossiers%rowtype; n int;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into d from public.dossiers where id = p_dossier for update;
  if not found then raise exception 'Dossier introuvable.'; end if;
  select count(*) into n from public.captures where match_id = d.match_id and statut = 'ecartee';
  update public.dossiers set captures_supprimees_le = clock_timestamp() where id = d.id;
  insert into public.registre (match_id, type, detail) values (d.match_id, 'decision', n || ' capture(s) écartée(s) supprimée(s) (dossier n° ' || d.id || ')');
end $$;

-- Relier une sanction (décidée avec « sanctionner ») au dossier de litige qui l'a motivée.
create function public.sanctionner_dossier(p_sanction bigint, p_dossier bigint) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  if not exists (select 1 from public.dossiers where id = p_dossier) then raise exception 'Dossier introuvable.'; end if;
  update public.sanctions set dossier_id = p_dossier where id = p_sanction and dossier_id is null;
end $$;

-- =====================================================================
-- Stockage : l'administrateur peut supprimer les captures écartées
-- =====================================================================
create policy "captures : suppression administrateur" on storage.objects for delete to authenticated
  using (bucket_id = 'captures' and (select public.est_admin()));

-- =====================================================================
-- Règles d'accès : Katana et les personnes convoquées seulement
-- =====================================================================
alter table public.dossiers        enable row level security;
alter table public.convocations    enable row level security;
alter table public.messages_litige enable row level security;
revoke all on public.dossiers, public.convocations, public.messages_litige from anon, authenticated;
grant select on public.dossiers, public.convocations, public.messages_litige to authenticated;
create policy "admin lit" on public.dossiers        for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.convocations    for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.messages_litige for select to authenticated using ((select public.est_admin()));
create policy "convoqué lit" on public.dossiers        for select to authenticated using ((select public.est_convoque(id)));
create policy "convoqué lit" on public.convocations    for select to authenticated using ((select public.est_convoque(dossier_id)));
create policy "convoqué lit" on public.messages_litige for select to authenticated using ((select public.est_convoque(dossier_id)));
grant select, insert, update, delete on public.dossiers, public.convocations, public.messages_litige to service_role;

revoke all on function public.matchs_ouvrir_dossier(), public.suppression_captures_le(bigint) from public, anon, authenticated;
revoke all on function public.est_convoque(bigint) from public, anon;
grant execute on function public.est_convoque(bigint) to authenticated;
revoke all on function public.qualifier_dossier(bigint, boolean, text), public.convoquer(bigint, bigint, text), public.ecrire_litige(bigint, text),
                       public.confirmer_convocation(bigint), public.trancher_dossier(bigint, text, bigint, text), public.valider_synthese(bigint, text),
                       public.captures_a_supprimer(bigint), public.noter_captures_supprimees(bigint), public.sanctionner_dossier(bigint, bigint) from public, anon;
grant execute on function public.qualifier_dossier(bigint, boolean, text), public.convoquer(bigint, bigint, text), public.ecrire_litige(bigint, text),
                          public.confirmer_convocation(bigint), public.trancher_dossier(bigint, text, bigint, text), public.valider_synthese(bigint, text),
                          public.captures_a_supprimer(bigint), public.noter_captures_supprimees(bigint), public.sanctionner_dossier(bigint, bigint) to authenticated;

commit;
