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
  saisons: [], sanctions: [], dossiers: [], convocations: [], messages_litige: [], lots: [], actualites: [], messages: [{ id: 900, membre_id: 2, de_katana: false, texte: 'Bonjour Katana, une question', publication_id: null, cree_le: '2026-11-21T10:00:00Z', lu_le: null }], publications: [], matchs: [], match_lignes: [], captures: [], registre: [], journal: [], demandes: [], notifications: [], volsever_appels: [], parametres_historique: [], membres_prives: [],
  // Calendrier des matchs de Katana (migration 0016) : 1re date le mercredi 25/11/2026 sur Ascension, à 16 h 05.
  jours_match: [['2026-11-25', 'Ascension'], ['2026-11-28', 'Ligne de tranchées'], ['2026-12-02', 'Accident de train'], ['2026-12-05', "Canal d'Akh"]]
    .map(([jour, carte], i) => ({ id: 800 + i, jour, debut: jour + 'T13:05:00Z', carte, statut: 'prevu', motif: null })),
  salles: [], participations: [], evenements: [] };
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
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
  await p.clock.setFixedTime(new Date('2026-11-22T07:00:00Z'));   // dimanche 22/11/2026, 10 h à Madagascar
  const erreurs = []; p.on('pageerror', e => erreurs.push('page : ' + e.message)); p.on('console', m => { if (m.type() === 'error') erreurs.push('console : ' + m.text()); });
  p.on('dialog', d => d.accept(d.type() === 'prompt' ? (global.REPONSE_PROMPT || '') : undefined));
  const etape = async (nom, fn) => { try { await fn(); console.log('OK  ' + nom); } catch (e) { console.log('ÉCHEC ' + nom + ' : ' + e.message.split('\n')[0]); await p.screenshot({ path: path.join(ICI, 'echec.png'), fullPage: true }); throw e; } };
  try {
    await p.goto('http://localhost:8765/#admin-saison'); await p.waitForTimeout(800);
    await etape('onglets Matchs et Saison visibles', async () => { const t = await p.textContent('#adm-tabs'); if (!/Matchs/.test(t) || !/Saison/.test(t)) throw new Error(t); });
    await etape('ancien prototype retiré : Tableau de bord, Décisions, Participer', async () => {
      const t = await p.textContent('#adm-tabs'); if (/Tableau de bord|Décisions/.test(t)) throw new Error(t);
      if (await p.$('#adm-decisions, [data-view="participer"], #dem-form')) throw new Error('élément de l’ancien prototype encore présent');
      for (const h of ['#admin-bord', '#admin-decisions']) {
        await p.goto('http://localhost:8765/' + h); await p.waitForTimeout(300);
        const on = await p.textContent('#adm-tabs a.on'); if (!/Paramètres|Saison/.test(on)) throw new Error(h + ' → ' + on);
      }
      await p.goto('http://localhost:8765/#participer'); await p.waitForTimeout(300);
      if (!(await p.isVisible('[data-view="inscription"]'))) throw new Error('#participer ne mène pas à Inscription');
      await p.goto('http://localhost:8765/#admin-saison'); await p.waitForTimeout(500);
    });
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
      await p.fill('#e-coller', 'Voici le résultat :\n```json\n' + JSON.stringify({ carte: 'Faille', mode: 'Warfare', fin: '2026-11-18T16:40', effectif: { HAAVK: 8, GTI: 9 }, lignes }) + '\n```');
      await p.click('[data-act="ed-coller"]'); await p.waitForTimeout(300);
      const n = await p.$$eval('#ed-table tbody tr[data-i]', x => x.length); if (n !== 17) throw new Error(n + ' lignes');
      const fin = await p.inputValue('#e-fin'); if (fin !== '2026-11-18T16:40') throw new Error('fin ' + fin);
      const carte = await p.inputValue('#e-carte'); if (carte !== 'Faille') throw new Error('carte ' + carte);
      const r1 = await p.textContent('#res-0'); if (!/DFMM-1/.test(r1)) throw new Error('ligne 1 : ' + r1);
      const r17 = await p.textContent('#res-16'); if (!/identifier/i.test(r17)) throw new Error('ligne 17 : ' + r17);
    });
    await etape('début annoncé obligatoire pour un match de Katana (retard pour tous les matchs)', async () => {
      if (!(await p.isDisabled('#ed-valider'))) throw new Error('bouton actif sans début annoncé');
      const nr = await p.$$eval('#ed-criteres li.b', x => x.map(e => e.textContent));
      if (!nr.some(t => /Début annoncé du match/.test(t))) throw new Error(JSON.stringify(nr));
      await p.fill('#e-debut', '2026-11-18T17:00'); await p.dispatchEvent('#e-debut', 'change'); await p.waitForTimeout(200);
      const at = await p.$$eval('#ed-criteres li.w', x => x.map(e => e.textContent));
      if (!at.some(t => /Fin au plus 1 h après le début annoncé/.test(t))) throw new Error('fin avant le début non signalée : ' + JSON.stringify(at));
      await p.fill('#e-debut', '2026-11-18T16:00'); await p.dispatchEvent('#e-debut', 'change'); await p.waitForTimeout(200);
      const ok = await p.$$eval('#ed-criteres li.o', x => x.map(e => e.textContent));
      if (!ok.some(t => /Fin au plus 1 h après le début annoncé/.test(t)) || !ok.some(t => /Début annoncé du match/.test(t))) throw new Error(JSON.stringify(ok));
    });
    await etape('contrôles : 17 joueurs, écart 1 accepté, 1 ligne à identifier, critères en bas', async () => {
      const c = await p.textContent('#ed-ctrl'); console.log('     ' + c.replace(/\s+/g, ' ').slice(0, 220));
      if (!/17 participant/.test(c) || !/à identifier/.test(c)) throw new Error(c);
      if (await p.isDisabled('#ed-valider')) throw new Error('bouton bloqué');
      if (/Lecture de la capture à corriger/.test(c)) throw new Error('effectif juste signalé à tort');
      const place = await p.evaluate(() => { const b = document.getElementById('ed-ctrl'), t = document.getElementById('ed-table'), m = document.getElementById('e-motif');
        return { colle: getComputedStyle(b).position, apresTableau: !!(t.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING), avantMotif: !!(b.compareDocumentPosition(m) & Node.DOCUMENT_POSITION_FOLLOWING) }; });
      if (place.colle === 'sticky' || place.colle === 'fixed' || !place.apresTableau || !place.avantMotif) throw new Error('critères mal placés : ' + JSON.stringify(place));
    });
    await etape('écart de 3 → validation bloquée, critère non rempli, motif proposé', async () => {
      await p.selectOption('tr[data-i="9"] select[data-f="faction"]', 'GTI'); await p.waitForTimeout(200);
      const c = await p.textContent('#ed-ctrl'); if (!/Écart/.test(c)) throw new Error(c);
      if (!(await p.isDisabled('#ed-valider'))) throw new Error('bouton actif');
      const nonRemplis = await p.$$eval('#ed-criteres li.b', x => x.map(e => e.textContent));
      if (nonRemplis.length !== 1 || !/écart 3/.test(nonRemplis[0])) throw new Error('critères : ' + JSON.stringify(nonRemplis));
      const remplis = await p.$$eval('#ed-criteres li.o', x => x.length); if (remplis < 8) throw new Error(remplis + ' critères remplis');
      await p.click('[data-act="ed-motif-auto"]'); await p.waitForTimeout(100);
      const motif = await p.inputValue('#e-motif'); if (!/^Critère\(s\) non rempli\(s\) : Écart d’effectif de 3/.test(motif)) throw new Error('motif : ' + motif);
      await p.locator('#ed-ctrl').screenshot({ path: path.join(ICI, 'criteres.png') });
      await p.fill('#e-motif', '');
      await p.selectOption('tr[data-i="9"] select[data-f="faction"]', 'HAAVK'); await p.waitForTimeout(200);
      if (await p.$('[data-act="ed-motif-auto"]')) throw new Error('bouton du motif encore là');
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
    await etape('matchs libres : créneaux, demande retenue acceptée', async () => {
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(300);
      await p.evaluate(() => {
        const DB = window.FAUSSE_BASE, s = DB.saisons[0].id;
        DB.creneaux = [
          { id: 700, saison_id: s, organisateur_id: 1, resp_haavk_id: 1, resp_gti_id: 2, debut: '2026-11-21T12:00:00Z', statut: 'annonce', vu_le: null },
          { id: 701, saison_id: s, organisateur_id: 4, resp_haavk_id: 4, resp_gti_id: 3, debut: '2026-11-23T12:00:00Z', statut: 'retenu', retenu_motif: 'Matricule non autorisé : responsable GTI DFMM-3', vu_le: null }];
        DB.matchs.push({ id: 710, saison_id: s, type: 'libre', demarrage: false, statut: 'brouillon', creneau_id: 700, fin: null, cree_le: '2026-11-20T10:00:00Z' });
        DB.captures.push({ id: 720, match_id: 710, chemin: '710/m1-1.jpg', envoyee_le: '2026-11-21T12:50:00Z', statut: 'recue', envoyeur_id: 1, partie: 'unique' },
                         { id: 721, match_id: 710, chemin: '710/m2-1.jpg', envoyee_le: '2026-11-21T13:20:00Z', statut: 'recue', envoyeur_id: 2, partie: 'unique' });
      });
      await p.goto('http://localhost:8765/#admin-creneaux'); await p.waitForTimeout(900);
      const t = await p.textContent('#cr-liste');
      if (!/L-700/.test(t) || !/En attente de Katana/.test(t) || !/responsable GTI DFMM-3/.test(t)) throw new Error(t.slice(0, 300));
      if ((await p.evaluate(() => window.FAUSSE_BASE.creneaux[0].vu_le)) === null) throw new Error('alerte non marquée vue');
      await p.click('[data-act="cr-decider"][data-d="accepter"]'); await p.waitForTimeout(700);
      if ((await p.evaluate(() => window.FAUSSE_BASE.creneaux[1].statut)) !== 'annonce') throw new Error('non acceptée');
    });
    await etape('match libre : capture en retard signalée, retard accepté', async () => {
      await p.click('#cr-liste .card-l:has-text("L-700") [data-act="m-ouvrir"]'); await p.waitForTimeout(800);
      if (!/Match libre M-710/.test(await p.textContent('#modal-t')) || !/Match libre L-700/.test(await p.textContent('#modal-b'))) throw new Error(await p.textContent('#modal-t'));
      await p.fill('#e-fin', '2026-11-21T15:45'); await p.dispatchEvent('#e-fin', 'change'); await p.waitForTimeout(500);
      const t = await p.textContent('#ed-thumbs');
      if (!/DFMM-2 Faux 2 \(responsable GTI\)/.test(t) || !/35 min après la fin/.test(t) || !/sera rejetée à la validation/.test(t)) throw new Error(t);
      global.REPONSE_PROMPT = 'Coupure réseau, vidéo reçue';
      await p.click('[data-act="ed-retard"]'); await p.waitForTimeout(600); global.REPONSE_PROMPT = '';
      if (!/retard accepté : Coupure réseau/.test(await p.textContent('#ed-thumbs'))) throw new Error('retard non accepté');
    });
    await etape('match libre : lectures différentes → attente proposée ; identiques → une seule gardée', async () => {
      const lec = (carte, elim) => JSON.stringify({ carte, mode: 'Conquête', fin: '2026-11-21T15:45', vainqueur: 'HAAVK', lisible: true, lignes: [
        { faction: 'HAAVK', pseudo: 'PKL¬Un', score: 1000, elim, morts: 2, assist: 1, med: 0, ing: 0, obj: 3, tac: 1 },
        { faction: 'GTI', pseudo: 'Joueur2', score: 900, elim: 4, morts: 3, assist: 0, med: 0, ing: 0, obj: 2, tac: 0 }] });
      await p.fill('#lec-1', lec('Faille', 5)); await p.fill('#lec-2', lec('Faille', 6));
      await p.click('[data-act="ed-comparer"]'); await p.waitForTimeout(600);
      let t = await p.textContent('#ed-conc');
      if (!/Captures différentes/.test(t) || !/PKL¬Un : Élim\. 5 \/ 6/.test(t)) throw new Error(t.slice(0, 300));
      await p.fill('#lec-2', lec('Faille', 5)); await p.click('[data-act="ed-comparer"]'); await p.waitForTimeout(600);
      t = await p.textContent('#ed-conc'); if (!/Captures concordantes/.test(t)) throw new Error(t.slice(0, 300));
      await p.click('[data-act="ed-garder"]'); await p.waitForTimeout(800);
      const st = await p.evaluate(() => window.FAUSSE_BASE.captures.filter(c => c.match_id === 710).map(c => c.statut).join(','));
      if (st !== 'recue,ecartee') throw new Error(st);
      if ((await p.$$('#ed-table tbody tr')).length !== 2) throw new Error('lignes : ' + (await p.$$('#ed-table tbody tr')).length);
      if (!(await p.evaluate(() => window.FAUSSE_BASE.captures.find(c => c.id === 720).lecture))) throw new Error('lecture non gardée');
    });
    await etape('inscriptions : vérifications automatiques, code Messenger obligatoire, revérifier', async () => {
      await p.evaluate(() => {
        const DB = window.FAUSSE_BASE;
        DB.membres.push({ id: 50, matricule: null, nom_gamer: 'Faux Candidat', statut: 'en_attente', cree_le: '2026-11-22T05:00:00Z' },
                        { id: 51, matricule: null, nom_gamer: 'Faux Muet', statut: 'en_attente', cree_le: '2026-11-22T05:30:00Z' });
        DB.comptes_jeu.push({ id: 60, membre_id: 50, uid: '9914050', pseudo: 'PKL¬Officiel', statut: 'en_pause' }, { id: 61, membre_id: 51, uid: '9914051', pseudo: 'Muet', statut: 'en_pause' });
        DB.membres_prives.push({ membre_id: 50, nom_reel: 'Faux', email: 'c50@test.invalid', facebook: 'facebook.com/faux50', residence: 'Madagascar', province: 'Antananarivo', zone: 'Périphérie', comprend_mg: true, code_messenger: 'UV-ABC234',
          verifications: { volsever: { resultat: 'trouve', pseudo_declare: 'PKL Officiel', pseudo_officiel: 'PKL¬Officiel', le: '2026-11-22T05:00:00Z' }, email: { resultat: 'ok', le: '2026-11-22T05:00:00Z' } } },
          { membre_id: 51, nom_reel: 'Faux', email: 'c51@test.invalid', facebook: 'facebook.com/faux51', residence: 'Madagascar', province: 'Antananarivo', zone: 'Périphérie', comprend_mg: true, code_messenger: 'UV-XYZ789',
          verifications: { volsever: { resultat: 'delai', pseudo_declare: 'Muet', le: '2026-11-22T05:30:00Z' }, email: { resultat: 'non_verifie', le: '2026-11-22T05:30:00Z' } } });
        window.FAUX_INVOKE = (n, o) => {
          if (n !== 'pseudo-volsever' || !o.body.reverifier_inscription) return { data: null, error: null };
          const pr = DB.membres_prives.find(x => x.membre_id === o.body.reverifier_inscription);
          pr.verifications = Object.assign({}, pr.verifications, { volsever: { resultat: 'trouve', pseudo_declare: 'Muet', pseudo_officiel: 'Muet', le: new Date().toISOString(), reverifie: true } });
          return { data: { verification: pr.verifications.volsever }, error: null };
        };
      });
      if (await p.isVisible('#modal-f button:has-text("Fermer")')) { await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(300); }
      await p.goto('http://localhost:8765/#admin-inscriptions'); await p.waitForTimeout(900);
      const carte = n => p.locator('#ins-liste .card-l', { hasText: n });
      let t = await carte('Faux Candidat').textContent();
      if (!/Pseudo différent/.test(t) || !/officiel « PKL¬Officiel »/.test(t) || !/reçoit des e-mails/.test(t) || !/UV-ABC234/.test(t)) throw new Error(t.slice(0, 400));
      if (await carte('Faux Candidat').locator('[data-act="ins-reverifier"]').count()) throw new Error('Revérifier affiché pour un UID trouvé');
      t = await carte('Faux Muet').textContent();
      if (!/n’a pas répondu à temps/.test(t) || !/domaine non vérifié/.test(t)) throw new Error(t.slice(0, 400));
      // Approbation sans le code Messenger : refusée
      await p.evaluate(() => { document.querySelector('input[name="dec-50"][value="approuver"]').checked = true; ['vc-50', 'vo-50'].forEach(i => { document.getElementById(i).checked = true; }); });
      await p.click('[data-act="ins-decider"][data-id="50"]'); await p.waitForTimeout(300);
      if (!/trois vérifications/.test(await p.textContent('#er-50'))) throw new Error(await p.textContent('#er-50'));
      const nbDec = await p.evaluate(() => (window.APPELS || []).filter(a => a[0] === 'decider_inscription').length);
      if (nbDec) throw new Error('décision envoyée sans le code');
      // Revérifier le candidat muet
      await carte('Faux Muet').locator('[data-act="ins-reverifier"]').click(); await p.waitForTimeout(900);
      t = await carte('Faux Muet').textContent();
      if (!/UID et pseudo confirmés/.test(t)) throw new Error(t.slice(0, 400));
      const appel = await p.evaluate(() => (window.APPELS || []).find(a => a[0] === 'fonction:pseudo-volsever'));
      if (!appel || appel[1].reverifier_inscription !== 51) throw new Error(JSON.stringify(appel));
      await p.screenshot({ path: path.join(ICI, 'inscriptions.png'), fullPage: false });
    });
    await etape('calendrier : dates, code de la salle, report puis rétablissement', async () => {
      await p.goto('http://localhost:8765/#admin-calendrier'); await p.waitForTimeout(900);
      const t = await p.textContent('#cal-liste');
      if (!/mercredi 25 novembre 2026 à 16 h 05/.test(t) || !/Carte : Ascension/.test(t) || !/samedi 28 novembre 2026/.test(t)) throw new Error(t.slice(0, 300));
      await p.fill('#cal-code-800', '4242'); await p.fill('#cal-mdp-800', 'uv'); await p.click('[data-act="cal-salle"][data-id="800"]'); await p.waitForTimeout(500);
      const sa = await p.evaluate(() => JSON.stringify(window.FAUSSE_BASE.salles.map(x => [x.jour_id, x.code, x.mot_de_passe])));
      if (sa !== '[[800,"4242","uv"]]') throw new Error(sa);
      global.REPONSE_PROMPT = '';
      await p.click('[data-act="cal-decider"][data-d="reporter"][data-id="801"]'); await p.waitForTimeout(600);
      let c = await p.evaluate(() => window.FAUSSE_BASE.jours_match.map(j => j.statut + ' ' + j.carte).join(' | '));
      if (c !== 'prevu Ascension | reporte Ligne de tranchées | prevu Ligne de tranchées | prevu Accident de train') throw new Error(c);
      if (!/Carte manquante/.test(await p.textContent('#cal-liste'))) throw new Error('motif absent');
      await p.click('[data-act="cal-decider"][data-d="retablir"][data-id="801"]'); await p.waitForTimeout(600);
      c = await p.evaluate(() => window.FAUSSE_BASE.jours_match.map(j => j.carte).join(' | '));
      if (c !== "Ascension | Ligne de tranchées | Accident de train | Canal d'Akh") throw new Error(c);
    });
    await etape('calendrier : « Saisir ce match » reprend la carte et le début annoncé', async () => {
      await p.click('[data-act="cal-saisir"][data-id="800"]'); await p.waitForTimeout(700);
      if (await p.inputValue('#e-debut') !== '2026-11-25T16:05' || await p.inputValue('#e-carte') !== 'Ascension') throw new Error(await p.inputValue('#e-debut') + ' ' + await p.inputValue('#e-carte'));
      if (!/Match du calendrier/.test(await p.textContent('#modal-b'))) throw new Error('note absente');
      await p.click('#modal-f button:has-text("Enregistrer")'); await p.waitForTimeout(500);
      const m = await p.evaluate(() => { const x = window.FAUSSE_BASE.matchs.find(m => m.jour_id === 800); return x ? x.carte + ' ' + x.debut_annonce : 'aucun'; });
      if (m !== 'Ascension 2026-11-25T16:05:00+03:00') throw new Error(m);
      await p.click('#modal-f button:has-text("Fermer")'); await p.waitForTimeout(600);
      if (!/Ouvrir le match M-/.test(await p.textContent('#cal-liste [data-jour="800"]'))) throw new Error('lien vers le match absent');
    });
    await etape('événement communautaire créé par Katana', async () => {
      await p.fill('#evc-titre', 'Tournoi de Noël'); await p.fill('#evc-debut', '2026-12-20T15:00'); await p.fill('#evc-desc', 'Ouvert à tous les membres.');
      await p.click('[data-act="evc-creer"]'); await p.waitForTimeout(600);
      const e = await p.evaluate(() => JSON.stringify(window.FAUSSE_BASE.evenements.map(x => [x.titre, x.debut])));
      if (e !== '[["Tournoi de Noël","2026-12-20T15:00:00+03:00"]]') throw new Error(e);
      if (!/Tournoi de Noël/.test(await p.textContent('#evc-liste'))) throw new Error('liste');
    });
    await etape('prochains événements : vue de Katana (noms, code, rotation, événement)', async () => {
      if (await p.isHidden('#nav-evenements')) throw new Error('lien du menu caché');
      await p.evaluate(() => { window.FAUSSE_BASE.participations.push({ jour_id: 800, membre_id: 3, cree_le: '2026-11-22T06:00:00Z' }); });
      await p.goto('http://localhost:8765/#evenements'); await p.waitForTimeout(800);
      const t = await p.textContent('#ev-zone');
      for (const x of ['Prochain match de Katana', 'mercredi 25 novembre 2026 à 16 h 05', 'Ascension', 'vers 15 h 50', '4242', 'DFMM-3 Faux 3', 'Craqué → Ascension', 'Tournoi de Noël', 'Matchs libres annoncés'])
        if (t.indexOf(x) < 0) throw new Error('absent : ' + x + ' — ' + t.slice(0, 300));
      if (await p.$('[data-act="ev-participer"]')) throw new Error('« Je participe » affiché à Katana (pas membre)');
    });
    await etape('rappels : bloc du téléphone, agenda (.ics) et liens Google Agenda, état pour Katana', async () => {
      const t = await p.textContent('#ev-rappels');
      for (const x of ['Rappels sur ce téléphone', 'Agenda du téléphone', 'même sans Internet', 'mer. 25/11 (Ascension)'])
        if (t.indexOf(x) < 0) throw new Error('absent : ' + x + ' — ' + t.slice(0, 300));
      if (/4242/.test(t)) throw new Error('code de la salle dans le bloc des rappels');
      const g = await p.getAttribute('#ev-rappels a[href*="calendar.google.com"]', 'href');
      if (!/dates=20261125T130500Z\/20261125T140500Z/.test(g)) throw new Error(g);
      const [dl] = await Promise.all([p.waitForEvent('download'), p.click('[data-act="rap-agenda"]')]);
      const ics = fs.readFileSync(await dl.path(), 'utf8');
      if (dl.suggestedFilename() !== 'league-uv-matchs.ics' || !/BEGIN:VEVENT[\s\S]*DTSTART:20261125T130500Z[\s\S]*TRIGGER:-PT35M/.test(ics) || /4242/.test(ics)) throw new Error(ics.slice(0, 400));
      await p.goto('http://localhost:8765/#admin-calendrier'); await p.waitForTimeout(900);
      const a = await p.textContent('#cal-rappels');
      if (!/Rappels sur les téléphones/.test(a) || !/2 \(2 personne/.test(a) || !/Activés/.test(a)) throw new Error(a.slice(0, 300));
      await p.goto('http://localhost:8765/#evenements'); await p.waitForTimeout(800);
    });
    await etape('prochains événements : membre actif (Je participe, code, organisateur d’un match libre)', async () => {
      await p.evaluate(() => { window.FAUX_ROLE = 'membre'; window.FAUX_MOI = 4; });
      await p.goto('http://localhost:8765/#accueil'); await p.goto('http://localhost:8765/#evenements'); await p.waitForTimeout(800);
      let t = await p.textContent('#ev-zone');
      if (/Noms/.test(t) || !/4242/.test(t)) throw new Error(t.slice(0, 300));
      await p.click('[data-act="ev-participer"][data-oui="1"]'); await p.waitForTimeout(600);
      if (await p.textContent('#ev-nb') !== '2' || !/Vous participez/.test(await p.textContent('#ev-prochain'))) throw new Error(await p.textContent('#ev-prochain'));
      // Match libre L-701 (organisateur DFMM-4, accepté plus haut) : l'organisateur saisit le code.
      await p.fill('#evl-code-701', 'L701'); await p.fill('#evl-mdp-701', 'libre'); await p.click('[data-act="ev-salle-libre"][data-id="701"]'); await p.waitForTimeout(600);
      t = await p.textContent('#ev-libres'); if (!/L701/.test(t) || !/DFMM-4 Faux 4/.test(t)) throw new Error(t.slice(0, 300));
      await p.setViewportSize({ width: 390, height: 844 }); await p.waitForTimeout(300);
      await p.screenshot({ path: path.join(ICI, 'evenements-telephone.png'), fullPage: true });
      const deborde = await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
      if (deborde) throw new Error('la page déborde sur téléphone');
      await p.setViewportSize({ width: 1280, height: 900 });
      await p.click('[data-act="ev-participer"][data-oui="0"]'); await p.waitForTimeout(600);
      if (await p.textContent('#ev-nb') !== '1') throw new Error('désinscription');
    });
    await etape('prochains événements : membre suspendu (ni code ni « Je participe »)', async () => {
      await p.evaluate(() => { window.FAUX_ROLE = 'suspendu'; window.FAUX_MOI = 2; });
      await p.goto('http://localhost:8765/#accueil'); await p.goto('http://localhost:8765/#evenements'); await p.waitForTimeout(800);
      const t = await p.textContent('#ev-zone');
      if (/4242|L701/.test(t) || !/réservés aux membres actifs non suspendus/.test(t) || await p.$('[data-act="ev-participer"]')) throw new Error(t.slice(0, 300));
      await p.evaluate(() => { window.FAUX_ROLE = 'admin'; });
    });
    await p.screenshot({ path: path.join(ICI, 'editeur.png'), fullPage: false });
    await p.setViewportSize({ width: 390, height: 844 }); await p.waitForTimeout(300);
    await p.screenshot({ path: path.join(ICI, 'editeur-telephone.png'), fullPage: false });
    await p.setViewportSize({ width: 1280, height: 900 });
    await etape('inscription : réponses gardées sur l’appareil (sauf mot de passe), lien cliquable vers la page DFMM, délai de traitement annoncé', async () => {
      await p.evaluate(() => localStorage.setItem('faux-visiteur', '1'));
      await p.goto('http://localhost:8765/#inscription'); await p.reload(); await p.waitForTimeout(800);
      const lien = await p.getAttribute('#f-inscription a[href*="facebook.com"]', 'href');
      if (lien !== 'https://www.facebook.com/share/1HwLd6ddVX/') throw new Error('lien : ' + lien);
      await p.fill('#i-nom_reel', 'Faux Nom'); await p.fill('#i-email', 'faux@test.invalid'); await p.check('#i-genre');
      await p.check('input[name="i-residence"][value="Madagascar"]'); await p.check('#i-acc_dfmm'); await p.fill('#i-mdp', 'secret123');
      await p.reload(); await p.waitForTimeout(800);
      const r = await p.evaluate(() => ({ nom: document.getElementById('i-nom_reel').value, mail: document.getElementById('i-email').value, genre: document.getElementById('i-genre').checked,
        prov: !document.querySelector('.fld[data-k="province"]').hidden, acc: document.getElementById('i-acc_dfmm').checked, mdp: document.getElementById('i-mdp').value,
        note: !!document.querySelector('#f-inscription .br-note'), stock: JSON.stringify(localStorage) }));
      if (r.nom !== 'Faux Nom' || r.mail !== 'faux@test.invalid' || !r.genre || !r.prov || !r.acc || r.mdp || !r.note) throw new Error(JSON.stringify(r).slice(0, 300));
      if (/secret123/.test(r.stock)) throw new Error('mot de passe gardé');
      await p.click('#f-inscription [data-act="br-effacer"]'); await p.waitForTimeout(200);
      const vide = await p.evaluate(() => !document.getElementById('i-nom_reel').value && !Object.keys(localStorage).some(k => k.indexOf('dfmm-brouillon|') === 0));
      if (!vide) throw new Error('« Effacer mes réponses » n’a pas tout effacé');
      await p.setViewportSize({ width: 390, height: 844 }); await p.fill('#i-nom_reel', 'Faux Nom'); await p.reload(); await p.waitForTimeout(800);
      await p.screenshot({ path: path.join(ICI, 'inscription-brouillon-telephone.png'), fullPage: false });
      if (await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1)) throw new Error('la page déborde sur téléphone');
      await p.setViewportSize({ width: 1280, height: 900 });
      // Envoi réussi : brouillon effacé, code Messenger avec le lien vers la page DFMM.
      for (const [k, x] of [['nom_gamer', 'Faux'], ['email', 'faux@test.invalid'], ['date_naissance', '2000-01-01'], ['facebook', 'https://facebook.com/faux'], ['pseudo', 'Faux'], ['uid', '99123456']]) await p.fill('#i-' + k, x);
      for (const [k, x] of [['genre', 'Homme'], ['residence', 'Madagascar'], ['zone', 'Ville principale'], ['comprend_mg', 'Oui'], ['parle_mg', 'Oui']]) await p.check('input[name="i-' + k + '"][value="' + x + '"]');
      await p.selectOption('#i-province', { index: 1 });
      for (const k of ['origine_mg', 'acc_dfmm', 'acc_uv', 'acc_donnees', 'acc_approbation']) await p.check('#i-' + k);
      await p.fill('#i-mdp', 'secret123'); await p.fill('#i-mdp2', 'secret123'); await p.setInputFiles('#i-capture', path.join(ICI, 'capture.png'));
      await p.evaluate(() => { window.FAUX_INVOKE = n => n === 'inscription' ? { data: { ok: true, code_messenger: 'UV-ABC123' }, error: null } : { data: null, error: null }; });
      await p.click('#f-inscription button[type="submit"]'); await p.waitForTimeout(800);
      const fin = await p.evaluate(() => ({ t: document.getElementById('ins-zone').textContent, liens: Array.from(document.querySelectorAll('#ins-zone a[href*="facebook.com"]')).map(a => a.href + '|' + a.target),
        reste: Object.keys(localStorage).filter(k => k.indexOf('dfmm-brouillon|') === 0) }));
      if (!/UV-ABC123/.test(fin.t) || !/Ouvrir la page DFMM/.test(fin.t) || !/comptez jusqu’à 48 h après l’envoi de votre code Messenger/.test(fin.t) || fin.liens.length < 2 || fin.liens.some(l => l !== 'https://www.facebook.com/share/1HwLd6ddVX/|_blank')) throw new Error(JSON.stringify(fin).slice(0, 300));
      if (fin.reste.length) throw new Error('brouillon gardé après l’envoi : ' + fin.reste);
      await p.screenshot({ path: path.join(ICI, 'inscription-code-messenger.png'), fullPage: false });
      await p.evaluate(() => { localStorage.clear(); });
    });
  } catch (e) { process.exitCode = 1; }
  if (erreurs.length) process.exitCode = 1;
  console.log(erreurs.length ? 'ERREURS JS :\n' + erreurs.join('\n') : 'Aucune erreur JavaScript.');
  console.log('Captures d\'écran : ' + ICI);
  console.log('Appels RPC : ' + (await p.evaluate(() => (window.APPELS || []).map(a => a[0]).join(', '))));
  await b.close(); srv.close();
});
