// Essai de bout en bout des écrans Saison, Matchs (lot 3A) et Classements (lot 3C), dans Chromium, avec une fausse base en mémoire
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
  saisons: [], sanctions: [], dossiers: [], convocations: [], messages_litige: [], lots: [], actualites: [], messages: [{ id: 900, membre_id: 2, de_katana: false, texte: 'Bonjour Katana, une question', publication_id: null, cree_le: '2026-11-21T10:00:00Z', lu_le: null }], publications: [], matchs: [], match_lignes: [], captures: [], registre: [], journal: [], demandes: [], notifications: [], volsever_appels: [], parametres_historique: [], membres_prives: [] };
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
  await p.clock.setFixedTime(new Date('2026-11-22T07:00:00Z'));   // dimanche 22/11/2026, 10 h à Madagascar
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
    await etape('classement : coupure future refusée (premier provisoire du 29/11)', async () => {
      await p.goto('http://localhost:8765/#admin-classements'); await p.waitForTimeout(700);
      if (await p.inputValue('#cl-date') !== '2026-11-29') throw new Error('date ' + await p.inputValue('#cl-date'));
      await p.click('[data-act="cl-calculer"]'); await p.waitForTimeout(700);
      const t = await p.textContent('#cl-res'); if (!/pas encore passée/.test(t)) throw new Error(t.slice(0, 300));
      if (!(await p.isDisabled('[data-act="cl-publier"]'))) throw new Error('bouton actif');
    });
    await etape('classement : calcul au 22/11 (coupure du samedi 21/11 à 16 h)', async () => {
      await p.fill('#cl-date', '2026-11-22'); await p.dispatchEvent('#cl-date', 'change'); await p.waitForTimeout(200);
      if (!/21\/11\/2026 à 16 h 00/.test(await p.textContent('#cl-coupure-txt'))) throw new Error(await p.textContent('#cl-coupure-txt'));
      await p.click('[data-act="cl-calculer"]'); await p.waitForTimeout(700);
      const t = await p.textContent('#cl-res'); console.log('     ' + t.replace(/\s+/g, ' ').slice(0, 240));
      if (!/1matchscomptés/.test(t.replace(/\s+/g, '')) || !/8joueursclassés/.test(t.replace(/\s+/g, ''))) throw new Error('chiffres');
      if (!/MOST Eliminator/.test(t) || !/Faux 7/.test(t)) throw new Error('catégories');
      if (await p.isDisabled('[data-act="cl-publier"]')) throw new Error('bouton bloqué');
    });
    await etape('classement : publication (cases obligatoires)', async () => {
      await p.click('[data-act="cl-publier"]'); await p.waitForTimeout(300);
      if (!/Cochez/.test(await p.textContent('#toast'))) throw new Error('pas de rappel des cases');
      for (const c of ['#cl-v1', '#cl-v2', '#cl-v3']) await p.check(c);
      await p.click('[data-act="cl-publier"]'); await p.waitForTimeout(800);
      const l = await p.textContent('#cl-liste'); if (!/Classement provisoire n°1/.test(l)) throw new Error(l);
    });
    await etape('page publique : classement visible', async () => {
      await p.goto('http://localhost:8765/#classements'); await p.waitForTimeout(700);
      const t = await p.textContent('#cl-body'), m = await p.textContent('#cl-meta');
      if (!/Classement provisoire n°1/.test(m) || !/Aurora/.test(m)) throw new Error(m);
      if (!/Faux 7/.test(t)) throw new Error(t.slice(0, 200));
      await p.goto('http://localhost:8765/#accueil'); await p.waitForTimeout(500);
      const b = await p.textContent('#home-board'); if (!/Faux 8/.test(b) || !/Aurora/.test(b)) throw new Error(b.slice(0, 200));
      await p.screenshot({ path: path.join(ICI, 'classements.png'), fullPage: false });
      await p.goto('http://localhost:8765/#admin-matchs'); await p.waitForTimeout(600);
    });
    const premierCl = async () => { await p.goto('http://localhost:8765/#admin-classements'); await p.waitForTimeout(600); await p.fill('#cl-date', '2026-11-22'); await p.dispatchEvent('#cl-date', 'change'); await p.click('[data-act="cl-calculer"]'); await p.waitForTimeout(700); return p.textContent('#cl-res .cl-card'); };
    await etape('sanction : statistiques de DFMM-8 retirées dans le match', async () => {
      await p.goto('http://localhost:8765/#admin-sanctions'); await p.waitForTimeout(600);
      await p.click('[data-act="sa2-nouvelle"]'); await p.waitForTimeout(400);
      await p.selectOption('#sn-m', '8'); await p.selectOption('#sn-cat', { index: 4 });
      if (await p.inputValue('#sn-type') !== 'retrait_statistiques') throw new Error('type proposé ' + await p.inputValue('#sn-type'));
      const mid = await p.evaluate(() => window.FAUSSE_BASE.matchs[0].id);
      await p.fill('#sn-mid', String(mid)); await p.fill('#sn-motif', 'Compte prêté');
      await p.click('#modal-f button:has-text("Appliquer")'); await p.waitForTimeout(600);
      const t = await p.textContent('#sa2-liste'); if (!/Statistiques d’un match retirées/.test(t) || !/DFMM-8/.test(t)) throw new Error(t.slice(0, 200));
      const c = await premierCl(); if (/Faux 8/.test(c.slice(0, 200)) && !/Faux 7/.test(c)) throw new Error(c.slice(0, 200));
      if (!/Faux 7/.test(c)) throw new Error('MOST Eliminator : ' + c.slice(0, 200));
    });
    await etape('sanction levée : DFMM-8 recompté', async () => {
      await p.goto('http://localhost:8765/#admin-sanctions'); await p.waitForTimeout(600);
      await p.click('[data-act="sa2-lever"]'); await p.fill('#sd-motif', 'Erreur'); await p.click('#modal-f button:has-text("Enregistrer")'); await p.waitForTimeout(600);
      if (!/Levée/.test(await p.textContent('#sa2-liste'))) throw new Error('pas levée');
      const c = await premierCl(); if (!/Faux 8/.test(c)) throw new Error('MOST Eliminator : ' + c.slice(0, 200));
      await p.goto('http://localhost:8765/#admin-matchs'); await p.waitForTimeout(600);
    });
    await etape('litige : match mis en attente → dossier ouvert', async () => {
      await p.click('[data-act="m-ouvrir"]'); await p.waitForTimeout(500);
      await p.fill('#e-motif', 'Vérification'); await p.click('#modal-f button:has-text("Repasser en brouillon")'); await p.waitForTimeout(600);
      await p.fill('#e-motif', 'Deux captures différentes'); await p.click('#modal-f button:has-text("Mettre en attente")'); await p.waitForTimeout(600);
      if (!/En attente/.test(await p.textContent('#modal-t'))) throw new Error(await p.textContent('#modal-t'));
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(300);
      await p.goto('http://localhost:8765/#admin-litiges'); await p.waitForTimeout(600);
      const t = await p.textContent('#li-liste'); if (!/n° \d+/.test(t) || !/En cours/.test(t)) throw new Error(t.slice(0, 200));
      if (!/Litiges1/.test((await p.textContent('#adm-tabs')).replace(/\s+/g, ''))) throw new Error('compteur ' + await p.textContent('#adm-tabs'));
    });
    await etape('litige : qualifier, convoquer, écrire', async () => {
      await p.click('[data-act="li-ouvrir"]'); await p.waitForTimeout(600);
      await p.check('input[name="li-q"][value="oui"]'); await p.fill('#li-faits', 'Scores différents'); await p.click('[data-act="li-qualifier"]'); await p.waitForTimeout(500);
      await p.selectOption('#li-mb', '1'); await p.selectOption('#li-role', 'responsable'); await p.click('[data-act="li-convoquer"]'); await p.waitForTimeout(500);
      await p.fill('#li-msg', 'Expliquez-moi la différence.'); await p.click('[data-act="li-ecrire"]'); await p.waitForTimeout(500);
      const t = await p.textContent('#modal-b');
      if (!/Responsable : DFMM-1/.test(t) || !/Expliquez-moi la différence/.test(t) || !/à confirmer avant/.test(t)) throw new Error(t.slice(0, 400));
    });
    await etape('litige : trancher (vraie capture), discussion fermée', async () => {
      await p.check('input[name="li-cap"]'); await p.check('input[name="li-dec"][value="capture_retenue"]'); await p.fill('#li-motif', 'Capture confirmée');
      await p.click('[data-act="li-trancher"]'); await p.waitForTimeout(800);
      const t = await p.textContent('#modal-b');
      if (!/Discussion fermée/.test(t) || !/Vraie capture retenue/.test(t)) throw new Error(t.slice(0, 400) + ' | ' + await p.textContent('#li-err'));
      if ((await p.evaluate(() => window.FAUSSE_BASE.matchs[0].statut)) !== 'valide') throw new Error('match non validé');
    });
    await etape('litige : synthèse validée, dossier archivé', async () => {
      await p.fill('#li-syn', 'La capture reçue était la bonne.'); await p.click('[data-act="li-synthese"]'); await p.waitForTimeout(700);
      const t = await p.textContent('#modal-b'); if (!/Synthèse validée/.test(t)) throw new Error(t.slice(-300));
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(400);
      if (!/Archivé/.test(await p.textContent('#li-liste'))) throw new Error('pas archivé');
      await p.goto('http://localhost:8765/#admin-matchs'); await p.waitForTimeout(600);
    });
    await etape('titres et lots : lots confirmés, prévision d’attribution', async () => {
      await p.goto('http://localhost:8765/#admin-lots'); await p.waitForTimeout(800);
      await p.fill('#lo-d-most_elim', 'Lot test : 10 000 Ar'); await p.check('#lo-c-most_elim'); await p.check('#lo-c-most_med');
      await p.click('[data-act="lo-enregistrer"]'); await p.waitForTimeout(800);
      if (!(await p.isChecked('#lo-c-most_elim'))) throw new Error('lot non enregistré');
      const t = await p.textContent('#lo-attr');
      if (!/Prévision/.test(t) || !/Lot test : 10 000 Ar/.test(t) || !/Faux 8/.test(t)) throw new Error(t.slice(0, 400));
      if (!/au plus un lot \(1 lot\(s\) attribué/.test(t)) throw new Error('contrôle : ' + t.slice(-300));
      if (await p.$('[data-act="lo-attribuer"]')) throw new Error('bouton d’enregistrement visible sans classement final');
      await p.goto('http://localhost:8765/#admin-matchs'); await p.waitForTimeout(600);
    });
    await etape('actualités : publier, visible sur l’accueil, retirer', async () => {
      await p.goto('http://localhost:8765/#admin-actualites'); await p.waitForTimeout(600);
      await p.click('[data-act="ac-publier"]'); await p.waitForTimeout(200);
      if (await p.evaluate(() => window.FAUSSE_BASE.actualites.length)) throw new Error('publiée sans titre');
      await p.fill('#ac-titre', 'Bienvenue dans Aurora'); await p.fill('#ac-texte', 'Premier classement provisoire le 29/11.');
      await p.click('[data-act="ac-publier"]'); await p.waitForTimeout(600);
      if (!/En ligne/.test(await p.textContent('#ac-liste'))) throw new Error(await p.textContent('#ac-liste'));
      await p.goto('http://localhost:8765/#accueil'); await p.waitForTimeout(700);
      if (await p.isHidden('#home-actus-band') || !/Bienvenue dans Aurora/.test(await p.textContent('#home-actus'))) throw new Error('pas sur l’accueil');
      await p.goto('http://localhost:8765/#admin-actualites'); await p.waitForTimeout(600);
      await p.click('[data-act="ac-retirer"]'); await p.waitForTimeout(600);
      if (!/Retirée/.test(await p.textContent('#ac-liste'))) throw new Error('non retirée');
      await p.goto('http://localhost:8765/#accueil'); await p.waitForTimeout(700);
      if (!(await p.isHidden('#home-actus-band'))) throw new Error('actualité retirée encore visible');
    });
    await etape('messages : compteur, lecture, réponse de Katana', async () => {
      await p.goto('http://localhost:8765/#admin-messages'); await p.waitForTimeout(800);
      if (!/Messages1/.test((await p.textContent('#adm-tabs')).replace(/\s+/g, ''))) throw new Error('compteur ' + await p.textContent('#adm-tabs'));
      if (!/DFMM-2 Faux 2/.test(await p.textContent('#ms-liste'))) throw new Error(await p.textContent('#ms-liste'));
      await p.click('[data-act="ms-ouvrir"]'); await p.waitForTimeout(600);
      if (!/Bonjour Katana, une question/.test(await p.textContent('#modal-b'))) throw new Error(await p.textContent('#modal-b'));
      await p.fill('#ms-rep', 'Bonjour, je regarde.'); await p.click('#modal-f button:has-text("Envoyer")'); await p.waitForTimeout(700);
      if (!/Bonjour, je regarde/.test(await p.textContent('#modal-b'))) throw new Error('réponse absente');
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(600);
      if (/Messages1/.test((await p.textContent('#adm-tabs')).replace(/\s+/g, ''))) throw new Error('compteur non remis à zéro');
      await p.goto('http://localhost:8765/#admin-matchs'); await p.waitForTimeout(600);
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
