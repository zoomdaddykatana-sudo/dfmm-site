-- =====================================================================
-- LEAGUE UV — DFMM · Limites de sécurité (PR A) · migration 0015
-- Choix de Katana du 22/11/2026 : décision 1 = limite d'inscriptions par heure seule (pas de case anti-robot) ;
-- décision 2 = 1 déclaration de pseudo par compte et par 24 h, bloquée pendant une suspension ;
-- décision 3 = 100 caractères au plus pour les noms, pseudos et champs courts, 2 000 pour les messages et motifs.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 4 réglages, 2 tables (compteurs), des contrôles de longueur, et complète
-- enregistrer_declaration_pseudo (refus pendant une suspension et texte trop long).
-- =====================================================================
begin;

-- ---------- Réglages (Administration > Paramètres > Limites) ----------
insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('inscriptions_max_heure', '10',   'entier', 'Inscriptions vérifiées par heure, au plus (au-delà : « réessayez plus tard »)', 'Limites', 1),
  ('pseudo_delai_h',         '24',   'entier', 'Délai entre deux déclarations de pseudo pour un même compte (h)',              'Limites', 2),
  ('longueur_max_court',     '100',  'entier', 'Longueur maximale des noms, pseudos et champs courts (caractères)',            'Limites', 3),
  ('longueur_max_long',      '2000', 'entier', 'Longueur maximale des messages et motifs (caractères)',                         'Limites', 4);

-- ---------- Compteurs (administrateur seulement) ----------
-- Une ligne par inscription arrivée à l'appel à volsever (le seul passage qui coûte : quota volsever, stockage).
create table public.inscription_essais (
  id      bigint generated always as identity primary key,
  cree_le timestamptz not null default clock_timestamp()
);
create index inscription_essais_date on public.inscription_essais (cree_le);

-- Une ligne par déclaration de pseudo acceptée (avant l'appel à volsever).
create table public.declarations_pseudo (
  id        bigint generated always as identity primary key,
  compte_id bigint not null references public.comptes_jeu(id) on delete cascade,
  cree_le   timestamptz not null default clock_timestamp()
);
create index declarations_pseudo_compte on public.declarations_pseudo (compte_id, cree_le);

-- ---------- Longueur maximale d'un texte ----------
-- p_type : « court » (noms, pseudos, e-mail, UID) ou « long » (messages, motifs, lien Facebook).
create function public.verifier_longueur(p_texte text, p_type text, p_nom text) returns void
language plpgsql stable security definer set search_path = ''
as $$
declare v_max int := (public.lire_param(case when p_type = 'court' then 'longueur_max_court' else 'longueur_max_long' end) #>> '{}')::int;
begin
  if p_texte is not null and v_max is not null and char_length(p_texte) > v_max then
    raise exception 'Texte trop long (%) : % caractères au plus.', p_nom, v_max;
  end if;
end $$;

-- Contrôle à l'enregistrement, quel que soit le chemin (site, fonction serveur).
create function public.longueurs_textes() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name in ('messages', 'messages_litige') then
    perform public.verifier_longueur(new.texte, 'long', 'message');
  elsif tg_table_name = 'sanctions' then
    perform public.verifier_longueur(new.contestation, 'long', 'contestation');
  elsif tg_table_name = 'creneaux' then
    perform public.verifier_longueur(new.motif, 'long', 'motif');
  elsif tg_table_name = 'demandes' then
    perform public.verifier_longueur(new.details->>'pseudo', 'court', 'pseudo');
    perform public.verifier_longueur(new.details->>'pseudo_declare', 'court', 'pseudo');
    perform public.verifier_longueur(new.details->>'uid', 'court', 'UID');
    perform public.verifier_longueur(new.details->>'motif', 'long', 'motif');
  elsif tg_table_name = 'membres' then
    perform public.verifier_longueur(new.nom_gamer, 'court', 'nom de gamer');
  elsif tg_table_name = 'membres_prives' then
    perform public.verifier_longueur(new.nom_reel, 'court', 'nom réel');
    perform public.verifier_longueur(new.email, 'court', 'e-mail');
    perform public.verifier_longueur(new.clan, 'court', 'clan');
    perform public.verifier_longueur(new.pays, 'court', 'pays');
    perform public.verifier_longueur(new.facebook, 'long', 'lien Facebook');
  end if;
  return new;
end $$;

create trigger longueurs_textes before insert or update of texte on public.messages
  for each row execute function public.longueurs_textes();
create trigger longueurs_textes before insert or update of texte on public.messages_litige
  for each row execute function public.longueurs_textes();
create trigger longueurs_textes before update of contestation on public.sanctions
  for each row execute function public.longueurs_textes();
create trigger longueurs_textes before insert or update of motif on public.creneaux
  for each row execute function public.longueurs_textes();
create trigger longueurs_textes before insert or update of details on public.demandes
  for each row execute function public.longueurs_textes();
create trigger longueurs_textes before insert or update of nom_gamer on public.membres
  for each row execute function public.longueurs_textes();
create trigger longueurs_textes before insert or update of nom_reel, email, clan, pays, facebook on public.membres_prives
  for each row execute function public.longueurs_textes();

-- ---------- Inscription : une place dans la limite par heure (appelée par la fonction « inscription ») ----------
-- Vrai = l'inscription continue (place notée) ; faux = limite atteinte ou réglage illisible.
create function public.reserver_essai_inscription() returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_max int := (public.lire_param('inscriptions_max_heure') #>> '{}')::int;
begin
  perform pg_advisory_xact_lock(hashtext('dfmm_inscription_essais'));   -- deux envois en même temps : l'un après l'autre
  if v_max is null or (select count(*) from public.inscription_essais where cree_le > clock_timestamp() - interval '1 hour') >= v_max then
    return false;
  end if;
  insert into public.inscription_essais default values;
  return true;
end $$;

-- ---------- Déclaration de pseudo : contrôles AVANT l'appel à volsever (appelée par « pseudo-volsever ») ----------
-- Membre actif, non suspendu, compte à lui, pseudo pas trop long, aucune déclaration en attente,
-- dernière déclaration de ce compte il y a plus de « pseudo_delai_h » heures. La déclaration est notée.
create function public.reserver_declaration_pseudo(p_user uuid, p_compte bigint, p_tape text) returns void
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; c public.comptes_jeu%rowtype; v_tape text := trim(coalesce(p_tape, ''));
        v_h int := coalesce((public.lire_param('pseudo_delai_h') #>> '{}')::int, 24); v_der timestamptz;
begin
  select * into m from public.membres where user_id = p_user;
  if not found or m.statut <> 'actif' then raise exception 'Cette démarche est réservée aux membres actifs.'; end if;
  if public.est_suspendu(m.id, clock_timestamp()) then
    raise exception 'Démarche impossible pendant une suspension. Vous pouvez contester la sanction dans « Mon compte » pendant le délai prévu.';
  end if;
  select * into c from public.comptes_jeu where id = p_compte and membre_id = m.id for update;
  if not found or c.statut = 'remplace' then raise exception 'Choisissez l''un de vos comptes.'; end if;
  if v_tape = '' then raise exception 'Le nouveau pseudo est obligatoire.'; end if;
  perform public.verifier_longueur(v_tape, 'court', 'pseudo');
  if exists (select 1 from public.demandes where membre_id = m.id and type = 'pseudo' and statut in ('en_attente', 'precisions')
             and details->>'compte_id' = c.id::text) then
    raise exception 'Une déclaration de pseudo est déjà en attente pour ce compte.';
  end if;
  select max(cree_le) into v_der from public.declarations_pseudo where compte_id = c.id;
  if v_der is not null and clock_timestamp() < v_der + make_interval(hours => v_h) then
    raise exception 'Une seule déclaration de pseudo par compte toutes les % h. Prochaine déclaration possible le % (heure de Madagascar).',
      v_h, public.date_mg(v_der + make_interval(hours => v_h));
  end if;
  insert into public.declarations_pseudo (compte_id) values (c.id);
end $$;

-- ---------- Enregistrement du résultat de volsever : mêmes règles qu'en 0005, plus suspension et longueur ----------
create or replace function public.enregistrer_declaration_pseudo(p_user uuid, p_compte bigint, p_tape text, p_resultat text, p_trouve text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; c public.comptes_jeu%rowtype; v_mod boolean; v_tape text := trim(coalesce(p_tape, '')); v_raison text;
begin
  select * into m from public.membres where user_id = p_user;
  if not found or m.statut <> 'actif' then raise exception 'Cette démarche est réservée aux membres actifs.'; end if;
  if public.est_suspendu(m.id, clock_timestamp()) then
    raise exception 'Démarche impossible pendant une suspension. Vous pouvez contester la sanction dans « Mon compte » pendant le délai prévu.';
  end if;
  select * into c from public.comptes_jeu where id = p_compte and membre_id = m.id for update;
  if not found then raise exception 'Ce compte n''est pas à vous.'; end if;
  if c.statut = 'remplace' then raise exception 'Ce compte est remplacé.'; end if;
  if v_tape = '' then raise exception 'Le nouveau pseudo est obligatoire.'; end if;
  perform public.verifier_longueur(v_tape, 'court', 'pseudo');
  if exists (select 1 from public.demandes where membre_id = m.id and type = 'pseudo' and statut in ('en_attente', 'precisions')
             and details->>'compte_id' = c.id::text) then
    raise exception 'Une déclaration de pseudo est déjà en attente pour ce compte.';
  end if;

  if p_resultat = 'trouve' and coalesce(p_trouve, '') <> '' then
    v_mod := public.changer_pseudo(c.id, p_trouve);
    insert into public.journal (type, objet, decision)
    values ('Pseudo', 'DFMM-' || m.matricule, case when v_mod then 'Pseudo mis à jour par volsever : ' || c.pseudo || ' → ' || p_trouve
                                                  else 'Pseudo vérifié par volsever, inchangé : ' || p_trouve end);
    if p_trouve = v_tape then
      perform public.notifier(m.id, case when v_mod then 'Votre pseudo est mis à jour : ' || p_trouve || '.' else 'Votre pseudo est confirmé : ' || p_trouve || '.' end);
      return case when v_mod then 'modifie' else 'conforme' end;
    end if;
    insert into public.demandes (membre_id, type, details)
    values (m.id, 'pseudo', jsonb_build_object('compte_id', c.id, 'uid', c.uid, 'pseudo_declare', v_tape, 'pseudo_volsever', p_trouve, 'raison', 'écart entre le pseudo déclaré et le profil'));
    perform public.notifier(m.id, 'Le pseudo lu sur votre profil (' || p_trouve || ') est différent de celui que vous avez déclaré (' || v_tape || '). Le pseudo du profil est retenu ; Katana va vérifier.');
    return 'ecart';
  end if;

  v_raison := case p_resultat when 'introuvable' then 'UID introuvable chez volsever'
                              when 'quota' then 'limite d''appels à volsever atteinte'
                              when 'delai' then 'volsever n''a pas répondu à temps'
                              else 'volsever indisponible' end;
  insert into public.demandes (membre_id, type, details)
  values (m.id, 'pseudo', jsonb_build_object('compte_id', c.id, 'uid', c.uid, 'pseudo_declare', v_tape, 'raison', v_raison));
  insert into public.journal (type, objet, decision, motif) values ('Pseudo', 'DFMM-' || m.matricule, 'Déclaration de pseudo en attente : ' || v_tape, v_raison);
  perform public.notifier(m.id, 'Votre déclaration de pseudo (' || v_tape || ') est en attente : Katana va la valider à la main.');
  return 'attente';
end $$;

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.inscription_essais enable row level security;
alter table public.declarations_pseudo enable row level security;
revoke all on public.inscription_essais, public.declarations_pseudo from anon, authenticated;
grant select on public.inscription_essais, public.declarations_pseudo to authenticated;
create policy "admin lit" on public.inscription_essais for select to authenticated using ((select public.est_admin()));
create policy "admin lit" on public.declarations_pseudo for select to authenticated using ((select public.est_admin()));
grant select, insert, update, delete on public.inscription_essais, public.declarations_pseudo to service_role;

revoke all on function public.verifier_longueur(text, text, text), public.longueurs_textes(),
  public.reserver_essai_inscription(), public.reserver_declaration_pseudo(uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.reserver_essai_inscription(), public.reserver_declaration_pseudo(uuid, bigint, text) to service_role;
revoke all on function public.enregistrer_declaration_pseudo(uuid, bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.enregistrer_declaration_pseudo(uuid, bigint, text, text, text) to service_role;

commit;
