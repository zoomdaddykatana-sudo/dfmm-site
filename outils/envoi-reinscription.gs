/* LEAGUE UV — DFMM · Envoi du message de réinscription aux anciens membres (DFMM-1 à DFMM-25).
   Script Google Apps Script, à coller dans une feuille Google (Extensions > Apps Script).
   Il envoie le message depuis le Gmail de la personne qui le lance. Aucune adresse n'est écrite ici :
   elles sont seulement dans la feuille, remplie à la main par Katana.

   Feuille attendue (premier onglet), ligne 1 = titres, puis une ligne par membre :
     A : Matricule (le nombre seul, par exemple 7 pour DFMM-7)
     B : Nom de gamer
     C : E-mail
     D : Envoyé le  (laisser vide : le script la remplit)

   Menu « LEAGUE UV » (apparaît en haut de la feuille) :
     1. « Envoyer un essai à moi-même » : le message de la 1re ligne arrive dans votre propre boîte.
     2. « Envoyer à tous » : chaque ligne dont la colonne D est vide reçoit son message ; la date est notée en D.
        Une ligne déjà datée n'est jamais renvoyée. */

var SITE = 'https://zoomdaddykatana-sudo.github.io/dfmm-site/#inscription';
var EXPEDITEUR = 'Katana — LEAGUE UV (DFMM)';

function sujet(mat) {
  return 'LEAGUE UV — réinscription de votre matricule DFMM-' + mat;
}

function message(nom, mat) {
  return 'Bonjour ' + nom + ',\n\n'
    + 'La LEAGUE UV (DFMM) passe sur son nouveau site. Vous faites partie des premiers membres approuvés : '
    + 'votre matricule DFMM-' + mat + ' vous est réservé.\n\n'
    + 'Pour le garder, réinscrivez-vous ici :\n' + SITE + '\n\n'
    + 'À préparer avant de commencer :\n'
    + '- votre pseudo exact en jeu, avec le tag de clan ;\n'
    + '- votre UID ;\n'
    + '- une capture de votre profil qui montre le pseudo et l\'UID.\n\n'
    + 'Utilisez de préférence l\'adresse e-mail qui reçoit ce message.\n\n'
    + 'Après l\'approbation par Katana, vous retrouvez votre matricule DFMM-' + mat
    + ' et votre date d\'approbation d\'origine : les matchs joués depuis pourront compter pour vous.\n\n'
    + 'Une question ? Écrivez à Katana sur Messenger.\n\n'
    + 'Katana\nLEAGUE UV — DFMM\n#LeagueUV\n';
}

function onOpen() {
  SpreadsheetApp.getUi().createMenu('LEAGUE UV')
    .addItem('Envoyer un essai à moi-même', 'envoyerEssai')
    .addItem('Envoyer à tous', 'envoyerATous')
    .addToUi();
}

function lignes_() {
  var f = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  var n = f.getLastRow();
  if (n < 2) return { feuille: f, lignes: [] };
  var v = f.getRange(2, 1, n - 1, 4).getValues();
  return {
    feuille: f,
    lignes: v.map(function (r, i) {
      return { rang: i + 2, mat: String(r[0]).replace(/\D/g, ''), nom: String(r[1]).trim(), email: String(r[2]).trim(), envoye: r[3] };
    })
  };
}

function emailValide_(e) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e); }

function envoyerEssai() {
  var ui = SpreadsheetApp.getUi();
  var d = lignes_();
  var l = d.lignes.filter(function (x) { return x.mat && x.nom; })[0];
  if (!l) { ui.alert('Aucune ligne remplie : mettez au moins un matricule et un nom de gamer en ligne 2.'); return; }
  var moi = Session.getActiveUser().getEmail();
  if (!moi) { ui.alert('Adresse de votre compte introuvable : lancez le script depuis votre propre compte Google.'); return; }
  MailApp.sendEmail({ to: moi, subject: '[ESSAI] ' + sujet(l.mat), body: message(l.nom, l.mat), name: EXPEDITEUR });
  ui.alert('Essai envoyé à votre propre adresse. Ouvrez Gmail pour vérifier le message.');
}

function envoyerATous() {
  var ui = SpreadsheetApp.getUi();
  var d = lignes_();
  var aEnvoyer = d.lignes.filter(function (x) { return !x.envoye && x.mat && x.nom && emailValide_(x.email); });
  var aVerifier = d.lignes.filter(function (x) { return !x.envoye && (x.mat || x.nom || x.email) && !(x.mat && x.nom && emailValide_(x.email)); });
  if (!aEnvoyer.length) { ui.alert('Rien à envoyer : toutes les lignes sont déjà datées en colonne D, ou incomplètes.'); return; }
  var quota = MailApp.getRemainingDailyQuota();
  if (quota < aEnvoyer.length) { ui.alert('Gmail n\'autorise plus que ' + quota + ' envoi(s) aujourd\'hui. Réessayez demain.'); return; }
  var ok = ui.alert('Envoyer le message à ' + aEnvoyer.length + ' membre(s) ?', ui.ButtonSet.YES_NO);
  if (ok !== ui.Button.YES) return;
  var envoyes = 0, echecs = [];
  aEnvoyer.forEach(function (x) {
    try {
      MailApp.sendEmail({ to: x.email, subject: sujet(x.mat), body: message(x.nom, x.mat), name: EXPEDITEUR });
      d.feuille.getRange(x.rang, 4).setValue(new Date());
      envoyes++;
    } catch (e) {
      echecs.push('ligne ' + x.rang + ' (DFMM-' + x.mat + ')');
    }
  });
  ui.alert(envoyes + ' message(s) envoyé(s).'
    + (echecs.length ? '\nÉchec : ' + echecs.join(', ') + '.' : '')
    + (aVerifier.length ? '\nLignes incomplètes, non envoyées : ' + aVerifier.map(function (x) { return x.rang; }).join(', ') + '.' : ''));
}
