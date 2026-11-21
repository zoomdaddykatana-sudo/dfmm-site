// Tests de la lecture des réponses de volsever et des limites d'appels (fonction « pseudo-volsever »).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const src = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'pseudo-volsever', 'index.ts'), 'utf8');
const aides = src.slice(src.indexOf('// DEBUT-AIDES'), src.indexOf('// FIN-AIDES'));
const { interpreterVolsever, limiteAtteinte, ADRESSE_VOLSEVER } = new Function(aides + '; return { interpreterVolsever, limiteAtteinte, ADRESSE_VOLSEVER };')();

test('réponse « ID Found » : pseudo lu tel quel, tag de clan « ¬ » compris', () => {
  const corps = { status: true, code: 200, message: 'ID Found', data: { username: 'PKL¬Pzone', user_id: '123', zone: null, game: 'Delta Force' } };
  assert.deepEqual(interpreterVolsever(200, corps), { resultat: 'trouve', pseudo: 'PKL¬Pzone' });
});
test('identifiant inconnu (404) : « introuvable »', () => {
  assert.equal(interpreterVolsever(404, { status: false, code: 404, message: 'Game not found' }).resultat, 'introuvable');
  assert.equal(interpreterVolsever(400, { status: false, code: 404 }).resultat, 'introuvable');
});
test('clé absente, réponse vide ou illisible : « erreur » (validation à la main)', () => {
  assert.equal(interpreterVolsever(401, { status: false, code: 401, error: 'MISSING_API_KEY' }).resultat, 'erreur');
  assert.equal(interpreterVolsever(500, null).resultat, 'erreur');
  assert.equal(interpreterVolsever(200, { status: true, data: { username: '' } }).resultat, 'erreur');
});
test('limites : 45 par jour, 15 par minute (réglables) ; sans réglage lisible, aucun appel', () => {
  assert.equal(limiteAtteinte(44, 14, 45, 15), false);
  assert.equal(limiteAtteinte(45, 0, 45, 15), true);
  assert.equal(limiteAtteinte(3, 15, 45, 15), true);
  assert.equal(limiteAtteinte(0, 0, NaN, 15), true);
});
test('adresse officielle de l’outil Delta Force (Tencent)', () => {
  assert.equal(ADRESSE_VOLSEVER, 'https://gate.volsever.com/proxy/api/game/delta-force?id=');
});
