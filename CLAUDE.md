# CLAUDE.md — reprise du projet DFMM / LEAGUE UV

À lire en entier au début de chaque session. État au 21/11/2026.

## 1. Le projet

- **DFMM** (Delta Force Mobile Madagascar) : site et application installable de la **LEAGUE UV**, ligue communautaire. Dépôt : `zoomdaddykatana-sudo/dfmm-site` (public).
- **Administrateur unique : Katana.** Il est débutant. Toujours : français simple, une action à la fois, chemin exact de clics (téléphone ou ordinateur), résultat attendu après chaque étape.
- Écritures à respecter : DFMM, LEAGUE UV, HAAVK, GTI, MOST, BEST, BEST Survivor, TDM, ES, PKL, DFMM-1 (sans année ni zéros).
- Technique : une page `index.html` (HTML, CSS, JavaScript sans outil de construction), règles de calcul dans `js/regles.js`, base **Supabase**, hébergement **GitHub Pages**.

## 2. Où sont les décisions

- **Source de vérité :** le cahier « LEAGUE UV — Règles et sanctions » (version du 21/11/2026), un Claude Doc : https://claude.ai/code/artifact/ad635088-b995-4405-b9fe-3e8089866423. Le lire avant de coder ; ne jamais inventer de règle. Si le cahier est muet ou contradictoire : demander à Katana.
- **Décisions prises après le cahier** (à reporter dans le règlement à la fin de la conception) :
  - Égalité parfaite : co-lauréats, titre partagé, lot de la catégorie non attribué ; égalité entre bénéficiaires d'une redistribution : lot non attribué.
  - Suspendus à la date de la coupure : hors médiane, Q1 et titres ; ils reviennent ensuite.
  - Seuil de 50 % : « membre confirmé » = ligne qui rapporte des points (membre actif, non suspendu, compte actif, ligne vérifiée).
  - Coupure : capture envoyée avant 16 h = classement du dimanche, même validée après ; match en attente tranché ou ligne identifiée après 16 h = classement suivant ; match de Katana compté s'il est validé avant la publication. Classement final : décisions comptées jusqu'à la publication.
  - Seuils des alertes de performance : paramètres réglables.
  - Matchs de Katana : en général mercredi et samedi à 16 h (jours habituels, pas de calendrier automatique), dits « programmés » ; étiquette « Katana » ; plus d'alerte « un match par session ».
  - Match libre : enregistré automatiquement avec alerte pour Katana, qui peut l'annuler ; déclaration au moins 2 h avant ; matchs libres fermés (réglage) jusqu'au lancement ; « heure annoncée » = heure de début ; motif facultatif.
  - Avant le lancement : seuls les matchs de Katana comptent, saisis avec sa seule capture, sans délai de 10 min, mention « saisie de démarrage » ; autres règles inchangées.
  - Consignes de salon (escouades…) : simple rappel, sans limite de participants.
  - Effacement des données : nom réel, date de naissance, genre, résidence, langues, e-mail, lien Facebook effacés ; empreinte codée de l'e-mail et du lien Facebook gardée ; UID, pseudos, matricule, statistiques gardés ; l'accès est fermé.
  - Pseudo : le joueur choisit son UID et tape son nouveau pseudo ; volsever lit le pseudo, qui remplace toujours l'actuel ; écart = notification + vérification par Katana ; volsever muet = en attente, validation à la main.
  - Réclamation sur un classement publié : gardée, par la messagerie, 48 h.
  - Inscription : « demander des précisions » et la case « Je comprends que mon inscription doit être approuvée » gardées.
  - Couleurs : ambre remplacé par le rouge #E53935 ; gris en tertiaire seulement. Icône : tête du logo original recadrée. Hashtag : « #LeagueUV » gardé.
  - Pas d'API Claude pour l'instant : Katana fait lire les captures dans claude.ai et colle les données dans l'écran de vérification (format à lui fournir au lot 3).
  - Pas d'e-mail aux joueurs, pas de confirmation d'adresse ; mot de passe oublié = lien créé par Katana (Administration > Accès des joueurs), envoyé par Messenger.
  - Anciens membres : DFMM-1 à DFMM-25 (approuvés les 18 et 19/11/2026), importés dans `matricules_anciens` (date seule) ; à la réinscription, ils gardent leur matricule et leur date d'origine à 0 h (Madagascar). Nouveaux membres : à partir de DFMM-26. Les 2 lignes sans matricule du fichier d'origine ne sont pas des membres. Le caractère « 么 » des pseudos TDM est gardé tel quel.

## 3. État d'avancement

| Lot | Contenu | État |
|---|---|---|
| 0 Socle | Supabase, connexion, paramètres, application installable | Fusionné (PR n° 1) |
| 1 Calculs | Règles de classement conformes au cahier, 24 tests | Fusionné (PR n° 2) |
| 2A Inscriptions | Inscription, approbation, reprise des anciens matricules, membres, sauvegarde ; migrations 0002 et 0003 | Fusionné (PR n° 3) |
| 2B Comptes et demandes | 2e compte, compte actif, retrait, réintégration, notifications, onglet Demandes, fiche membre ; migration 0004 | **PR n° 4 ouverte** : migration 0004 exécutée et test 0004 réussi (27/27) dans le vrai projet le 21/11/2026 ; reste la vérification sur téléphone et l'accord de Katana pour fusionner |
| 2C | Pseudo avec volsever ; effacement des données | À faire |
| 3 | Matchs et captures, registre | À faire |
| 4 | Litiges, sanctions, captures écartées | À faire |
| 5 | Textes et pages (règlement, processus, actualités, messagerie, couleurs) | À faire ; proposer les textes à Katana avant de réécrire |

Points en suspens :
- Nettoyage de la fausse fiche « EssaiTest » et du compte `essai1@dfmm.invalid` : fait, vérifié le 21/11/2026 (0 fiche, 0 compte).
- Mise à jour du règlement du site (lot 5) et du guide PDF (ne pas toucher au PDF).
- Message de réinscription pour les 25 membres déjà approuvés : à rédiger.
- Sauvegarde : bouton dans Administration > Sauvegarde ; à faire chaque semaine (pas de sauvegarde automatique).

## 4. Règles de travail

- **Jamais** de clé secrète, de mot de passe ou de donnée personnelle dans le dépôt, les commits, les PR ou le chat. Côté site : seulement l'URL et la clé publishable (`config.js`). Les clés secrètes (service_role, volsever) sont dans les secrets Supabase, placées par Katana.
- Toute requête SQL sur le vrai projet est **présentée à Katana avant exécution**, avec le résultat attendu. Jamais d'UPDATE ou de DELETE sans clause WHERE. Aucune suppression de donnée, compte ou fichier réel sans sa confirmation écrite. Aucun changement des réglages de sécurité (inscriptions, confirmation, droits) sans sa confirmation.
- Ne pas lire les données personnelles réelles : tester avec de faux membres, ne rapporter que des nombres.
- Chaque lot : branche `ccr-08840471-84tqcu` repartie de `main`, petits commits, tests, PR, puis validation de Katana. **Ne jamais fusionner sans son accord écrit** (« fusionne la PR n° X »).
- **Ne pas supprimer la branche `ccr-08840471-84tqcu`** : GitHub Pages la publie. Rappeler à Katana de ne pas cocher « Delete branch ».
- Le site en ligne est la **version de test** (bandeau rouge) : ne pas ouvrir les inscriptions ni les matchs libres sans demande écrite.
- Tout paramètre de la section 10 du cahier est réglable dans la table `parametres` (Administration > Paramètres) : rien en dur.

## 5. Infos de référence

- Site : https://zoomdaddykatana-sudo.github.io/dfmm-site/ (Pages publie la branche `ccr-08840471-84tqcu`).
- Supabase : projet `ijpbplzbjohfrqwnvrqv` (URL et clé publishable dans `config.js`, rien d'autre). Fonctions installées : `lien-reinitialisation`, `inscription`. Secret déjà rangé : `VOLSEVER_API_KEY`.
- Migrations (`supabase/migrations/`) : 0001 à 0004 exécutées dans le vrai projet. Chaque migration a son test dans `supabase/tests/` (il finit par un message rouge « FIN DU TEST » voulu, qui annule tout).
- Forfait gratuit Supabase : pause après 1 semaine sans activité, pas de sauvegarde automatique, 1 Go de fichiers, envoi d'e-mails limité à 2 par heure et aux membres de l'équipe du projet.
- volsever : `GET https://gate.volsever.com/proxy/api/game/delta-force?id={UID}` ; réponse `data.username` ; environ 5 s ; forfait gratuit 45 requêtes par jour et 15 par minute ; mode d'envoi de la clé (en-tête ou paramètre) à vérifier dans sa documentation.
- Pseudo et tag de clan : « ¬ » est un tag de clan validé, à conserver et comparer tel quel.
- Environnement cloud « dfmm-site » : hôtes autorisés `ijpbplzbjohfrqwnvrqv.supabase.co` et `supabase.com`.
- Connecteur « Supabase DFMM » (limité au projet, outils base, journal et documentation ; pas d'outil de compte). Le connecteur standard « Supabase » (accès à tout le compte) est déconnecté : ne pas l'utiliser. Chaque requête : SQL et résultat attendu montrés à Katana, puis son « oui » écrit, puis le message exact de Supabase rapporté.
- Tests locaux : `node --test tests/*.test.js` (29 tests) ; base imitée : PostgreSQL 16 avec `supabase/tests/emulation_locale.sql`, puis les migrations dans l'ordre, puis les fichiers de test.

## 6. Pièges déjà rencontrés

- Fonction Supabase : le nom se choisit à la création ; le fichier reste `index.ts`.
- E-mails : le service intégré de Supabase n'écrit qu'aux membres de l'équipe du projet ; jamais de confirmation par e-mail, utiliser le lien de réinitialisation envoyé par Messenger.
- La fonction `inscription` doit avoir « Verify JWT » désactivé.
- Les projets Supabase récents ne donnent aucun droit automatique au rôle `service_role` : chaque nouvelle table doit lui être accordée (migration 0003 règle les tables existantes et les suivantes) ; la base locale de test imite ce comportement.
- Une même opération SQL a une seule valeur de `now()` : pour des dates de début et de fin dans une même opération, utiliser `clock_timestamp()`.
- Le compteur des matricules ne revient jamais en arrière : un test ne doit pas approuver avec un nouveau matricule dans le vrai projet sans remettre le compteur (voir les tests 0002 et 0004).
- Aucune valeur de test dans la vraie base sans nettoyage vérifié ; utiliser des matricules fictifs (99xxx) et des adresses `@test.invalid`.
- Le lien de réinitialisation doit être écouté dès le chargement de la page (bug corrigé au lot 0).

## 7. Prochaine étape

1. Demander à Katana s'il a vérifié la PR n° 4 sur son téléphone (onglet Demandes, bouton Ouvrir dans Membres).
2. Si Katana écrit « fusionne la PR n° 4 » : vérifier, fusionner, puis repartir de `main` sur la branche `ccr-08840471-84tqcu`.
3. Commencer le lot 2C :
   - lire d'abord la documentation de volsever (mode d'envoi de la clé ; ajouter l'hôte à l'environnement si besoin) ;
   - puis coder le pseudo (compteur d'appels, délai d'attente, repli manuel) et l'effacement (décision Q10).
