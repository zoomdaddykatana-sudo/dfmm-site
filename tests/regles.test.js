// Tests automatiques des règles de calcul (lot 1). Lancer : node --test tests/
// Les valeurs des paramètres sont lues dans la migration Supabase : mêmes chiffres que la base.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('../js/regles.js');

// ---------- Paramètres : lus dans supabase/migrations/0001_socle.sql ----------
const sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0001_socle.sql'), 'utf8');
const PARAM = {};
for (const m of sql.matchAll(/^\s*\('([a-z0-9_]+)',\s*'((?:[^']|'')*)',\s*'(entier|decimal|heure|jour|booleen|texte)'/gm)) PARAM[m[1]] = JSON.parse(m[2]);
const R = L.regles(PARAM);

// ---------- Données fictives ----------
const SAISON = { id: 1, nom: 'Saison test', debut: '2026-11-18', fin: '2027-01-31' };
function membre(mat, extra) { return Object.assign({ matricule: mat, statut: 'Actif', periodes: [{ debut: '2026-11-18T00:00', fin: '' }], suspensions: [] }, extra || {}); }
function compte(id, mat) { return { id, matricule: mat, pseudo: 'P' + mat, statut: 'Actif', periodes: [{ debut: '2026-11-18T00:00', fin: '' }], pseudos: [] }; }
function ctxAvec(nbMembres, extraMembres) {
  const membres = {}, comptes = {};
  for (let i = 1; i <= nbMembres; i++) { const mat = 'DFMM-' + i; membres[mat] = membre(mat, (extraMembres || {})[mat]); comptes['C' + i] = compte('C' + i, mat); }
  return { membres, comptes, creneaux: {}, matchsList: [] };
}
const stats = (v) => ({ score: 1000 * v, elim: v, morts: 5, assist: 1, med: 0, ing: 0, obj: v, tac: 1 });
// Un match de `total` joueurs, moitié HAAVK, moitié GTI ; les `nbMembres` premiers sont des membres reconnus.
function match(total, nbMembres, extra) {
  const lignes = [];
  for (let i = 1; i <= total; i++) {
    const l = Object.assign({ faction: i % 2 ? 'HAAVK' : 'GTI', pseudo: 'J' + i }, stats(i));
    if (i <= nbMembres) Object.assign(l, { mat: 'DFMM-' + i, cpt: 'C' + i, res: 'auto' }); else l.res = 'non inscrit';
    lignes.push(l);
  }
  return Object.assign({ id: 'M1', saison_id: 1, type: 'Katana', statut: 'Validé', fin: '2026-11-21T16:30', envoi: '2026-11-21T16:35', captures: ['x'], lignes }, extra || {});
}

// ---------- Paramètres ----------
test('les 22 paramètres de calcul sont lus dans la base, aucune valeur en dur', () => {
  assert.equal(R.participants_min, 16); assert.equal(R.seuil_membres_pct, 50); assert.equal(R.delai_capture_min, 10);
  assert.equal(R.coupure_heure, '16:00'); assert.equal(R.coupure_jour, 6); assert.equal(R.plage_fin_h, 1);
  assert.throws(() => L.regles({ participants_min: 16 }), /Paramètre\(s\) manquant\(s\)/);
});

// ---------- Section 4 : validité d'un match ----------
test('seuil de 50 % de membres confirmés, arrondi vers le bas', () => {
  assert.equal(L.membresRequis(16, R), 8);
  assert.equal(L.membresRequis(17, R), 8);
  assert.equal(L.membresRequis(15, R), 7);
  assert.equal(L.membresRequis(21, R), 10);
});
test('16 joueurs dont 8 membres confirmés : valide ; 7 membres : bloqué', () => {
  assert.deepEqual(L.controlesMatch(match(16, 8), ctxAvec(16), SAISON, R).bloquants, []);
  const c = L.controlesMatch(match(16, 7), ctxAvec(16), SAISON, R);
  assert.equal(c.membres, 7); assert.match(c.bloquants.join(), /au moins 8/);
});
test('un membre suspendu ou hors période ne compte pas comme membre confirmé', () => {
  const ctx = ctxAvec(16, { 'DFMM-1': { suspensions: [{ debut: '2026-11-20T00:00', fin: '2026-11-25T00:00' }] } });
  const c = L.controlesMatch(match(16, 8), ctx, SAISON, R);
  assert.equal(c.membres, 7); assert.match(c.bloquants.join(), /au moins 8/);
});
test('une ligne à identifier ne bloque pas le match et ne compte pas comme membre', () => {
  const m = match(16, 9); Object.assign(m.lignes[8], { mat: '', cpt: '', res: 'à identifier' });
  const c = L.controlesMatch(m, ctxAvec(16), SAISON, R);
  assert.equal(c.membres, 8); assert.deepEqual(c.bloquants, []);
  assert.match(c.alertes.join(), /à identifier/);
});
test('15 participants ou écart de 2 entre factions : bloqué ; pas de maximum de participants', () => {
  assert.match(L.controlesMatch(match(15, 15), ctxAvec(16), SAISON, R).bloquants.join(), /au moins 16/);
  const m = match(18, 18); m.lignes[1].faction = 'HAAVK';
  assert.match(L.controlesMatch(m, ctxAvec(18), SAISON, R).bloquants.join(), /Écart/);
  assert.deepEqual(L.controlesMatch(match(40, 20), ctxAvec(40), SAISON, R).bloquants, []);
});
test('capture envoyée 10 min après la fin : acceptée ; 11 min : rejetée (matchs de Katana compris)', () => {
  assert.deepEqual(L.controlesMatch(match(16, 8, { envoi: '2026-11-21T16:40' }), ctxAvec(16), SAISON, R).bloquants, []);
  assert.match(L.controlesMatch(match(16, 8, { envoi: '2026-11-21T16:41' }), ctxAvec(16), SAISON, R).bloquants.join(), /11 min/);
});
test('saisie de démarrage : pas de délai de 10 min, mais les autres règles restent', () => {
  assert.deepEqual(L.controlesMatch(match(16, 8, { demarrage: true, envoi: '' }), ctxAvec(16), SAISON, R).bloquants, []);
  assert.match(L.controlesMatch(match(16, 7, { demarrage: true, envoi: '' }), ctxAvec(16), SAISON, R).bloquants.join(), /au moins 8/);
});
test('match libre : fin dans l’heure qui suit l’heure annoncée, sinon en attente', () => {
  const ctx = ctxAvec(16); ctx.creneaux.L1 = { id: 'L1', date: '2026-11-21', debut: '15:00', statut: 'Enregistré' };
  const ok = L.controlesMatch(match(16, 8, { type: 'Libre', creneau_id: 'L1', fin: '2026-11-21T16:00', envoi: '2026-11-21T16:05' }), ctx, SAISON, R);
  assert.deepEqual(ok.bloquants, []); assert.deepEqual(ok.attente, []);
  const tard = L.controlesMatch(match(16, 8, { type: 'Libre', creneau_id: 'L1', fin: '2026-11-21T16:01', envoi: '2026-11-21T16:05' }), ctx, SAISON, R);
  assert.deepEqual(tard.bloquants, []); assert.match(tard.attente.join(), /en attente/);
});
test('plus de gel des 7 derniers jours : un match du dernier jour de la saison est accepté', () => {
  const c = L.controlesMatch(match(16, 8, { fin: '2027-01-31T16:30', envoi: '2027-01-31T16:35' }), ctxAvec(16), SAISON, R);
  assert.deepEqual(c.bloquants, []);
  assert.match(L.controlesMatch(match(16, 8, { fin: '2027-02-01T16:30', envoi: '2027-02-01T16:35' }), ctxAvec(16), SAISON, R).bloquants.join(), /après la fin/);
});
test('l’ancienne alerte « un match par session » n’existe plus', () => {
  const ctx = ctxAvec(16); ctx.matchsList = [match(16, 8, { id: 'M0' })];
  const c = L.controlesMatch(match(16, 8), ctx, SAISON, R);
  assert.ok(!c.alertes.join().includes('session'));
});

// ---------- Section 7 : coupure ----------
test('coupure : samedi précédant la publication, à 16 h (valeurs réglables)', () => {
  assert.equal(L.dow('2026-12-06'), 0);
  assert.equal(L.coupurePour('2026-12-06', R), '2026-12-05T16:00');
  assert.equal(L.coupurePour('2026-12-06', Object.assign({}, R, { coupure_heure: '15:30' })), '2026-12-05T15:30');
});
test('coupure selon l’heure d’envoi : 15:59 compte, 16:00 passe au suivant ; le match de Katana est exempté', () => {
  const opts = { coupure: '2026-11-21T16:00' };
  assert.equal(L.matchDansClassement(match(16, 8, { type: 'Libre', fin: '2026-11-21T15:50', envoi: '2026-11-21T15:59' }), SAISON, opts), true);
  assert.equal(L.matchDansClassement(match(16, 8, { type: 'Libre', fin: '2026-11-21T15:55', envoi: '2026-11-21T16:00' }), SAISON, opts), false);
  assert.equal(L.matchDansClassement(match(16, 8, { type: 'Katana', fin: '2026-11-21T16:30', envoi: '2026-11-21T16:35' }), SAISON, opts), true);
});
test('match en attente tranché après la coupure, ou ligne identifiée après : classement suivant', () => {
  const opts = { coupure: '2026-11-21T16:00' };
  assert.equal(L.matchDansClassement(match(16, 8, { type: 'Libre', envoi: '2026-11-21T15:00', attente_decide_le: '2026-11-21T17:00' }), SAISON, opts), false);
  assert.equal(L.matchDansClassement(match(16, 8, { type: 'Libre', envoi: '2026-11-21T15:00', attente_decide_le: '2026-11-21T15:30' }), SAISON, opts), true);
  const m = match(16, 8); Object.assign(m.lignes[0], { res: 'manuel', identifie_le: '2026-11-21T18:00' });
  assert.equal(L.ligneDansClassement(m.lignes[0], m, ctxAvec(16), opts), false);
  assert.equal(L.ligneDansClassement(m.lignes[0], m, ctxAvec(16), { coupure: '2026-12-05T16:00' }), true);
});

// ---------- Section 7 : classements ----------
function agg(joueurs) { return { joueurs: joueurs.map(j => Object.assign({ score: 0, elim: 0, morts: 0, assist: 0, med: 0, ing: 0, obj: 0, tac: 0 }, j)), nbMatchs: 10 }; }
const MEMBRES = ['A', 'B', 'C', 'D', 'E'].reduce((o, k) => (o[k] = membre(k), o), {});
test('égalité parfaite après les 3 critères : co-lauréats', () => {
  const cl = L.classer(agg([{ mat: 'A', n: 4, elim: 20, score: 900 }, { mat: 'B', n: 4, elim: 20, score: 900 }, { mat: 'C', n: 4, elim: 10, score: 900 }]), MEMBRES);
  const c = cl.cats.find(x => x.key === 'most_elim');
  assert.equal(c.statut, 'Co-lauréats'); assert.deepEqual(c.laureats.map(j => j.mat).sort(), ['A', 'B']);
});
test('départage : statistique, puis matchs joués, puis score total', () => {
  const cl = L.classer(agg([{ mat: 'A', n: 6, elim: 42, score: 900 }, { mat: 'B', n: 8, elim: 42, score: 100 }]), MEMBRES);
  assert.deepEqual(cl.cats.find(x => x.key === 'most_elim').laureats.map(j => j.mat), ['B']);
});
test('suspendus à la date de la coupure, retirés et exclus : hors médiane, hors Q1, non candidats', () => {
  const m = Object.assign({}, MEMBRES, {
    A: membre('A', { suspensions: [{ debut: '2026-11-20T00:00', fin: '2026-12-01T00:00' }] }),
    B: membre('B', { statut: 'Retiré' }), C: membre('C', { statut: 'Exclu' })
  });
  const j = [{ mat: 'A', n: 9, elim: 99, score: 9000 }, { mat: 'B', n: 9, elim: 99 }, { mat: 'C', n: 9, elim: 99 }, { mat: 'D', n: 2, elim: 5, score: 500 }, { mat: 'E', n: 4, elim: 6, score: 400 }];
  const pendant = L.classer(agg(j), m, '2026-11-21T16:00');
  assert.deepEqual(pendant.pop.map(x => x.mat).sort(), ['D', 'E']); assert.equal(pendant.seuil, 3);
  const apres = L.classer(agg(j), m, '2026-12-05T16:00');
  assert.deepEqual(apres.pop.map(x => x.mat).sort(), ['A', 'D', 'E']);
});
test('BEST : seuil = médiane des matchs arrondie au supérieur ; Q1 = QUARTILE.INC', () => {
  assert.equal(L.quantile([1, 2, 3, 4], 0.25), 1.75);
  const cl = L.classer(agg([3, 4, 4, 5, 8].map((n, i) => ({ mat: 'ABCDE'[i], n, elim: n, score: 100 * n }))), MEMBRES);
  assert.equal(cl.seuil, 4);
});
test('candidature : total strictement positif, sauf BEST Survivor (0 mort est le meilleur résultat)', () => {
  const cl = L.classer(agg([{ mat: 'A', n: 4, morts: 0, score: 800, med: 0 }, { mat: 'B', n: 4, morts: 8, score: 800, med: 0 }]), MEMBRES);
  assert.equal(cl.cats.find(x => x.key === 'most_med').statut, 'Aucun candidat');
  assert.deepEqual(cl.cats.find(x => x.key === 'best_surv').laureats.map(j => j.mat), ['A']);
});

// ---------- Section 8 : lots ----------
test('ordre de priorité des lots : Objective avant Tactician', () => {
  assert.deepEqual(L.CATS.map(c => c.label), ['MOST Eliminator', 'MOST Medic', 'MOST Engineer', 'MOST Objective', 'MOST Tactician', 'BEST Survivor', 'BEST Eliminator', 'BEST Medic', 'BEST Engineer', 'BEST Objective', 'BEST Tactician']);
});
test('co-lauréats : titre partagé, lot non attribué ; un lot n’est jamais attribué deux fois', () => {
  const cl = L.classer(agg([{ mat: 'A', n: 4, elim: 20, obj: 5, score: 900 }, { mat: 'B', n: 4, elim: 20, obj: 3, score: 900 }]), MEMBRES);
  const r = L.attribuerLots(cl, { most_elim: true, most_obj: true });
  const elim = r.find(x => x.key === 'most_elim'), obj = r.find(x => x.key === 'most_obj');
  assert.equal(elim.statut, 'Non attribué'); assert.equal(elim.beneficiaire, null);
  assert.equal(obj.beneficiaire, 'A');
  const lotis = r.filter(x => x.beneficiaire).map(x => x.beneficiaire);
  assert.equal(new Set(lotis).size, lotis.length);
});
test('redistribution : le lauréat déjà loti garde le titre, le lot passe au suivant sans lot', () => {
  const cl = L.classer(agg([{ mat: 'A', n: 4, elim: 30, med: 9, score: 900 }, { mat: 'B', n: 4, elim: 10, med: 5, score: 900 }]), MEMBRES);
  const r = L.attribuerLots(cl, { most_elim: true, most_med: true });
  assert.equal(r.find(x => x.key === 'most_elim').beneficiaire, 'A');
  const med = r.find(x => x.key === 'most_med');
  assert.deepEqual(med.laureats, ['A']); assert.equal(med.beneficiaire, 'B'); assert.equal(med.statut, 'Attribué (redistribution)');
});

// ---------- Alertes ----------
test('alertes de performance : seuils réglables, jamais bloquantes', () => {
  const ctx = ctxAvec(16);
  ctx.matchsList = [1, 2, 3].map(k => match(16, 8, { id: 'H' + k, fin: '2026-11-2' + k + 'T10:00' }));
  const m = match(16, 8, { id: 'N', fin: '2026-11-25T10:00', envoi: '2026-11-25T10:05' });
  m.lignes[0].elim = 40; // le joueur 1 fait habituellement 1 élimination
  assert.match(L.alertesPerformance(m, ctx, R).join(), /Alerte performance/);
  assert.equal(L.alertesPerformance(m, ctx, Object.assign({}, R, { alerte_facteur: 100 })).length, 0);
  assert.deepEqual(L.controlesMatch(m, ctx, SAISON, R).bloquants, []);
});
test('heure de Madagascar : un envoi enregistré par le serveur à 13:05 UTC est 16:05 à Madagascar', () => {
  assert.equal(L.versLocal('2026-11-21T13:05:00Z'), '2026-11-21T16:05');
});
