# Envoi du message de réinscription aux 25 anciens membres

Texte validé par Katana le 21/11/2026. Inscriptions ouvertes le 21/11/2026. Le script `envoi-reinscription.gs`
envoie le message depuis le Gmail de Katana ; les adresses restent dans sa feuille Google (jamais dans le dépôt ni le chat).

Sur ordinateur, une étape à la fois :

1. **Préparer la feuille.** Ouvrir https://sheets.new, la renommer `LEAGUE UV — réinscription`.
   Ligne 1 : A1 `Matricule`, B1 `Nom de gamer`, C1 `E-mail`, D1 `Envoyé le`.
   Lignes 2 à 26 (depuis la feuille Inscription de l'ancien classeur) : A = le numéro seul (`7` pour DFMM-7),
   B = nom de gamer, C = e-mail. Colonne D vide.
   Résultat attendu : 25 lignes remplies.
2. **Coller le script.** Dans la feuille : menu **Extensions > Apps Script**. Un nouvel onglet s'ouvre avec
   `function myFunction() {}`. Tout effacer, puis coller le contenu de
   https://github.com/zoomdaddykatana-sudo/dfmm-site/blob/ccr-08840471-84tqcu/outils/envoi-reinscription.gs
   (bouton **Copier**, en haut à droite du code). Cliquer sur l'icône de disquette **Enregistrer**.
   Résultat attendu : plus de point orange à côté du nom du fichier `Code.gs`.
3. **Faire apparaître le menu.** Fermer l'onglet Apps Script, recharger la feuille (touche F5).
   Résultat attendu : après quelques secondes, un menu **LEAGUE UV** apparaît à droite du menu **Aide**.
4. **Autoriser et envoyer un essai.** Menu **LEAGUE UV > Envoyer un essai à moi-même**.
   La première fois, Google demande une autorisation : **Continuer** → choisir son compte →
   « Google n'a pas validé cette application » → **Paramètres avancés** → **Accéder à … (non sécurisé)** →
   **Autoriser** (c'est son propre script, il n'envoie qu'avec son Gmail). Puis relancer
   **LEAGUE UV > Envoyer un essai à moi-même**.
   Résultat attendu : le message « Essai envoyé à votre propre adresse », et dans Gmail un e-mail
   « [ESSAI] LEAGUE UV — réinscription de votre matricule DFMM-… » (regarder aussi dans Spam).
5. **Vérifier l'essai.** Dans l'e-mail : bon nom de gamer, bon matricule ; le lien ouvre bien le formulaire
   d'inscription du site.
6. **Envoyer à tous.** Menu **LEAGUE UV > Envoyer à tous** → **Oui**.
   Résultat attendu : « 25 message(s) envoyé(s). » et la colonne D remplie avec la date d'envoi.
   Une ligne incomplète ou en échec est signalée par son numéro : la corriger, puis relancer
   **Envoyer à tous** (seules les lignes sans date en colonne D partent ; jamais de double envoi).
   Limite de Gmail : environ 100 envois par jour, largement suffisant.

Ensuite, à chaque réinscription reçue : **Administration > Inscriptions** → cocher les vérifications →
**Approuver** → dans **Matricule**, choisir l'ancien matricule (groupe « Même nom de gamer » ou
« Autres anciens matricules ») au lieu de « Nouveau matricule » → **Enregistrer la décision**. Le membre garde
son matricule et sa date d'approbation d'origine (0 h, heure de Madagascar).
