-- =====================================================================
-- LEAGUE UV — DFMM · Rappels : correction du bilan des envois · migration 0022
-- Constat du 25/11/2026 (premier essai réel, notification bien reçue) : le journal de la fonction « rappels » dit
-- « rappels_resultats : UPDATE requires a WHERE clause ». Supabase refuse, pour les appels venant de l'API (rôle
-- serveur compris), toute modification sans condition WHERE. Conséquence : le bilan des envois n'était pas noté et
-- un téléphone désinscrit (réponse 404 ou 410) n'aurait jamais été oublié. Correction : « where id » ajouté aux
-- 2 modifications de la ligne unique de prive.rappels_config (rappels_resultats et, par prudence, rappels_reveil).
-- Aucune règle changée, aucune donnée modifiée. Le reste des 2 fonctions est identique à la migration 0020.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- =====================================================================
begin;

create or replace function public.rappels_reveil() returns text
language plpgsql security definer set search_path = ''
as $$
declare c prive.rappels_config%rowtype;
begin
  select * into c from prive.rappels_config;
  if not found then return 'sans réglage'; end if;
  delete from public.rappels_envoyes where envoye_le < clock_timestamp() - interval '30 days';
  -- Journal de pg_cron (une ligne par minute) : 7 jours gardés ; nettoyé une fois par heure.
  if extract(minute from clock_timestamp())::int = 0 and to_regclass('cron.job_run_details') is not null then
    begin
      execute 'delete from cron.job_run_details where end_time < now() - interval ''7 days''';
    exception when others then null;
    end;
  end if;
  -- Téléphones de personnes qui ne sont plus membres actifs (retrait, exclusion, effacement) : oubliés.
  delete from public.abonnements_push a where not public.rappels_autorise(a.user_id);
  if public.lire_param('rappels_actifs') is distinct from 'true'::jsonb then return 'rappels arrêtés'; end if;
  perform public.calendrier_preparer();
  if c.vapid_public is null then
    -- Clé pas encore créée : un appel toutes les 10 minutes au plus, pour que la fonction la crée.
    if c.dernier_reveil is not null and c.dernier_reveil > clock_timestamp() - interval '10 minutes' then return 'clé en attente'; end if;
  elsif not exists (select 1 from public.rappels_dus()) then
    return 'rien à envoyer';
  end if;
  update prive.rappels_config set dernier_reveil = clock_timestamp() where id;
  perform net.http_post(url := c.url_fonction, body := '{}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-rappels-cle', c.secret),
                        timeout_milliseconds := 30000);
  return 'fonction appelée';
end $$;

create or replace function public.rappels_resultats(p jsonb) returns void
language plpgsql security definer set search_path = ''
as $$
declare e jsonb; k text; v_ok int := 0; v_ko int := 0; v_oublies int := 0; v_http int;
begin
  for e in select * from jsonb_array_elements(coalesce(p->'envois', '[]'::jsonb)) loop
    v_http := nullif(e->>'http', '')::int;
    if v_http between 200 and 299 then
      v_ok := v_ok + 1;
      update public.abonnements_push set dernier_envoi = clock_timestamp(), echecs = 0, derniere_erreur = null where id = (e->>'id')::bigint;
    elsif v_http in (404, 410) then
      v_oublies := v_oublies + 1;
      delete from public.abonnements_push where id = (e->>'id')::bigint;
    else
      v_ko := v_ko + 1;
      update public.abonnements_push set echecs = echecs + 1, derniere_erreur = left(coalesce(v_http::text, 'pas de réponse'), 100)
       where id = (e->>'id')::bigint;
    end if;
  end loop;
  -- Téléphone en échec 20 fois de suite : oublié.
  delete from public.abonnements_push where echecs >= 20;
  for k in select jsonb_object_keys(coalesce(p->'cles', '{}'::jsonb)) loop
    update public.rappels_envoyes set destinataires = (p->'cles'->>k)::int where cle = k;
  end loop;
  update prive.rappels_config set dernier_envoi = clock_timestamp(),
         dernier_bilan = jsonb_build_object('le', clock_timestamp(), 'envoyes', v_ok, 'echecs', v_ko, 'oublies', v_oublies,
                                            'messages', (select count(*) from jsonb_object_keys(coalesce(p->'cles', '{}'::jsonb))))
   where id;
end $$;

revoke all on function public.rappels_reveil(), public.rappels_resultats(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.rappels_resultats(jsonb) to service_role;

commit;
