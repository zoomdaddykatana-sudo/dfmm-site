-- =====================================================================
-- LEAGUE UV — DFMM · Actualités et messagerie · migration 0012
-- Cahier, section 1 : page d'actualités alimentée seulement par Katana, les membres lisent sans
-- publier (décision du 22/11/2026 : visibles seulement par les membres connectés) ; messagerie
-- personnelle avec Katana, pas de messagerie entre joueurs ; réclamation sur un classement publié
-- par la messagerie, dans le délai réglé (« reclamation_h », 48 h).
-- À exécuter UNE fois dans Supabase. Ne supprime rien : ajoute 2 tables et des fonctions.
-- =====================================================================
begin;

create table public.actualites (
  id        bigint generated always as identity primary key,
  titre     text not null check (length(trim(titre)) > 0),
  texte     text not null check (length(trim(texte)) > 0),
  publie_le timestamptz not null default clock_timestamp(),
  retire_le timestamptz,
  auteur    uuid default auth.uid()
);

create table public.messages (
  id             bigint generated always as identity primary key,
  membre_id      bigint not null references public.membres(id),
  de_katana      boolean not null,
  texte          text not null check (length(trim(texte)) > 0),
  publication_id bigint references public.publications(id),   -- réclamation sur ce classement
  cree_le        timestamptz not null default clock_timestamp(),
  lu_le          timestamptz
);
create index messages_membre on public.messages (membre_id, cree_le);

-- Lecteur des actualités et de la messagerie : membre approuvé, non retiré (un membre suspendu ou
-- exclu lit les annonces et peut écrire à Katana pour contester).
create function public.mon_membre_lecteur() returns bigint
language sql stable security definer set search_path = ''
as $$ select id from public.membres where user_id = (select auth.uid()) and matricule is not null and statut in ('actif', 'exclu') $$;

-- ---------- Messagerie ----------
create function public.ecrire_a_katana(p_texte text, p_publication bigint default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_m bigint := public.mon_membre_lecteur(); v_txt text := nullif(trim(coalesce(p_texte, '')), ''); pub public.publications%rowtype; v_mat integer;
begin
  if v_m is null then raise exception 'La messagerie est réservée aux membres.'; end if;
  if v_txt is null then raise exception 'Le message est vide.'; end if;
  if p_publication is not null then
    select * into pub from public.publications where id = p_publication;
    if not found then raise exception 'Classement introuvable.'; end if;
    if clock_timestamp() > pub.publie_le + make_interval(hours => (public.lire_param('reclamation_h') #>> '{}')::int) then
      raise exception 'Le délai de réclamation sur ce classement est dépassé.';
    end if;
  end if;
  insert into public.messages (membre_id, de_katana, texte, publication_id) values (v_m, false, v_txt, p_publication);
  if p_publication is not null then
    select matricule into v_mat from public.membres where id = v_m;
    insert into public.journal (type, objet, decision) values ('Réclamation', 'DFMM-' || v_mat,
      'Réclamation sur le classement ' || case when pub.type = 'final' then 'final' else 'provisoire n° ' || pub.numero end);
  end if;
end $$;

create function public.repondre_membre(p_membre bigint, p_texte text) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_txt text := nullif(trim(coalesce(p_texte, '')), '');
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  if v_txt is null then raise exception 'Le message est vide.'; end if;
  if not exists (select 1 from public.membres where id = p_membre and matricule is not null) then raise exception 'Membre introuvable.'; end if;
  insert into public.messages (membre_id, de_katana, texte) values (p_membre, true, v_txt);
  perform public.notifier(p_membre, 'Nouveau message de Katana : voir « Messages avec Katana » dans Mon compte.');
end $$;

-- Marquer comme lus : l'administrateur, les messages d'un membre ; le membre, les messages de Katana.
create function public.marquer_messages_lus(p_membre bigint default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_m bigint;
begin
  if (select public.est_admin()) and p_membre is not null then
    update public.messages set lu_le = clock_timestamp() where membre_id = p_membre and not de_katana and lu_le is null;
  else
    v_m := public.mon_membre_lecteur();
    if v_m is null then raise exception 'La messagerie est réservée aux membres.'; end if;
    update public.messages set lu_le = clock_timestamp() where membre_id = v_m and de_katana and lu_le is null;
  end if;
end $$;

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.actualites enable row level security;
alter table public.messages   enable row level security;
revoke all on public.actualites, public.messages from anon, authenticated;
grant select, insert, update on public.actualites to authenticated;
grant select on public.messages to authenticated;
create policy "admin gère" on public.actualites for all to authenticated using ((select public.est_admin())) with check ((select public.est_admin()));
create policy "membre lit" on public.actualites for select to authenticated using (retire_le is null and (select public.mon_membre_lecteur()) is not null);
create policy "admin lit" on public.messages for select to authenticated using ((select public.est_admin()));
create policy "membre lit les siens" on public.messages for select to authenticated using (membre_id = (select public.mon_membre_lecteur()));
grant select, insert, update, delete on public.actualites, public.messages to service_role;

revoke all on function public.mon_membre_lecteur() from public, anon;
grant execute on function public.mon_membre_lecteur() to authenticated;
revoke all on function public.ecrire_a_katana(text, bigint), public.repondre_membre(bigint, text), public.marquer_messages_lus(bigint) from public, anon;
grant execute on function public.ecrire_a_katana(text, bigint), public.repondre_membre(bigint, text), public.marquer_messages_lus(bigint) to authenticated;

commit;
