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
  - Saisons : elles portent le nom de la saison du jeu (par exemple « Aurora ») ; les matchs comptent jusqu'à la fin officielle de la saison de Delta Force, sans gel avant la fin ; vérification pendant 48 h après la fin (réglage `verification_finale_h`), puis classement final publié le premier dimanche qui suit la fin de ces 48 h (fin un samedi → vérification jusqu'au lundi → dimanche d'après). Remplace « 7 jours après la fin ».
  - Phase de démarrage : réglage `phase_demarrage` (oui/non, Administration > Paramètres), passé à « non » par Katana le jour du lancement.
  - Matchs déjà joués : tous à saisir (saisie de démarrage) ; Katana a toutes les captures.
  - Réinscription des 25 anciens membres : par e-mail depuis le Gmail de Katana (exception à « pas d'e-mail aux joueurs »), avec `outils/envoi-reinscription.gs` (Google Apps Script) et une feuille Google qu'il remplit lui-même (adresses dans l'ancien classeur ; jamais dans le dépôt ni le chat). Texte du message validé le 21/11/2026. Envoi seulement après ouverture des inscriptions (demande écrite « ouvre les inscriptions »).
  - Anciens membres : DFMM-1 à DFMM-25 (approuvés les 18 et 19/11/2026), importés dans `matricules_anciens` (date seule) ; à la réinscription, ils gardent leur matricule et leur date d'origine à 0 h (Madagascar). Nouveaux membres : à partir de DFMM-26. Les 2 lignes sans matricule du fichier d'origine ne sont pas des membres. Le caractère « 么 » des pseudos TDM est gardé tel quel.

## 3. État d'avancement

| Lot | Contenu | État |
|---|---|---|
| 0 Socle | Supabase, connexion, paramètres, application installable | Fusionné (PR n° 1) |
| 1 Calculs | Règles de classement conformes au cahier, 24 tests | Fusionné (PR n° 2) |
| 2A Inscriptions | Inscription, approbation, reprise des anciens matricules, membres, sauvegarde ; migrations 0002 et 0003 | Fusionné (PR n° 3) |
| 2B Comptes et demandes | 2e compte, compte actif, retrait, réintégration, notifications, onglet Demandes, fiche membre ; migration 0004 | Fusionné (PR n° 4) ; migration 0004 exécutée, test 27/27 |
| 2C | Pseudo avec volsever (compteur d'appels, repli manuel) ; effacement des données ; migration 0005 ; fonctions `pseudo-volsever` et `effacer-donnees` | Fusionné (PR n° 6) ; migration 0005 exécutée, test 21/21 dans le vrai projet ; 2 fonctions installées (« Verify JWT » activé) ; écrans administrateur vérifiés sur téléphone le 21/11/2026 |
| 3 | Matchs et captures, registre | 3A (matchs de Katana) : **fusionné (PR n° 8)** le 21/11/2026 ; migration 0006 exécutée (test 8/8) ; migration 0007 (matchs, lignes, captures, registre, stockage « captures », colonne `saisons.fin_confirmee`) exécutée et test 0007 réussi (23/23) dans le vrai projet le 21/11/2026 ; onglets Saison et Matchs branchés sur Supabase. 3B (matchs libres : créneaux, captures des responsables, délai de 10 min, concordance, attente) à faire |
| 3C Classements | Onglet Administration > Classements branché sur Supabase (calcul sur les matchs validés, contrôle avant publication, publication figée) ; page publique et accueil lisent `publications` ; migration 0008 (numéro automatique, un seul final, classement figé, journal) | **Fusionné (PR n° 9)** le 21/11/2026 ; migration 0008 exécutée et test 0008 réussi (11/11) dans le vrai projet le 21/11/2026 ; premier provisoire d'Aurora renseigné (29/11/2026) |
| 4A Sanctions | Avertissement, suspension (≤ 14 j, dernier jour inclus fixé par Katana), exclusion, retrait des statistiques d'un joueur dans un match ; recours 48 h (contestation dans Mon compte) ; levée = matchs recomptés ; démarches bloquées pendant une suspension ; retrait soumis à Katana si sanction ou match en attente ; migration 0009 | **Fusionné (PR n° 10)** ; migration 0009 exécutée et test 0009 réussi (21/21) dans le vrai projet le 21/11/2026 |
| 4B Litiges | Dossier ouvert tout seul pour chaque match en attente ; qualification ; convocations (confirmation sous 12 h) et témoins ; discussion confidentielle (Katana et convoqués) ; décision (vraie capture / match refusé / annulé) qui ferme la discussion ; sanctions liées ; export pour une synthèse par claude.ai validée puis archivée ; suppression des captures écartées (tout de suite sans sanction, après le recours avec sanction) ; migration 0010 | **Fusionné (PR n° 10, avec 4A)** ; migration 0010 exécutée et test 0010 réussi (23/23) dans le vrai projet le 21/11/2026 |
| Titres et lots | Onglet Administration > Titres et lots : lots de la saison (description, confirmé), prévision d'attribution sur les matchs validés, attribution enregistrée sur le classement final publié (figé), remise ; jamais publiés ; migration 0011 | **PR n° 11 ouverte** ; migration 0011 exécutée et test 0011 réussi (12/12) dans le vrai projet le 21/11/2026 |
| 5 | Textes et pages (règlement, processus, actualités, messagerie, couleurs) | En cours : 14 corrections de textes faux (50 %, 10 min, coupure 16 h selon l'heure d'envoi, fin de saison 48 h, co-lauréats, ordre des lots Objective avant Tactician, matchs de Katana, matchs libres, retrait automatique, anciens matricules gardés, message du lien de réinitialisation) validées par Katana le 21/11/2026 et appliquées (accueil, classements, règlement, processus) ; page « Participer » retirée du menu (#participer → Inscription) ; accueil : « organisée par DFMM, indépendante de l'éditeur du jeu ». Reste : règlement réécrit en entier (litiges, sanctions, confidentialité, démarrage), processus, couleurs, actualités, messagerie ; proposer chaque texte avant |

Points en suspens :
- Nettoyage de la fausse fiche « EssaiTest » et du compte `essai1@dfmm.invalid` : fait, vérifié le 21/11/2026 (0 fiche, 0 compte).
- Mise à jour du règlement du site (lot 5) et du guide PDF (ne pas toucher au PDF).
- Message de réinscription pour les 25 : **envoyé le 21/11/2026** (essai vérifié, puis « 25 message(s) envoyé(s). »). Reste : approuver chaque réinscription reçue avec l'ancien matricule (Administration > Inscriptions > Approuver > Matricule = l'ancien, pas « Nouveau matricule »).
- Sauvegarde : bouton dans Administration > Sauvegarde ; à faire chaque semaine (pas de sauvegarde automatique). Depuis la PR n° 7, elle inclut `demandes`, `notifications` et `volsever_appels` ; le test `tests/sauvegarde.test.js` échoue si une nouvelle table de migration n'est pas ajoutée à `TABLES_SAUVEGARDE` (`index.html`).
- Pseudo et effacement : jamais essayés de bout en bout avec un vrai compte (aucun membre encore). Premier essai réel avec le premier membre réinscrit (consomme 1 appel volsever).

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
- Supabase : projet `ijpbplzbjohfrqwnvrqv` (URL et clé publishable dans `config.js`, rien d'autre). Fonctions installées : `lien-reinitialisation`, `inscription` (« Verify JWT » désactivé), `pseudo-volsever` et `effacer-donnees` (« Verify JWT » **activé** : réservées aux personnes connectées). Secret déjà rangé : `VOLSEVER_API_KEY`.
- Migrations (`supabase/migrations/`) : 0001 à 0011 exécutées dans le vrai projet (par le SQL, pas par l'outil de migrations : la liste des migrations de Supabase reste vide, c'est normal). Chaque migration a son test dans `supabase/tests/` (il finit par un message rouge « FIN DU TEST » voulu, qui annule tout).
- Forfait gratuit Supabase : pause après 1 semaine sans activité, pas de sauvegarde automatique, 1 Go de fichiers, envoi d'e-mails limité à 2 par heure et aux membres de l'équipe du projet.
- volsever : `GET https://gate.volsever.com/proxy/api/game/delta-force?id={UID}` ; réponse `data.username` ; environ 5 s ; forfait gratuit 45 requêtes par jour et 15 par minute ; clé envoyée dans l'en-tête `X-API-KEY` (documentation : docs.volsever.com, outil « Delta Force (Tencent) ») ; identifiant inconnu = code 404. Le compteur d'appels est tenu dans la table `volsever_appels` (24 h glissantes et dernière minute).
- Pseudo et tag de clan : « ¬ » est un tag de clan validé, à conserver et comparer tel quel.
- Environnement cloud « dfmm-site » : hôtes autorisés `ijpbplzbjohfrqwnvrqv.supabase.co`, `supabase.com`, `volsever.com`, `www.volsever.com`, `gate.volsever.com`, `docs.volsever.com` (documentation seulement : la clé volsever n'est jamais dans cet environnement).
- Connecteur « Supabase DFMM » (limité au projet, outils base, journal et documentation ; pas d'outil de compte). Le connecteur standard « Supabase » (accès à tout le compte) est déconnecté : ne pas l'utiliser. Chaque requête : SQL et résultat attendu montrés à Katana, puis son « oui » écrit, puis le message exact de Supabase rapporté.
- Tests locaux : `node --test tests/*.test.js` (41 tests) ; base imitée : PostgreSQL 16 avec `supabase/tests/emulation_locale.sql`, puis les migrations dans l'ordre, puis les fichiers de test.
- Essai des écrans dans Chromium : `node tests/e2e/lot3a.e2e.js` (fausse base en mémoire `tests/e2e/faux-supabase.js`, aucune donnée réelle, horloge fixée au dimanche 22/11/2026) : saison, nouveau match, capture, réponse de claude.ai, contrôles, validation, identification, calcul et publication d'un classement, page publique, sanction (retrait de statistiques) et levée, litige (attente → dossier, qualification, convocation, discussion, décision, synthèse), lots et prévision d'attribution, retour en brouillon (23 étapes).
- Matchs (lot 3A) : saisie dans Administration > Matchs ; capture rangée dans l'espace privé « captures » (`<match>/<horodatage>.jpg`), heure d'envoi fixée par le serveur (déclencheur) ; lecture par claude.ai avec la consigne `PROMPT_CLAUDE` (`index.html`, réponse JSON `{carte, mode, fin, lignes:[{faction, pseudo, score, elim, morts, assist, med, ing, obj, tac}]}`) collée dans l'éditeur ; contrôles `L.controlesMatch` côté site ; décisions par `decider_match` (valider, attente, refuser, annuler, brouillon ; motif obligatoire sauf pour valider) ; ligne « à identifier » après validation : `identifier_ligne` (datée, classements suivants) ; registre (section 5) jamais modifiable. Les écrans « Créneaux » et « Tableau de bord » de `index.html` restent l'ancien prototype local (non affichés) : à refaire.
- Sanctions (lot 4A) : table `sanctions` (jamais publique ; le membre ne voit que les siennes) ; `sanctionner`, `contester_sanction`, `decider_sanction` (maintenir / lever) ; `est_suspendu` utilisé par `mon_membre_actif` ; le calcul (`chargerContexte`) ajoute les suspensions aux membres et marque `exclue_sanction` sur les lignes dont les statistiques sont retirées ; cas « fausse identité » et « double inscription » (compte supprimé, accès fermé) non automatisés : à traiter à part ; « capture falsifiée : plus organisateur ni responsable pendant la saison » à brancher au lot 3B (catégorie gardée dans `sanctions.categorie`).
- Litiges (lot 4B) : tables `dossiers`, `convocations`, `messages_litige` ; déclencheur `matchs_ouvrir_dossier` (statut → attente) ; `qualifier_dossier`, `convoquer`, `confirmer_convocation`, `ecrire_litige`, `trancher_dossier` (appelle `decider_match`), `valider_synthese`, `captures_a_supprimer` + suppression des fichiers par le site + `noter_captures_supprimees`, `sanctionner_dossier` ; consigne `PROMPT_SYNTHESE` (`index.html`) ; les convoqués ne voient pas encore les captures (à ajouter si Katana le souhaite).
- Titres et lots : table `lots` (administrateur seulement) ; `L.classementDepuisPublication` relit le classement final publié pour `L.attribuerLots` ; `enregistrer_attribution` (classement final seulement, un lot par joueur), `marquer_lot_remis`.
- Classements (lot 3C) : provisoire = date de publication (un dimanche) → coupure `L.coupurePour` (samedi 16 h), décisions comptées jusqu'à la coupure ; final = `L.coupureFinale`, publication possible seulement après `L.finVerificationFinale`, décisions jusqu'à la publication ; `L.agreger` puis `L.classer` ; contenu publié = noms de gamer, matricules, pseudos et statistiques seulement ; la base attribue le numéro et l'heure, et refuse toute modification ou suppression (corriger = publier le classement suivant). Premier provisoire d'Aurora : dimanche 29/11/2026 (coupure samedi 28/11 à 16 h).

## 6. Pièges déjà rencontrés

- Fonction Supabase : le nom se choisit à la création ; le fichier reste `index.ts`.
- E-mails : le service intégré de Supabase n'écrit qu'aux membres de l'équipe du projet ; jamais de confirmation par e-mail, utiliser le lien de réinitialisation envoyé par Messenger.
- La fonction `inscription` doit avoir « Verify JWT » désactivé.
- Les projets Supabase récents ne donnent aucun droit automatique au rôle `service_role` : chaque nouvelle table doit lui être accordée (migration 0003 règle les tables existantes et les suivantes) ; la base locale de test imite ce comportement.
- Une même opération SQL a une seule valeur de `now()` : pour des dates de début et de fin dans une même opération, utiliser `clock_timestamp()`.
- Le compteur des matricules ne revient jamais en arrière : un test ne doit pas approuver avec un nouveau matricule dans le vrai projet sans remettre le compteur (voir les tests 0002 et 0004).
- Aucune valeur de test dans la vraie base sans nettoyage vérifié ; utiliser des matricules fictifs (99xxx) et des adresses `@test.invalid`.
- Le lien de réinitialisation doit être écouté dès le chargement de la page (bug corrigé au lot 0).
- Base imitée en local : le dossier des données doit appartenir à l'utilisateur `postgres` (par exemple `/var/lib/postgresql/…`), sinon `initdb` refuse.
- Une session cloud qui n'est pas dans l'environnement « dfmm-site » ne joint pas `ijpbplzbjohfrqwnvrqv.supabase.co` directement : passer par le connecteur « Supabase DFMM ».

## 7. Prochaine étape

1. Titres et lots (PR n° 11) : migration 0011 et test 0011 faits ; fusion sur l'accord écrit de Katana.
2. Matchs saisis en brouillon : M-2 et M-3 (valider quand les réinscriptions sont approuvées). Premier provisoire d'Aurora le dimanche 29/11/2026 (coupure samedi 28/11 à 16 h) : guider Katana (Administration > Classements).
3. Lot 5, suite (proposer chaque texte à Katana avant de l'appliquer) : règlement réécrit en entier à partir du cahier (ajouter matchs en attente et litiges, tableau-guide des sanctions, confidentialité des litiges, phase de démarrage, lisibilité des captures) ; page Processus (litiges, sanctions) ; couleurs (rouge #E53935 au lieu de l'ambre) ; actualités (Katana publie) ; messagerie avec Katana.
4. Lot 3B (matchs libres), puis nettoyage de l'ancien code du prototype (onglets « Créneaux », « Tableau de bord », « Décisions »).
