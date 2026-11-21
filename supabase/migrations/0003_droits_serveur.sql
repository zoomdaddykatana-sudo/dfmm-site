-- =====================================================================
-- LEAGUE UV — DFMM · migration 0003 · droits du rôle serveur
-- Les fonctions serveur (inscription, lien de réinitialisation) utilisent
-- le rôle « service_role ». Sur les projets Supabase récents, ce rôle ne
-- reçoit plus automatiquement de droits sur les nouvelles tables : il ne
-- pouvait donc pas lire le réglage « Inscriptions ouvertes ».
-- Cette migration lui donne les droits nécessaires. Elle ne change rien
-- pour les visiteurs ni pour les membres, et ne touche à aucune donnée.
-- =====================================================================
begin;
grant usage on schema public to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
-- Les tables créées par les prochaines migrations recevront ces droits d'office.
alter default privileges in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to service_role;
commit;
