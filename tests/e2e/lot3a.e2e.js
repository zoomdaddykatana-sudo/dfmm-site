// Essai de bout en bout des écrans Saison et Matchs (lot 3A), dans Chromium, avec une fausse base en mémoire
// (tests/e2e/faux-supabase.js) : aucune donnée réelle, aucun appel à Supabase.
// Lancer : node tests/e2e/lot3a.e2e.js   (Playwright et Chromium requis)
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const os = require('os');
const SITE = path.join(__dirname, '..', '..'), ICI = fs.mkdtempSync(path.join(os.tmpdir(), 'dfmm-e2e-')), WWW = path.join(ICI, 'www');
fs.rmSync(WWW, { recursive: true, force: true });
fs.cpSync(SITE, WWW, { recursive: true, filter: s => !s.includes('/.git') && !s.includes('/tests') });
// Paramètres : toutes les migrations dans l'ordre (comme les tests).
const PARAMS = {}; const dm = path.join(SITE, 'supabase/migrations');
for (const f of fs.readdirSync(dm).sort()) {
  const sql = fs.readFileSync(path.join(dm, f), 'utf8');
  for (const m of sql.matchAll(/^\s*\('([a-z0-9_]+)',\s*'((?:[^']|'')*)',\s*'(entier|decimal|heure|jour|booleen|texte)',\s*'((?:[^']|'')*)',\s*'([^']*)',\s*(\d+)\)/gm)) PARAMS[m[1]] = { cle: m[1], valeur: JSON.parse(m[2]), type: m[3], libelle: m[4].replace(/''/g, "'"), section: m[5], ordre: +m[6] };
  for (const m of sql.matchAll(/delete from public\.parametres where cle = '([a-z0-9_]+)'/g)) delete PARAMS[m[1]];
}
PARAMS.inscriptions_ouvertes.valeur = true;
const base = { parametres: Object.values(PARAMS), membres: [], periodes: [], comptes_jeu: [], comptes_periodes: [], pseudos_historique: [],
  saisons: [], matchs: [], match_lignes: [], captures: [], registre: [], journal: [], demandes: [], notifications: [], volsever_appels: [], parametres_historique: [], membres_prives: [] };
for (let i = 1; i <= 8; i++) {
  base.membres.push({ id: i, matricule: i, nom_gamer: 'Faux ' + i, statut: 'actif', date_approbation: '2026-11-18T00:00:00+03:00' });
  base.periodes.push({ id: 100 + i, membre_id: i, debut: '2026-11-17T21:00:00Z', fin: null });
  base.comptes_jeu.push({ id: 10 + i, membre_id: i, uid: '99' + i, pseudo: (i === 1 ? 'PKL¬Un' : 'Joueur' + i), statut: 'actif' });
  base.comptes_periodes.push({ id: 200 + i, compte_id: 10 + i, debut: '2026-11-17T21:00:00Z', fin: null });
  base.pseudos_historique.push({ id: 300 + i, compte_id: 10 + i, pseudo: (i === 1 ? 'PKL¬Un' : 'Joueur' + i), debut: '2026-11-17T21:00:00Z', fin: null });
}
fs.writeFileSync(path.join(WWW, 'base.js'), 'window.FAUSSE_BASE = ' + JSON.stringify(base) + ';');
fs.copyFileSync(path.join(__dirname, 'faux-supabase.js'), path.join(WWW, 'faux-supabase.js'));
let html = fs.readFileSync(path.join(WWW, 'index.html'), 'utf8');
html = html.replace(/<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase[^>]*><\/script>/, '<script src="base.js"></script><script src="faux-supabase.js"></script>');
fs.writeFileSync(path.join(WWW, 'index.html'), html);
// Une fausse capture
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
fs.writeFileSync(path.join(ICI, 'capture.png'), png);

const srv = http.createServer((q, r) => { let f = path.join(WWW, decodeURIComponent(q.url.split('?')[0].split('#')[0])); if (f.endsWith('/')) f += 'index.html'; fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); r.end(); return; } r.writeHead(200, { 'Content-Type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/octet-stream' }); r.end(d); }); });
srv.listen(8765, async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const erreurs = []; p.on('pageerror', e => erreurs.push('page : ' + e.message)); p.on('console', m => { if (m.type() === 'error') erreurs.push('console : ' + m.text()); });
  p.on('dialog', d => d.accept());
  const etape = async (nom, fn) => { try { await fn(); console.log('OK  ' + nom); } catch (e) { console.log('ÉCHEC ' + nom + ' : ' + e.message.split('\n')[0]); await p.screenshot({ path: path.join(ICI, 'echec.png'), fullPage: true }); throw e; } };
  try {
    await p.goto('http://localhost:8765/#admin-saison'); await p.waitForTimeout(800);
    await etape('onglets Matchs et Saison visibles', async () => { const t = await p.textContent('#adm-tabs'); if (!/Matchs/.test(t) || !/Saison/.test(t)) throw new Error(t); });
    await etape('créer la saison Aurora', async () => {
      await p.click('[data-act="sa-nouvelle"]'); await p.fill('#s-nom', 'Aurora'); await p.fill('#s-debut', '2026-11-10'); await p.fill('#s-fin', '2027-01-21');
      await p.click('#modal-f button:has-text("Enregistrer")'); await p.waitForTimeout(400);
      const t = await p.textContent('#sa-liste'); if (!/Aurora/.test(t) || !/Saison active/.test(t) || !/estimée/.test(t)) throw new Error(t.slice(0, 300));
      console.log('     ' + t.replace(/\s+/g, ' ').slice(0, 260));
    });
    await etape('dimanche obligatoire pour le premier provisoire', async () => {
      await p.click('[data-act="sa-modifier"]'); await p.fill('#s-pp', '2026-11-28'); await p.click('#modal-f button:has-text("Enregistrer")'); await p.waitForTimeout(200);
      const e = await p.textContent('#a-err'); if (!/dimanche/.test(e)) throw new Error(e);
      await p.fill('#s-pp', '2026-11-29'); await p.click('#modal-f button:has-text("Enregistrer")'); await p.waitForTimeout(400);
      const t = await p.textContent('#sa-liste'); if (!/29\/11\/2026/.test(t)) throw new Error(t.slice(0, 300));
    });
    await p.goto('http://localhost:8765/#admin-matchs'); await p.waitForTimeout(600);
    await etape('nouveau match : saisie de démarrage affichée', async () => { await p.click('[data-act="m-nouveau"]'); await p.waitForTimeout(400); const t = await p.textContent('#modal-b'); if (!/Saisie de démarrage/.test(t)) throw new Error(t.slice(0, 200)); });
    await etape('envoyer une capture', async () => {
      await p.setInputFiles('#e-files', path.join(ICI, 'capture.png')); await p.click('[data-act="ed-envoyer"]'); await p.waitForFunction(() => !/en cours/.test(document.querySelector('#ed-info').textContent), null, { timeout: 8000 });
      const t = await p.textContent('#ed-info'); if (!/1 capture/.test(t)) throw new Error(t);
      const titre = await p.textContent('#modal-t'); if (!/M-\d+/.test(titre)) throw new Error(titre);
    });
    const lignes = [];
    for (let i = 1; i <= 8; i++) lignes.push({ faction: i % 2 ? 'HAAVK' : 'GTI', pseudo: i === 1 ? 'PKL¬Un' : 'Joueur' + i, score: 1000 + i, elim: i, morts: 2, assist: 1, med: 0, ing: 10, obj: 20, tac: 5 });
    for (let i = 1; i <= 8; i++) lignes.push({ faction: i % 2 ? 'GTI' : 'HAAVK', pseudo: 'Invité' + i, score: 900, elim: 3, morts: 4, assist: 1, med: 0, ing: 0, obj: 5, tac: 1 });
    lignes.push({ faction: 'GTI', pseudo: 'Joueur9', score: 1, elim: 0, morts: 0, assist: 0, med: 0, ing: 0, obj: 0, tac: 0 });
    await etape('coller la réponse de claude.ai', async () => {
      await p.fill('#e-coller', 'Voici le résultat :\n```json\n' + JSON.stringify({ carte: 'Faille', mode: 'Warfare', fin: '2026-11-18T16:40', lignes }) + '\n```');
      await p.click('[data-act="ed-coller"]'); await p.waitForTimeout(300);
      const n = await p.$$eval('#ed-table tbody tr[data-i]', x => x.length); if (n !== 17) throw new Error(n + ' lignes');
      const fin = await p.inputValue('#e-fin'); if (fin !== '2026-11-18T16:40') throw new Error('fin ' + fin);
      const carte = await p.inputValue('#e-carte'); if (carte !== 'Faille') throw new Error('carte ' + carte);
      const r1 = await p.textContent('#res-0'); if (!/DFMM-1/.test(r1)) throw new Error('ligne 1 : ' + r1);
      const r17 = await p.textContent('#res-16'); if (!/identifier/i.test(r17)) throw new Error('ligne 17 : ' + r17);
    });
    await etape('contrôles : 17 joueurs, écart 1 accepté, 1 ligne à identifier', async () => {
      const c = await p.textContent('#ed-ctrl'); console.log('     ' + c.replace(/\s+/g, ' ').slice(0, 220));
      if (!/17 participant/.test(c) || !/à identifier/.test(c)) throw new Error(c);
      if (await p.isDisabled('#ed-valider')) throw new Error('bouton bloqué');
    });
    await etape('écart de 3 → validation bloquée', async () => {
      await p.selectOption('tr[data-i="9"] select[data-f="faction"]', 'GTI'); await p.waitForTimeout(200);
      const c = await p.textContent('#ed-ctrl'); if (!/Écart/.test(c)) throw new Error(c);
      if (!(await p.isDisabled('#ed-valider'))) throw new Error('bouton actif');
      await p.selectOption('tr[data-i="9"] select[data-f="faction"]', 'HAAVK'); await p.waitForTimeout(200);
    });
    await etape('valider le match', async () => {
      await p.click('#ed-valider'); await p.waitForTimeout(800);
      const t = await p.textContent('#modal-t'); if (!/Validé/.test(t)) throw new Error(t);
      const reg = await p.textContent('#modal-b'); if (!/Registre/.test(reg) || !/Capture reçue/.test(reg)) throw new Error('registre');
    });
    await etape('liste des matchs', async () => {
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(500);
      const t = await p.textContent('#ma-liste'); if (!/Validé/.test(t) || !/8\/17/.test(t)) throw new Error(t.slice(0, 300));
      console.log('     ' + t.replace(/\s+/g, ' ').slice(0, 200));
    });
    await etape('identifier la ligne après validation', async () => {
      await p.click('[data-act="m-ouvrir"]'); await p.waitForTimeout(500);
      await p.selectOption('#idf-16', '__ni'); await p.click('[data-act="ed-identifier"][data-i="16"]'); await p.waitForTimeout(600);
      const r = await p.textContent('#res-16'); if (!/confirmé/.test(r) || !/identifiée le/.test(r)) throw new Error(r);
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(400);
    });
    await etape('repasser en brouillon (motif obligatoire)', async () => {
      await p.click('[data-act="m-ouvrir"]'); await p.waitForTimeout(500);
      await p.click('#modal-f button:has-text("Repasser en brouillon")'); await p.waitForTimeout(200);
      if (!/motif/i.test(await p.textContent('#ed-err'))) throw new Error('pas de message');
      await p.fill('#e-motif', 'Essai'); await p.click('#modal-f button:has-text("Repasser en brouillon")'); await p.waitForTimeout(600);
      if (!/Brouillon/.test(await p.textContent('#modal-t'))) throw new Error(await p.textContent('#modal-t'));
    });
    await p.screenshot({ path: path.join(ICI, 'editeur.png'), fullPage: false });
    await p.setViewportSize({ width: 390, height: 844 }); await p.waitForTimeout(300);
    await p.screenshot({ path: path.join(ICI, 'editeur-telephone.png'), fullPage: false });
  } catch (e) { process.exitCode = 1; }
  if (erreurs.length) process.exitCode = 1;
  console.log(erreurs.length ? 'ERREURS JS :\n' + erreurs.join('\n') : 'Aucune erreur JavaScript.');
  console.log('Captures d\'écran : ' + ICI);
  console.log('Appels RPC : ' + (await p.evaluate(() => (window.APPELS || []).map(a => a[0]).join(', '))));
  await b.close(); srv.close();
});
