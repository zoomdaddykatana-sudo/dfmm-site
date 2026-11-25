-- =====================================================================
-- LEAGUE UV — DFMM · Rattachement de Katana joueur (DFMM-6) à sa connexion administrateur
-- Décision de Katana du 25/11/2026 : Katana joue avec son matricule d'origine DFMM-6,
-- relié à SA connexion administrateur (pas de deuxième adresse e-mail).
--
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > coller > Run.
-- AVANT : remplacer seulement les 2 textes « TAPEZ_ICI_… » ci-dessous (entre les apostrophes).
-- Ne jamais enregistrer ce fichier avec vos vraies valeurs dans le dépôt ni les mettre dans un chat.
--
-- Ce que fait le script (tout ou rien : à la moindre erreur, rien n'est gardé) :
--  1. contrôle : 1 seul administrateur, DFMM-6 dans la liste des anciens et pas encore repris,
--     aucune fiche membre déjà reliée à la connexion administrateur, UID et lien Facebook valides ;
--  2. crée la candidature avec les fonctions normales du site (creer_inscription) :
--     e-mail repris de la connexion administrateur, empreintes codées comme le formulaire ;
--  3. l'approuve avec l'ancien matricule DFMM-6 (decider_inscription) : date d'origine 18/11/2026 à 0 h
--     (Madagascar), compte de jeu actif, premier pseudo à la même date, ligne au journal ;
--  4. affiche le résultat (nombres seulement).
-- Aucune règle changée. Le statut « hors concours » viendra ensuite (migration 0020).
-- =====================================================================
do $$
declare
  v_uid      text := 'TAPEZ_ICI_VOTRE_UID';             -- votre UID Delta Force (chiffres)
  v_facebook text := 'TAPEZ_ICI_VOTRE_LIEN_FACEBOOK';   -- lien de votre profil Facebook
  v_pseudo   text := 'DaddyKatana';                      -- pseudo actuel dans le jeu
  v_admin uuid; v_email text; v_fb text; v_fbid text; v_nom text; v_id bigint; v_mat integer;
  n_actifs integer; v_debut text;
begin
  -- ---------- 1. Contrôles ----------
  if (select count(*) from public.admins) <> 1 then raise exception 'Il faut exactement 1 administrateur.'; end if;
  select a.user_id into v_admin from public.admins a;
  select lower(btrim(u.email)) into v_email from auth.users u where u.id = v_admin;
  if coalesce(v_email, '') = '' then raise exception 'Connexion administrateur sans e-mail.'; end if;
  if exists (select 1 from public.membres where user_id = v_admin) then
    raise exception 'Une fiche membre est déjà reliée à la connexion administrateur.';
  end if;
  select nom_gamer into v_nom from public.matricules_anciens where matricule = 6 and repris_par is null;
  if not found then raise exception 'DFMM-6 absent de la liste des anciens, ou déjà repris.'; end if;

  -- UID : même nettoyage que le formulaire (espaces, caractères invisibles, « UID: », chiffres larges).
  v_uid := regexp_replace(normalize(v_uid, NFKC), '[[:space:]­᠎​-‏‪-‮⁠-⁩﻿]', '', 'g');
  v_uid := regexp_replace(v_uid, '^uid:?', '', 'i');
  if v_uid !~ '^[0-9]{5,25}$' then raise exception 'UID invalide : 5 à 25 chiffres.'; end if;

  -- Lien Facebook : même forme unique que le formulaire (normFacebook).
  v_fb := lower(regexp_replace(v_facebook, '^[[:space:]]+|[[:space:]]+$', '', 'g'));
  v_fb := regexp_replace(v_fb, '^https?://', '');
  v_fb := regexp_replace(v_fb, '^(www|m|web|mbasic)\.', '');
  v_fb := regexp_replace(v_fb, '^fb\.com', 'facebook.com');
  v_fbid := substring(v_fb from '^facebook\.com/profile\.php\?(?:.*&)?id=([0-9]+)');
  if v_fbid is not null then
    v_fb := 'facebook.com/profile.php?id=' || v_fbid;
  else
    v_fb := regexp_replace(split_part(split_part(v_fb, '?', 1), '#', 1), '/+$', '');
  end if;
  if v_fb !~ '^facebook\.com/[^[:space:]]+$' then raise exception 'Lien Facebook invalide.'; end if;

  -- ---------- 2. Candidature (fonction normale du site) ----------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_id := public.creer_inscription(jsonb_build_object(
    'user_id', v_admin, 'nom_gamer', coalesce(v_nom, 'Katana'), 'uid', v_uid, 'pseudo', v_pseudo,
    'email', v_email, 'facebook', v_fb,
    'empreinte_email', encode(sha256(convert_to(v_email, 'UTF8')), 'hex'),
    'empreinte_facebook', encode(sha256(convert_to(v_fb, 'UTF8')), 'hex'),
    'acceptations', jsonb_build_object('dfmm', true, 'league_uv', true, 'donnees', true, 'approbation', true,
                                       'date', now(), 'rattachement_admin', true)));

  -- ---------- 3. Approbation avec l'ancien matricule DFMM-6 ----------
  v_mat := public.decider_inscription(v_id, 'approuver',
    'Rattachement de l''administrateur joueur à DFMM-6 (décision de Katana du 25/11/2026)', 6);

  -- ---------- 4. Résultat (nombres seulement) ----------
  select count(*) into n_actifs from public.comptes_jeu where membre_id = v_id and statut = 'actif';
  select to_char(min(debut) at time zone 'Indian/Antananarivo', 'DD/MM/YYYY HH24:MI') into v_debut
  from public.periodes where membre_id = v_id;
  raise notice 'FAIT : DFMM-% actif, relié à la connexion administrateur, % compte(s) de jeu actif(s), période depuis le % (Madagascar).',
    v_mat, n_actifs, v_debut;
end $$;
