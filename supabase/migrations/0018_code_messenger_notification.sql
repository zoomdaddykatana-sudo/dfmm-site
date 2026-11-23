-- =====================================================================
-- LEAGUE UV — DFMM · Code Messenger dans les notifications · migration 0018
-- Constat de Katana du 23/11/2026 : le message de fin d'inscription (code UV-XXXXXX à envoyer à la page DFMM
-- sur Messenger) disparaît trop vite : le joueur part sur Facebook, revient, et le code n'est plus affiché.
-- Choix de Katana du 23/11/2026 : « bouton joueur + fin automatique », « bouton Messenger direct ».
--  1. À l'inscription, le code est aussi rangé dans les notifications du joueur (sujet « code_messenger ») ;
--  2. le joueur connecté touche « J'ai envoyé le code » : la date est notée (code_signale_le), Katana la voit ;
--  3. à l'approbation (ou au refus), la notification du code est classée (lue) toute seule ;
--     à l'approbation, le joueur reçoit « Votre inscription est approuvée » avec son matricule ;
--  4. inscriptions déjà en attente avec un code : la notification du code est ajoutée une seule fois.
-- Aucune règle changée. Ne supprime rien.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- =====================================================================
begin;

alter table public.membres_prives add column code_signale_le timestamptz;
alter table public.notifications add column sujet text check (sujet is null or sujet in ('code_messenger'));

-- Texte de la notification du code (le site ajoute les boutons Messenger et page DFMM).
create function public.texte_notif_code(p_code text) returns text
language sql immutable set search_path = ''
as $$ select 'Dernière étape de votre inscription : envoyez le code ' || p_code
  || ' en message privé à la page Facebook DFMM, depuis le compte Facebook que vous avez indiqué. Ensuite, touchez « J''ai envoyé le code ».' $$;
revoke all on function public.texte_notif_code(text) from public, anon, authenticated;

-- ---------- Point 1 : notification du code à l'inscription ----------
create function public.notifier_code_messenger() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.code_messenger is not null then
    insert into public.notifications (membre_id, texte, sujet)
    values (new.membre_id, public.texte_notif_code(new.code_messenger), 'code_messenger');
  end if;
  return new;
end $$;
revoke all on function public.notifier_code_messenger() from public, anon, authenticated;
create trigger notifier_code_messenger after insert on public.membres_prives
  for each row execute function public.notifier_code_messenger();

-- ---------- Point 2 : « J'ai envoyé le code » (joueur connecté, inscription en attente) ----------
create function public.signaler_code_envoye() returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare v_m bigint; v_le timestamptz;
begin
  select m.id into v_m from public.membres m
  where m.user_id = (select auth.uid()) and m.statut in ('en_attente', 'precisions')
  order by m.id desc limit 1;
  if v_m is null then raise exception 'Aucune inscription en attente sur ce compte.'; end if;
  update public.membres_prives set code_signale_le = coalesce(code_signale_le, now())
  where membre_id = v_m and code_messenger is not null
  returning code_signale_le into v_le;
  if v_le is null then raise exception 'Aucun code Messenger pour cette inscription.'; end if;
  return v_le;
end $$;
revoke all on function public.signaler_code_envoye() from public, anon;
grant execute on function public.signaler_code_envoye() to authenticated;

-- ---------- Point 3 : décision sur l'inscription → notification du code classée ----------
create function public.fin_code_messenger() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.statut in ('en_attente', 'precisions') and new.statut in ('actif', 'refuse') then
    update public.notifications set lu = true
    where membre_id = new.id and sujet = 'code_messenger' and not lu;
    if new.statut = 'actif' then
      perform public.notifier(new.id, 'Votre inscription est approuvée : bienvenue dans la LEAGUE UV ! Votre matricule est DFMM-'
        || new.matricule || '.');
    end if;
  end if;
  return new;
end $$;
revoke all on function public.fin_code_messenger() from public, anon, authenticated;
create trigger fin_code_messenger after update of statut on public.membres
  for each row execute function public.fin_code_messenger();

-- ---------- Point 4 : inscriptions déjà en attente (une seule fois) ----------
do $$
declare n integer;
begin
  insert into public.notifications (membre_id, texte, sujet)
  select p.membre_id, public.texte_notif_code(p.code_messenger), 'code_messenger'
  from public.membres_prives p join public.membres m on m.id = p.membre_id
  where p.code_messenger is not null and m.statut in ('en_attente', 'precisions')
    and not exists (select 1 from public.notifications n where n.membre_id = p.membre_id and n.sujet = 'code_messenger');
  get diagnostics n = row_count;
  raise notice 'Notifications du code ajoutées aux inscriptions en attente : %', n;
end $$;

commit;
