-- =====================================================================
-- LEAGUE UV — DFMM · Fin de saison et phase de démarrage · migration 0006
-- Décisions de Katana du 21/11/2026 :
--   - les matchs comptent jusqu'à la fin officielle de la saison de Delta Force (pas de gel avant la fin) ;
--   - vérification pendant 48 h après la fin, puis classement final publié le premier dimanche
--     qui suit la fin de cette vérification ;
--   - « Phase de démarrage » : réglage oui/non ; tant qu'il est sur oui, seuls les matchs de Katana
--     comptent, saisis avec sa seule capture, sans délai de 10 minutes.
-- À exécuter UNE fois dans Supabase. Retire un seul paramètre (« classement_final_jours »,
-- jamais modifié, aucun historique) et en ajoute deux.
-- =====================================================================
begin;

delete from public.parametres where cle = 'classement_final_jours';

insert into public.parametres (cle, valeur, type, libelle, section, ordre) values
  ('verification_finale_h', '48',   'entier',  'Vérification après la fin de saison, avant le classement final (h)', 'Classements', 5),
  ('phase_demarrage',       'true', 'booleen', 'Phase de démarrage (seuls les matchs de Katana, sans délai de 10 min)', 'Site', 4);

commit;
