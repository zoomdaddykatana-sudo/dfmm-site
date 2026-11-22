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

// ----- Vérifications automatiques (migration 0014, choix de Katana du 22/11/2026) -----
const V = new Function(aides + '; return { dateReelle, interpreterVolsever, interpreterMx, lireListeJetables, estJetable, domaineEmail, codeMessenger, MESSAGES_EMAIL, MESSAGE_UID_INCONNU };')();

test('UID : chiffres seulement, de 5 à 20', () => {
  assert.match(verifierDonnees(Object.assign({}, BON, { uid: '12a456' })).join(), /UID invalide/);
  assert.match(verifierDonnees(Object.assign({}, BON, { uid: '1234' })).join(), /UID invalide/);
  assert.match(verifierDonnees(Object.assign({}, BON, { uid: '1'.repeat(21) })).join(), /UID invalide/);
  assert.deepEqual(verifierDonnees(Object.assign({}, BON, { uid: ' 12345 ' })), []);
});
test('date de naissance : réelle (pas de 31 février), après 1900, passée', () => {
  assert.equal(V.dateReelle('2001-05-04'), true);
  assert.equal(V.dateReelle('2001-02-31'), false);
  assert.equal(V.dateReelle('1899-12-31'), false);
  assert.equal(V.dateReelle('2999-01-01'), false);
  assert.match(verifierDonnees(Object.assign({}, BON, { date_naissance: '2003-02-30' })).join(), /Date de naissance/);
});
test('volsever : même lecture que la fonction « pseudo-volsever »', () => {
  const src2 = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'pseudo-volsever', 'index.ts'), 'utf8');
  const extraire = (t, nom) => { const i = t.indexOf('function ' + nom); return t.slice(i, t.indexOf('\n}\n', i) + 2); };
  ['interpreterVolsever', 'limiteAtteinte'].forEach(n => assert.equal(extraire(aides, n), extraire(src2, n), n));
  assert.match(src, /const ADRESSE_VOLSEVER = 'https:\/\/gate\.volsever\.com\/proxy\/api\/game\/delta-force\?id=';/);
  assert.equal(V.interpreterVolsever(404, { status: false, code: 404 }).resultat, 'introuvable');
  assert.deepEqual(V.interpreterVolsever(200, { status: true, data: { username: 'PKL¬Pzone' } }), { resultat: 'trouve', pseudo: 'PKL¬Pzone' });
});
test('UID inconnu : refus (réglage « refus_uid_introuvable », oui par défaut) ; volsever muet : l’inscription passe', () => {
  assert.match(V.MESSAGE_UID_INCONNU, /n’existe pas/);
  assert.match(src, /vs\.resultat === 'introuvable' && P\.refus_uid_introuvable !== false/);
  const mig = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0014_verifications_inscription.sql'), 'utf8');
  assert.match(mig, /\('refus_uid_introuvable', 'true', 'booleen'/);
});
test('e-mail : réponse DNS (MX) → ok, sans serveur de messagerie, inexistant, pas de réponse', () => {
  assert.equal(V.interpreterMx({ Status: 0, Answer: [{ name: 'gmail.com.', type: 15, TTL: 300, data: '5 gmail-smtp-in.l.google.com.' }] }), 'ok');
  assert.equal(V.interpreterMx({ Status: 0, Answer: [{ type: 5, data: 'autre.exemple.' }] }), 'sans_mx');
  assert.equal(V.interpreterMx({ Status: 0 }), 'sans_mx');
  assert.equal(V.interpreterMx({ Status: 0, Answer: [{ type: 15, data: '0 .' }] }), 'sans_mx');
  assert.equal(V.interpreterMx({ Status: 3 }), 'inexistant');
  assert.equal(V.interpreterMx({ Status: 2 }), 'erreur');
  assert.equal(V.interpreterMx(null), 'erreur');
  ['inexistant', 'sans_mx', 'jetable'].forEach(k => assert.ok(V.MESSAGES_EMAIL[k], k));
  assert.equal(V.MESSAGES_EMAIL.ok, undefined);
  assert.equal(V.MESSAGES_EMAIL.non_verifie, undefined);   // services DNS muets : pas de refus
});
test('e-mail jetable : domaine ou sous-domaine de la liste publique', () => {
  const l = V.lireListeJetables('# commentaire\nyopmail.com\r\nMailinator.com\n\n');
  assert.equal(l.size, 2);
  assert.equal(V.estJetable(V.domaineEmail('Jean@YOPMAIL.com'), l), true);
  assert.equal(V.estJetable('x.mailinator.com', l), true);
  assert.equal(V.estJetable('gmail.com', l), false);
  assert.equal(V.estJetable('com', l), false);
});
test('code Messenger : « UV- » + 6 signes lisibles', () => {
  const c = V.codeMessenger(new Uint8Array([0, 1, 30, 31, 200, 255]));
  assert.match(c, /^UV-[2-9A-HJKMNP-Z]{6}$/);
  for (let i = 0; i < 200; i++) assert.match(V.codeMessenger(require('node:crypto').randomBytes(6)), /^UV-[2-9A-HJKMNP-Z]{6}$/);
});
test('longueurs maximales (décision 3) : 100 caractères pour les champs courts, 2 000 pour le lien Facebook', () => {
  assert.deepEqual(verifierDonnees(Object.assign({}, BON, { nom_gamer: 'n'.repeat(100), nom_reel: 'r'.repeat(100), clan: 'c'.repeat(100) })), []);
  assert.match(verifierDonnees(Object.assign({}, BON, { nom_gamer: 'n'.repeat(101) })).join(), /Texte trop long \(nom de gamer\) : 100 caractères/);
  assert.match(verifierDonnees(Object.assign({}, BON, { pseudo: 'p'.repeat(101) })).join(), /Texte trop long \(pseudo\)/);
  assert.match(verifierDonnees(Object.assign({}, BON, { facebook: 'https://facebook.com/' + 'f'.repeat(2000) })).join(), /Texte trop long \(lien Facebook\) : 2000 caractères/);
});
test('longueurs maximales réglables (longueur_max_court, longueur_max_long)', () => {
  assert.match(verifierDonnees(Object.assign({}, BON, { nom_gamer: 'n'.repeat(21) }), { court: 20, long: 2000 }).join(), /20 caractères au plus/);
  assert.deepEqual(verifierDonnees(Object.assign({}, BON, { nom_gamer: 'n'.repeat(21) }), { court: '150', long: '3000' }), []);
});
