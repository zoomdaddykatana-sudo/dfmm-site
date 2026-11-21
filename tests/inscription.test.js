// Tests des contrôles de la fonction serveur « inscription » (partie JavaScript simple).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const src = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'inscription', 'index.ts'), 'utf8');
const aides = src.slice(src.indexOf('// DEBUT-AIDES'), src.indexOf('// FIN-AIDES'));
const { normEmail, normFacebook, verifierDonnees } = new Function(aides + '; return { normEmail, normFacebook, verifierDonnees };')();

const BON = { nom_reel: 'Rakoto Jean', nom_gamer: 'Jeannot', email: 'Jean@Exemple.mg', date_naissance: '2001-05-04', genre: 'Homme',
  facebook: 'https://www.facebook.com/jeannot.rakoto/', pseudo: 'PKL¬Pzone', uid: '123456789', residence: 'Madagascar',
  province: 'Antananarivo', zone: 'Périphérie', comprend_mg: 'Oui', parle_mg: 'Non', origine_mg: true,
  acc_dfmm: true, acc_uv: true, acc_donnees: true, acc_approbation: true, mot_de_passe: 'motdepasse1' };

test('un dossier complet est accepté (pseudo avec tag de clan « ¬ » gardé tel quel)', () => {
  assert.deepEqual(verifierDonnees(BON), []);
});
test('ne pas comprendre le malgache bloque l’inscription (critère essentiel)', () => {
  assert.match(verifierDonnees(Object.assign({}, BON, { comprend_mg: 'Non' })).join(), /essentiel/);
});
test('cases obligatoires, mot de passe de 8 caractères, province, pays', () => {
  assert.match(verifierDonnees(Object.assign({}, BON, { acc_approbation: false })).join(), /acc_approbation/);
  assert.match(verifierDonnees(Object.assign({}, BON, { mot_de_passe: 'court' })).join(), /8 caractères/);
  assert.match(verifierDonnees(Object.assign({}, BON, { province: 'Paris' })).join(), /Province/);
  assert.match(verifierDonnees(Object.assign({}, BON, { residence: 'Étranger', pays: '' })).join(), /Pays/);
  assert.deepEqual(verifierDonnees(Object.assign({}, BON, { residence: 'Étranger', pays: 'France', province: '', zone: '' })), []);
});
test('le même e-mail ou le même profil Facebook écrit autrement donne la même empreinte', () => {
  assert.equal(normEmail(' Jean@Exemple.MG '), 'jean@exemple.mg');
  const formes = ['https://www.facebook.com/jeannot.rakoto/', 'http://m.facebook.com/Jeannot.Rakoto?ref=bookmarks', 'facebook.com/jeannot.rakoto', 'https://web.facebook.com/jeannot.rakoto#'];
  assert.equal(new Set(formes.map(normFacebook)).size, 1);
  assert.equal(normFacebook('https://www.facebook.com/profile.php?id=10001234&mibextid=x'), 'facebook.com/profile.php?id=10001234');
  assert.equal(normFacebook('https://fb.com/jeannot.rakoto'), 'facebook.com/jeannot.rakoto');
});
test('un lien qui n’est pas Facebook est refusé', () => {
  assert.match(verifierDonnees(Object.assign({}, BON, { facebook: 'https://instagram.com/jeannot' })).join(), /Facebook/);
});
