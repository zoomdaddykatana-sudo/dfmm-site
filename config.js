/* Configuration publique du site LEAGUE UV (DFMM).
   Ces deux valeurs sont faites pour être lues par le navigateur :
   la protection des données repose sur les règles d'accès Supabase (RLS).
   Ne jamais mettre ici la clé secrète Supabase ni la clé volsever :
   elles vont uniquement dans les secrets de Supabase. */
window.DFMM_CONFIG = Object.freeze({
  supabaseUrl: 'https://ijpbplzbjohfrqwnvrqv.supabase.co',
  supabasePublishableKey: 'sb_publishable_L6BFesjVJmnSyGTB4BXFQQ_Iz6quPmx'
});
