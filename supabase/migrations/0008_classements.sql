-- =====================================================================
-- LEAGUE UV — DFMM · Classements publiés · migration 0008
-- Un classement publié est figé : numéro attribué par la base (provisoire n° 1, 2…), un seul
-- classement final par saison, heure de publication du serveur, aucune modification ni suppression
-- après coup, publication notée au journal. À exécuter UNE fois dans Supabase. Ne supprime rien
-- (la table « publications » est vide) : ajoute 2 index, 2 contrôles et leurs déclencheurs.
-- =====================================================================
begin;

create unique index publications_numero on public.publications (saison_id, type, numero) where numero is not null;
create unique index publications_un_final on public.publications (saison_id) where type = 'final';

-- Numéro, heure et journal fixés par la base, jamais par le téléphone.
create function public.publications_avant_ajout() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_nom text;
begin
  select nom into v_nom from public.saisons where id = new.saison_id;
  if v_nom is null then raise exception 'Saison introuvable.'; end if;
  if new.type = 'final' and exists (select 1 from public.publications where saison_id = new.saison_id and type = 'final') then
    raise exception 'Le classement final de cette saison est déjà publié.';
  end if;
  if new.type = 'provisoire' then
    select coalesce(max(numero), 0) + 1 into new.numero from public.publications where saison_id = new.saison_id and type = 'provisoire';
  else
    new.numero := null;
  end if;
  new.publie_le := clock_timestamp();
  if new.coupure > new.publie_le then raise exception 'La coupure ne peut pas être après la publication.'; end if;
  insert into public.journal (type, objet, decision, motif)
  values ('Publication', v_nom, case when new.type = 'final' then 'Classement final publié' else 'Classement provisoire n° ' || new.numero || ' publié' end,
          'Coupure : ' || to_char(new.coupure at time zone 'Indian/Antananarivo', 'DD/MM/YYYY HH24:MI') || ' (heure de Madagascar)');
  return new;
end $$;
create trigger publications_avant_ajout before insert on public.publications
for each row execute function public.publications_avant_ajout();

create function public.publications_figees() returns trigger
language plpgsql set search_path = ''
as $$ begin raise exception 'Un classement publié ne se modifie pas et ne se supprime pas.'; end $$;
create trigger publications_figees before update or delete on public.publications
for each row execute function public.publications_figees();

revoke all on function public.publications_avant_ajout(), public.publications_figees() from public, anon, authenticated;

commit;
