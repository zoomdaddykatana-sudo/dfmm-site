-- =====================================================================
-- LEAGUE UV — DFMM · Lot 2C « pseudo avec volsever et effacement » · migration 0005
-- À exécuter UNE fois dans Supabase. Ne supprime rien : ajoute 4 paramètres,
-- une table (journal des appels à volsever) et des fonctions.
-- =====================================================================
begin;

-- ---------- Paramètres réglables de volsever ----------
insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('volsever_max_jour',   '45', 'entier', 'Appels à volsever autorisés sur 24 heures',            'Volsever', 1),
  ('volsever_max_minute', '15', 'entier', 'Appels à volsever autorisés par minute',               'Volsever', 2),
  ('volsever_delai_s',    '15', 'entier', 'Attente maximum d''une réponse de volsever (secondes)', 'Volsever', 3),
  ('volsever_alerte_pct', '80', 'entier', 'Alerte quand ce pourcentage de la limite est atteint', 'Volsever', 4);

-- ---------- Journal des appels à volsever (compteur ; administrateur seulement) ----------
create table public.volsever_appels (
  id            bigint generated always as identity primary key,
  cree_le       timestamptz not null default clock_timestamp(),
  compte_id     bigint references public.comptes_jeu(id) on delete set null,
  resultat      text not null check (resultat in ('trouve','introuvable','erreur','delai','quota')),
  pseudo_trouve text,
  http          integer
);
create index volsever_appels_date on public.volsever_appels (cree_le);

-- ---------- Déclaration de pseudo : résultat de volsever (appelée par la fonction serveur) ----------
-- Le pseudo trouvé par volsever remplace toujours l'actuel. S'il diffère du pseudo tapé : notification
-- et demande de vérification pour Katana. Sans réponse utilisable : demande en attente, validation à la main.
create function public.enregistrer_declaration_pseudo(p_user uuid, p_compte bigint, p_tape text, p_resultat text, p_trouve text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; c public.comptes_jeu%rowtype; v_mod boolean; v_tape text := trim(coalesce(p_tape, '')); v_raison text;
begin
  select * into m from public.membres where user_id = p_user;
  if not found or m.statut <> 'actif' then raise exception 'Cette démarche est réservée aux membres actifs.'; end if;
  select * into c from public.comptes_jeu where id = p_compte and membre_id = m.id for update;
  if not found then raise exception 'Ce compte n''est pas à vous.'; end if;
  if c.statut = 'remplace' then raise exception 'Ce compte est remplacé.'; end if;
  if v_tape = '' then raise exception 'Le nouveau pseudo est obligatoire.'; end if;
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

-- ---------- Effacement des données personnelles (décision Q10) ----------
create function public.demander_effacement() returns bigint
language plpgsql security definer set search_path = ''
as $$
declare m public.membres%rowtype; v_id bigint;
begin
  select * into m from public.membres where user_id = (select auth.uid());
  if not found then raise exception 'Aucune fiche membre liée à ce compte.'; end if;
  if m.donnees_effacees then raise exception 'Vos données sont déjà effacées.'; end if;
  if exists (select 1 from public.demandes where membre_id = m.id and type = 'effacement' and statut in ('en_attente', 'precisions')) then
    raise exception 'Une demande d''effacement est déjà en cours.';
  end if;
  insert into public.demandes (membre_id, type, details) values (m.id, 'effacement', '{}'::jsonb) returning id into v_id;
  insert into public.journal (type, objet, decision) values ('Demande', coalesce('DFMM-' || m.matricule, m.id::text), 'Demande d''effacement des données reçue');
  return v_id;
end $$;

-- Efface : nom réel, date de naissance, genre, résidence, langues, e-mail, lien Facebook, capture du profil.
-- Garde : empreintes de l'e-mail et du lien Facebook, UID, pseudos, matricule, statistiques.
-- Renvoie le compte de connexion et les captures à supprimer (fait ensuite par la fonction serveur).
create function public.effacer_donnees_membre(p_demande bigint) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare d public.demandes%rowtype; m public.membres%rowtype; v_captures text[];
begin
  select * into d from public.demandes where id = p_demande for update;
  if not found or d.type <> 'effacement' then raise exception 'Demande d''effacement introuvable.'; end if;
  if d.statut not in ('en_attente', 'precisions') then raise exception 'Cette demande a déjà été traitée.'; end if;
  select * into m from public.membres where id = d.membre_id for update;
  select array_remove(array_agg(distinct x), null) into v_captures from (
    select capture_profil as x from public.membres_prives where membre_id = m.id
    union all
    select details->>'capture' from public.demandes where membre_id = m.id and type = 'compte2') t;
  update public.membres_prives set nom_reel = null, date_naissance = null, genre = null, residence = null, province = null,
    zone = null, pays = null, comprend_mg = null, parle_mg = null, email = null, facebook = null, capture_profil = null,
    modifie_le = clock_timestamp()
  where membre_id = m.id;
  update public.demandes set details = details - 'capture' where membre_id = m.id and type = 'compte2';
  update public.membres set donnees_effacees = true where id = m.id;
  update public.demandes set statut = 'acceptee', decide_le = clock_timestamp(), motif_decision = 'Données personnelles effacées' where id = d.id;
  insert into public.journal (type, objet, decision)
  values ('Données', coalesce('DFMM-' || m.matricule, m.id::text), 'Données personnelles effacées sur demande ; accès fermé');
  return jsonb_build_object('user_id', m.user_id, 'captures', coalesce(to_jsonb(v_captures), '[]'::jsonb));
end $$;

-- =====================================================================
-- Règles d'accès
-- =====================================================================
alter table public.volsever_appels enable row level security;
revoke all on public.volsever_appels from anon, authenticated;
grant select on public.volsever_appels to authenticated;
create policy "admin lit" on public.volsever_appels for select to authenticated using ((select public.est_admin()));
grant select, insert, update, delete on public.volsever_appels to service_role;

revoke all on function public.enregistrer_declaration_pseudo(uuid, bigint, text, text, text), public.effacer_donnees_membre(bigint)
  from public, anon, authenticated;
grant execute on function public.enregistrer_declaration_pseudo(uuid, bigint, text, text, text), public.effacer_donnees_membre(bigint) to service_role;
revoke all on function public.demander_effacement() from public, anon;
grant execute on function public.demander_effacement() to authenticated;

commit;
