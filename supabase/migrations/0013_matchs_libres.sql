-- =====================================================================
-- LEAGUE UV — DFMM · Matchs libres (lot 3B) · migration 0013
-- Cahier, section 4 : déclaration au moins 2 h avant (« delai_declaration_h »), responsables HAAVK et
-- GTI (membres ; l'organisateur peut en être un ; une même personne peut l'être des deux factions),
-- alerte à Katana ; matricule non autorisé : demande retenue, message neutre, Katana l'accepte ou la
-- refuse ; un créneau = un match ; captures envoyées par chaque responsable (et l'organisateur s'il
-- n'est pas responsable), 2 au plus (haut puis bas) ; délai de 10 min après l'heure de fin, contrôlé
-- capture par capture quand Katana colle la lecture (capture en retard rejetée seule, exception pour
-- un échec technique prouvé) ; captures identiques : une seule conservée.
-- Décisions du 22/11/2026 : liste visible des membres connectés ; l'organisateur annule jusqu'à
-- l'heure de début ; envoi ouvert de l'heure de début à début + « plage_fin_h » + « delai_capture_min ».
-- Fermé tant que « matchs_libres_ouverts » vaut non.
-- À exécuter UNE fois dans Supabase. Ne supprime rien : ajoute une table, des colonnes et des fonctions.
-- =====================================================================
begin;

create table public.creneaux (
  id              bigint generated always as identity primary key,
  saison_id       bigint not null references public.saisons(id),
  organisateur_id bigint not null references public.membres(id),
  resp_haavk_id   bigint not null references public.membres(id),
  resp_gti_id     bigint not null references public.membres(id),
  debut           timestamptz not null,                  -- heure de début annoncée
  statut          text not null default 'annonce' check (statut in ('annonce', 'retenu', 'refuse', 'annule')),
  retenu_motif    text,                                  -- pour Katana seulement : matricule(s) non autorisé(s)
  annule_par      text check (annule_par in ('organisateur', 'katana')),
  motif           text,                                  -- motif d'annulation ou de refus (facultatif)
  cree_le         timestamptz not null default clock_timestamp(),
  decide_le       timestamptz,
  vu_le           timestamptz                            -- alerte vue par Katana
);
create index creneaux_debut on public.creneaux (debut);

alter table public.matchs add column creneau_id bigint unique references public.creneaux(id);

alter table public.captures
  add column envoyeur_id bigint references public.membres(id),          -- null : capture de Katana
  add column partie      text not null default 'unique' check (partie in ('unique', 'haut', 'bas')),
  add column exception   text,                                           -- retard accepté (échec technique prouvé)
  add column lecture     jsonb;                                          -- réponse de claude.ai collée par Katana
alter table public.captures drop constraint captures_statut_check;
alter table public.captures add constraint captures_statut_check check (statut in ('recue', 'retenue', 'refusee', 'ecartee', 'annulee'));
alter table public.registre drop constraint registre_type_check;
alter table public.registre add constraint registre_type_check check (type in ('match_declare', 'capture_recue', 'capture_acceptee',
  'capture_refusee', 'capture_annulee', 'capture_ecartee', 'match_en_attente', 'litige_ouvert', 'decision', 'sanction'));

-- Capture reçue : l'envoyeur est noté au registre.
create or replace function public.captures_apres_ajout() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.registre (match_id, type, membre_id, detail) values (new.match_id, 'capture_recue', new.envoyeur_id,
    'Capture reçue' || case when new.partie = 'haut' then ' (haut du tableau)' when new.partie = 'bas' then ' (bas du tableau)' else '' end);
  return null;
end $$;

-- =====================================================================
-- Outils internes
-- =====================================================================
-- Matricule autorisé comme organisateur ou responsable : membre actif, non suspendu (maintenant et à
-- l'heure du match), sans sanction « Capture falsifiée » en cours dans la saison.
create function public.autorise_libre(p_membre bigint, p_saison bigint, p_t timestamptz) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.membres where id = p_membre and statut = 'actif' and matricule is not null)
     and not public.est_suspendu(p_membre, clock_timestamp())
     and not public.est_suspendu(p_membre, p_t)
     and not exists (select 1 from public.sanctions x join public.saisons s on s.id = p_saison
                      where x.membre_id = p_membre and x.categorie = 'Capture falsifiée' and x.statut = 'active'
                        and x.debut >= (s.debut::timestamp at time zone 'Indian/Antananarivo'))
$$;

-- Fin de la période d'envoi des captures d'un créneau.
create function public.fin_envoi_captures(p_debut timestamptz) returns timestamptz
language sql stable security definer set search_path = ''
as $$ select p_debut + make_interval(mins => ((public.lire_param('plage_fin_h') #>> '{}')::numeric * 60
                                             + (public.lire_param('delai_capture_min') #>> '{}')::numeric)::int) $$;

-- Créer le match d'un créneau annoncé et avertir les responsables.
create function public.creer_match_libre(p_creneau bigint) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare c public.creneaux%rowtype; v_match bigint; v_org integer; v_txt text;
begin
  select * into c from public.creneaux where id = p_creneau;
  select matricule into v_org from public.membres where id = c.organisateur_id;
  insert into public.matchs (saison_id, type, demarrage, creneau_id) values (c.saison_id, 'libre', false, c.id) returning id into v_match;
  insert into public.registre (match_id, type, membre_id, detail)
  values (v_match, 'match_declare', c.organisateur_id, 'Match libre déclaré (créneau L-' || c.id || ', début le ' || public.date_mg(c.debut) || ')');
  v_txt := ' du match libre du ' || public.date_mg(c.debut) || ' (organisateur DFMM-' || v_org || '). Après le match, envoyez la capture de fin dans « Mon compte », rubrique « Matchs libres », au plus tard '
           || (public.lire_param('delai_capture_min') #>> '{}') || ' min après l''heure de fin affichée.';
  if c.resp_haavk_id = c.resp_gti_id then
    perform public.notifier(c.resp_haavk_id, 'Vous êtes responsable HAAVK et GTI' || v_txt);
  else
    perform public.notifier(c.resp_haavk_id, 'Vous êtes responsable HAAVK' || v_txt);
    perform public.notifier(c.resp_gti_id, 'Vous êtes responsable GTI' || v_txt);
  end if;
  return v_match;
end $$;

-- Envoi d'une capture possible pour ce membre et ce match (organisateur ou responsable, période ouverte).
create function public.envoyeur_autorise(p_match bigint, p_membre bigint) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.matchs m join public.creneaux c on c.id = m.creneau_id join public.membres mb on mb.id = p_membre
     where m.id = p_match and m.type = 'libre' and m.statut = 'brouillon' and c.statut = 'annonce'
       and p_membre in (c.organisateur_id, c.resp_haavk_id, c.resp_gti_id)
       and mb.statut = 'actif' and not public.est_suspendu(p_membre, clock_timestamp())
       and clock_timestamp() >= c.debut and clock_timestamp() <= public.fin_envoi_captures(c.debut))
$$;

-- Règles du stockage : chemin « <match>/m<membre>-<horodatage>.jpg ».
create function public.depot_capture_autorise(p_nom text) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare v_m bigint := public.mon_membre_lecteur(); v_dos text := split_part(p_nom, '/', 1);
begin
  if v_m is null or v_dos !~ '^[0-9]{1,18}$' or split_part(p_nom, '/', 3) <> '' then return false; end if;
  if split_part(p_nom, '/', 2) not like 'm' || v_m || '-%' then return false; end if;
  return public.envoyeur_autorise(v_dos::bigint, v_m);
end $$;

-- Ses propres fichiers de capture (lecture et suppression d'une capture annulée).
create function public.capture_a_moi(p_nom text) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare v_m bigint := public.mon_membre_lecteur();
begin
  return v_m is not null and split_part(p_nom, '/', 2) like 'm' || v_m || '-%';
end $$;

create function public.suppression_capture_autorisee(p_nom text) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare v_m bigint := public.mon_membre_lecteur();
begin
  if v_m is null or split_part(p_nom, '/', 2) not like 'm' || v_m || '-%' then return false; end if;
  return not exists (select 1 from public.captures where chemin = p_nom and statut <> 'annulee');
end $$;

-- =====================================================================
-- Membres : déclarer, annuler, envoyer et annuler une capture
-- =====================================================================
-- p : {debut (date et heure avec fuseau), resp_haavk (matricule), resp_gti (matricule)}
create function public.declarer_match_libre(p jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; s public.saisons%rowtype; v_debut timestamptz; v_h bigint; v_g bigint; v_delai int;
        v_bloques text[] := '{}'; v_champs text[] := '{}'; v_id bigint; v_match bigint; v_jour date;
begin
  m := public.mon_membre_actif();
  if coalesce(public.lire_param('matchs_libres_ouverts'), 'false'::jsonb) <> 'true'::jsonb then
    raise exception 'Les matchs libres ne sont pas encore ouverts.';
  end if;
  select * into s from public.saisons where active;
  if not found then raise exception 'Aucune saison en cours.'; end if;
  v_debut := nullif(p->>'debut', '')::timestamptz;
  if v_debut is null then raise exception 'Indiquez la date et l''heure de début.'; end if;
  v_delai := (public.lire_param('delai_declaration_h') #>> '{}')::int;
  if v_debut < clock_timestamp() + make_interval(hours => v_delai) then
    raise exception 'Un match libre se déclare au moins % h avant l''heure de début.', v_delai;
  end if;
  v_jour := (v_debut at time zone 'Indian/Antananarivo')::date;
  if v_jour < s.debut or v_jour > s.fin then raise exception 'Cette date est en dehors de la saison en cours.'; end if;
  select id into v_h from public.membres where matricule = nullif(p->>'resp_haavk', '')::int;
  if v_h is null then raise exception 'Responsable HAAVK : matricule introuvable.'; end if;
  select id into v_g from public.membres where matricule = nullif(p->>'resp_gti', '')::int;
  if v_g is null then raise exception 'Responsable GTI : matricule introuvable.'; end if;
  if not public.autorise_libre(m.id, s.id, v_debut) then v_bloques := v_bloques || ('organisateur DFMM-' || m.matricule); v_champs := v_champs || 'organisateur'::text; end if;
  if not public.autorise_libre(v_h, s.id, v_debut) then v_bloques := v_bloques || ('responsable HAAVK DFMM-' || (p->>'resp_haavk')); v_champs := v_champs || 'resp_haavk'::text; end if;
  if not public.autorise_libre(v_g, s.id, v_debut) then v_bloques := v_bloques || ('responsable GTI DFMM-' || (p->>'resp_gti')); v_champs := v_champs || 'resp_gti'::text; end if;
  if cardinality(v_champs) > 0 then
    insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut, statut, retenu_motif)
    values (s.id, m.id, v_h, v_g, v_debut, 'retenu', 'Matricule non autorisé : ' || array_to_string(v_bloques, ', ')) returning id into v_id;
    insert into public.journal (type, objet, decision) values ('Match libre', 'L-' || v_id, 'Demande retenue (matricule non autorisé) : à traiter');
    return jsonb_build_object('id', v_id, 'statut', 'retenu', 'champs', to_jsonb(v_champs));
  end if;
  insert into public.creneaux (saison_id, organisateur_id, resp_haavk_id, resp_gti_id, debut)
  values (s.id, m.id, v_h, v_g, v_debut) returning id into v_id;
  v_match := public.creer_match_libre(v_id);
  insert into public.journal (type, objet, decision) values ('Match libre', 'L-' || v_id, 'Match libre enregistré (M-' || v_match || ') par DFMM-' || m.matricule);
  return jsonb_build_object('id', v_id, 'statut', 'annonce', 'match', v_match);
end $$;

-- Annuler : l'organisateur jusqu'à l'heure de début, Katana à tout moment (motif facultatif).
create function public.annuler_creneau(p_creneau bigint, p_motif text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare c public.creneaux%rowtype; v_admin boolean := (select public.est_admin()); v_par text; v_motif text := nullif(trim(coalesce(p_motif, '')), '');
        v_match public.matchs%rowtype; v_txt text;
begin
  select * into c from public.creneaux where id = p_creneau for update;
  if not found then raise exception 'Match libre introuvable.'; end if;
  if c.statut not in ('annonce', 'retenu') then raise exception 'Ce match libre est déjà annulé ou refusé.'; end if;
  if v_admin then v_par := 'katana';
  else
    if c.organisateur_id <> (public.mon_membre_actif()).id then raise exception 'Seul l''organisateur peut annuler ce match libre.'; end if;
    if clock_timestamp() >= c.debut then raise exception 'L''heure de début est passée : écrivez à Katana pour annuler.'; end if;
    v_par := 'organisateur';
  end if;
  select * into v_match from public.matchs where creneau_id = c.id for update;
  if found then
    if v_match.statut = 'valide' then raise exception 'Ce match est déjà validé : annulez-le dans Administration > Matchs.'; end if;
    if v_match.statut <> 'annule' then
      update public.matchs set statut = 'annule', motif = coalesce(v_motif, 'Match libre annulé'), modifie_le = now() where id = v_match.id;
      insert into public.registre (match_id, type, detail) values (v_match.id, 'decision',
        'Match libre annulé par ' || case when v_par = 'katana' then 'Katana' else 'l''organisateur' end || coalesce(' — ' || v_motif, ''));
    end if;
  end if;
  update public.creneaux set statut = 'annule', annule_par = v_par, motif = v_motif, decide_le = clock_timestamp() where id = c.id;
  insert into public.journal (type, objet, decision, motif) values ('Match libre', 'L-' || c.id,
    'Annulé par ' || case when v_par = 'katana' then 'Katana' else 'l''organisateur' end, v_motif);
  if c.statut = 'annonce' then
    v_txt := 'Le match libre du ' || public.date_mg(c.debut) || ' est annulé' || case when v_par = 'katana' then ' par Katana' || coalesce(' : ' || v_motif, '') else ' par l''organisateur' end || '.';
    perform public.notifier(x, v_txt) from (select distinct unnest(array[c.organisateur_id, c.resp_haavk_id, c.resp_gti_id]) as x) t
     where v_par = 'katana' or x <> c.organisateur_id;
  end if;
end $$;

-- p_partie : « unique », ou « haut » et « bas » (au-delà de 8 joueurs par faction).
create function public.envoyer_capture(p_chemin text, p_partie text default 'unique') returns bigint
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; v_match bigint; v_id bigint;
begin
  m := public.mon_membre_actif();
  if coalesce(p_partie, '') not in ('unique', 'haut', 'bas') then raise exception 'Partie de capture inconnue.'; end if;
  if not public.depot_capture_autorise(p_chemin) then raise exception 'L''envoi des captures est fermé pour ce match.'; end if;
  v_match := split_part(p_chemin, '/', 1)::bigint;
  if not exists (select 1 from storage.objects where bucket_id = 'captures' and name = p_chemin) then
    raise exception 'Fichier introuvable : renvoyez la capture.';
  end if;
  if exists (select 1 from public.captures where match_id = v_match and envoyeur_id = m.id and statut = 'recue'
              and (partie = p_partie or partie = 'unique' or p_partie = 'unique')) then
    raise exception 'Vous avez déjà envoyé cette capture : annulez-la d''abord pour la remplacer.';
  end if;
  insert into public.captures (match_id, chemin, envoyeur_id, partie) values (v_match, p_chemin, m.id, p_partie) returning id into v_id;
  return v_id;
end $$;

-- Annuler sa capture pendant la période d'envoi (pour la renvoyer) ; renvoie le chemin du fichier à supprimer.
create function public.annuler_ma_capture(p_capture bigint) returns text
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; c public.captures%rowtype;
begin
  m := public.mon_membre_actif();
  select * into c from public.captures where id = p_capture and envoyeur_id = m.id and statut = 'recue' for update;
  if not found then raise exception 'Capture introuvable.'; end if;
  if not public.envoyeur_autorise(c.match_id, m.id) then raise exception 'La période d''envoi est terminée : la capture ne peut plus être annulée.'; end if;
  update public.captures set statut = 'annulee', motif = 'Annulée par l''envoyeur' where id = c.id;
  insert into public.registre (match_id, type, membre_id, detail) values (c.match_id, 'capture_annulee', m.id, 'Capture annulée par l''envoyeur');
  return c.chemin;
end $$;

-- Liste des matchs libres : annoncés (membres connectés) et ceux du membre (organisateur ou responsable).
create function public.liste_matchs_libres() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_m bigint := public.mon_membre_lecteur();
begin
  if v_m is null then raise exception 'Réservé aux membres.'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'debut', c.debut, 'fin_envoi', public.fin_envoi_captures(c.debut),
      'statut', c.statut,
      'organisateur', jsonb_build_object('matricule', o.matricule, 'nom_gamer', o.nom_gamer),
      'haavk', jsonb_build_object('matricule', h.matricule, 'nom_gamer', h.nom_gamer),
      'gti', jsonb_build_object('matricule', g.matricule, 'nom_gamer', g.nom_gamer),
      'moi_organisateur', c.organisateur_id = v_m, 'moi_haavk', c.resp_haavk_id = v_m, 'moi_gti', c.resp_gti_id = v_m,
      'match_id', mt.id, 'match_statut', mt.statut,
      'peut_envoyer', mt.id is not null and public.envoyeur_autorise(mt.id, v_m),
      'mes_captures', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'partie', x.partie, 'envoyee_le', x.envoyee_le, 'statut', x.statut) order by x.id)
                                  from public.captures x where x.match_id = mt.id and x.envoyeur_id = v_m and x.statut <> 'annulee'), '[]'::jsonb)
    ) order by c.debut desc)
    from public.creneaux c
    join public.membres o on o.id = c.organisateur_id join public.membres h on h.id = c.resp_haavk_id join public.membres g on g.id = c.resp_gti_id
    left join public.matchs mt on mt.creneau_id = c.id
    where c.debut > clock_timestamp() - interval '7 days'
      and (c.statut = 'annonce' or (c.statut = 'annule' and c.debut > clock_timestamp()) or c.organisateur_id = v_m
           or (c.statut = 'annule' and v_m in (c.resp_haavk_id, c.resp_gti_id)))
  ), '[]'::jsonb);
end $$;

-- =====================================================================
-- Katana : demandes retenues, alertes, lecture, retard accepté, captures identiques
-- =====================================================================
create function public.decider_creneau(p_creneau bigint, p_decision text, p_motif text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare c public.creneaux%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), ''); v_match bigint;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into c from public.creneaux where id = p_creneau for update;
  if not found then raise exception 'Match libre introuvable.'; end if;
  if c.statut <> 'retenu' then raise exception 'Cette demande n''est pas retenue.'; end if;
  if p_decision = 'accepter' then
    update public.creneaux set statut = 'annonce', motif = v_motif, decide_le = clock_timestamp(), vu_le = coalesce(vu_le, clock_timestamp()) where id = c.id;
    v_match := public.creer_match_libre(c.id);
    perform public.notifier(c.organisateur_id, 'Votre match libre du ' || public.date_mg(c.debut) || ' est enregistré.');
    insert into public.journal (type, objet, decision, motif) values ('Match libre', 'L-' || c.id, 'Demande retenue acceptée (M-' || v_match || ')', v_motif);
  elsif p_decision = 'refuser' then
    update public.creneaux set statut = 'refuse', motif = v_motif, decide_le = clock_timestamp(), vu_le = coalesce(vu_le, clock_timestamp()) where id = c.id;
    perform public.notifier(c.organisateur_id, 'Votre demande de match libre du ' || public.date_mg(c.debut) || ' n''a pas été retenue.');
    insert into public.journal (type, objet, decision, motif) values ('Match libre', 'L-' || c.id, 'Demande retenue refusée', v_motif);
  else raise exception 'Décision inconnue.';
  end if;
end $$;

create function public.marquer_creneaux_vus() returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  update public.creneaux set vu_le = clock_timestamp() where vu_le is null and statut <> 'retenu';
end $$;

create function public.noter_lecture(p_captures bigint[], p_lecture jsonb) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  update public.captures set lecture = p_lecture where id = any(p_captures);
end $$;

-- Retard accepté pour un échec technique prouvé (motif obligatoire).
create function public.accepter_capture_retard(p_capture bigint, p_motif text) returns void
language plpgsql security definer set search_path = ''
as $$
declare c public.captures%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), '');
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  if v_motif is null then raise exception 'Le motif est obligatoire (échec technique prouvé).'; end if;
  select * into c from public.captures where id = p_capture for update;
  if not found then raise exception 'Capture introuvable.'; end if;
  if c.statut not in ('recue', 'refusee') then raise exception 'Cette capture ne peut plus être acceptée.'; end if;
  if (select statut from public.matchs where id = c.match_id) not in ('brouillon', 'attente') then
    raise exception 'Repassez d''abord le match en brouillon.';
  end if;
  update public.captures set exception = v_motif, statut = 'recue', motif = null where id = c.id;
  insert into public.registre (match_id, type, membre_id, detail) values (c.match_id, 'capture_acceptee', c.envoyeur_id, 'Retard accepté (échec technique prouvé) : ' || v_motif);
  insert into public.journal (type, objet, decision, motif) values ('Match', 'M-' || c.match_id, 'Capture en retard acceptée', v_motif);
end $$;

-- Captures identiques : une seule conservée ; renvoie les fichiers à supprimer.
create function public.ecarter_captures(p_match bigint, p_captures bigint[], p_motif text) returns text[]
language plpgsql security definer set search_path = ''
as $$
declare v_st text; v_motif text := coalesce(nullif(trim(coalesce(p_motif, '')), ''), 'Capture identique : une seule conservée'); v_chemins text[];
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select statut into v_st from public.matchs where id = p_match;
  if v_st is null or v_st not in ('brouillon', 'attente') then raise exception 'Seul un brouillon ou un match en attente se modifie.'; end if;
  insert into public.registre (match_id, type, membre_id, detail)
    select p_match, 'capture_ecartee', envoyeur_id, v_motif from public.captures where match_id = p_match and id = any(p_captures) and statut = 'recue';
  select array_agg(chemin order by id) into v_chemins from public.captures where match_id = p_match and id = any(p_captures) and statut = 'recue';
  update public.captures set statut = 'ecartee', motif = v_motif where match_id = p_match and id = any(p_captures) and statut = 'recue';
  return coalesce(v_chemins, '{}');
end $$;

-- =====================================================================
-- Valider un match libre : chaque capture reçue plus de « delai_capture_min » minutes après l'heure de
-- fin (sans retard accepté) est rejetée seule ; le reste de decider_match est inchangé (migration 0007).
-- =====================================================================
create or replace function public.decider_match(p_match bigint, p_decision text, p_motif text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare m public.matchs%rowtype; v_motif text := nullif(trim(coalesce(p_motif, '')), ''); n int; v_lib text; v_delai int;
begin
  if not (select public.est_admin()) then raise exception 'Réservé à l''administrateur.'; end if;
  select * into m from public.matchs where id = p_match for update;
  if not found then raise exception 'Match introuvable.'; end if;
  if p_decision not in ('valider', 'attente', 'refuser', 'annuler', 'brouillon') then raise exception 'Décision inconnue.'; end if;
  if p_decision <> 'valider' and v_motif is null then raise exception 'Le motif est obligatoire.'; end if;

  if p_decision = 'valider' then
    if m.statut not in ('brouillon', 'attente') then raise exception 'Seul un brouillon ou un match en attente se valide.'; end if;
    if m.fin is null then raise exception 'Heure de fin du match manquante.'; end if;
    if m.type = 'libre' then
      if exists (select 1 from public.creneaux where id = m.creneau_id and statut <> 'annonce') then raise exception 'Le créneau de ce match libre est annulé.'; end if;
      v_delai := (public.lire_param('delai_capture_min') #>> '{}')::int;
      insert into public.registre (match_id, type, membre_id, detail)
        select m.id, 'capture_refusee', envoyeur_id, 'Hors délai : envoyée plus de ' || v_delai || ' min après l''heure de fin'
          from public.captures where match_id = m.id and statut = 'recue' and exception is null and envoyee_le > m.fin + make_interval(mins => v_delai);
      update public.captures set statut = 'refusee', motif = 'Hors délai'
       where match_id = m.id and statut = 'recue' and exception is null and envoyee_le > m.fin + make_interval(mins => v_delai);
    end if;
    select count(*) into n from public.captures where match_id = m.id and statut in ('recue', 'retenue');
    if n = 0 then
      if m.type = 'libre' then raise exception 'Aucune capture valable reçue à temps : refusez le match (motif : hors délai).'; end if;
      raise exception 'Ajoutez au moins une capture avant de valider.';
    end if;
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

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.creneaux enable row level security;
revoke all on public.creneaux from anon, authenticated;
grant select on public.creneaux to authenticated;
create policy "admin lit" on public.creneaux for select to authenticated using ((select public.est_admin()));
grant select, insert, update, delete on public.creneaux to service_role;

create policy "captures : dépôt par un responsable" on storage.objects for insert to authenticated
  with check (bucket_id = 'captures' and public.depot_capture_autorise(name));
create policy "captures : lecture de ses fichiers" on storage.objects for select to authenticated
  using (bucket_id = 'captures' and public.capture_a_moi(name));
create policy "captures : suppression d'une capture annulée" on storage.objects for delete to authenticated
  using (bucket_id = 'captures' and public.suppression_capture_autorisee(name));

revoke all on function public.autorise_libre(bigint, bigint, timestamptz), public.fin_envoi_captures(timestamptz),
  public.creer_match_libre(bigint), public.envoyeur_autorise(bigint, bigint) from public, anon, authenticated;
revoke all on function public.depot_capture_autorise(text), public.suppression_capture_autorisee(text), public.capture_a_moi(text),
  public.declarer_match_libre(jsonb), public.annuler_creneau(bigint, text), public.envoyer_capture(text, text),
  public.annuler_ma_capture(bigint), public.liste_matchs_libres(), public.decider_creneau(bigint, text, text),
  public.marquer_creneaux_vus(), public.noter_lecture(bigint[], jsonb), public.accepter_capture_retard(bigint, text),
  public.ecarter_captures(bigint, bigint[], text) from public, anon;
grant execute on function public.depot_capture_autorise(text), public.suppression_capture_autorisee(text), public.capture_a_moi(text),
  public.declarer_match_libre(jsonb), public.annuler_creneau(bigint, text), public.envoyer_capture(text, text),
  public.annuler_ma_capture(bigint), public.liste_matchs_libres(), public.decider_creneau(bigint, text, text),
  public.marquer_creneaux_vus(), public.noter_lecture(bigint[], jsonb), public.accepter_capture_retard(bigint, text),
  public.ecarter_captures(bigint, bigint[], text) to authenticated;

commit;
