-- =====================================================================
-- LEAGUE UV — DFMM · Délai de traitement des inscriptions · migration 0019
-- Demande de Katana du 23/11/2026 (suite de l'audit) : annoncer le délai de traitement à ceux qui
-- finissent l'inscription. Le site l'affiche après l'envoi et dans « Mon compte » (inscription en attente).
-- Réglable dans Administration > Paramètres > Site ; 0 = aucun délai affiché.
-- À exécuter UNE fois dans Supabase : SQL Editor > New query > Run.
-- Ne supprime rien : ajoute 1 réglage.
-- =====================================================================
begin;

insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('delai_traitement_h', '48', 'entier', 'Délai de traitement des inscriptions annoncé aux joueurs (h, 0 = rien affiché)', 'Site', 6);

commit;
