/* LEAGUE UV — DFMM : règles de calcul, sans affichage (testables à part). */
var L = (function () {
  'use strict';

  // Ordre des 8 colonnes sur la capture : score, éliminations, morts, assistances, médicale, ingénieur, objectif, tactique
  var STATS = [
    { k: 'score', label: 'Score du match', court: 'Score' },
    { k: 'elim', label: 'Éliminations', court: 'Élim.' },
    { k: 'morts', label: 'Morts', court: 'Morts' },
    { k: 'assist', label: 'Assistances', court: 'Assist.' },
    { k: 'med', label: 'Contribution médicale', court: 'Médic.' },
    { k: 'ing', label: 'Contribution ingénieur', court: 'Ingén.' },
    { k: 'obj', label: 'Contribution aux objectifs', court: 'Obj.' },
    { k: 'tac', label: 'Contribution tactique', court: 'Tact.' }
  ];

  // Ordre obligatoire de priorité des lots (guide, section 05)
  var CATS = [
    { key: 'most_elim', kind: 'MOST', fam: 'elim', label: 'MOST Eliminator', prio: 1 },
    { key: 'most_med', kind: 'MOST', fam: 'med', label: 'MOST Medic', prio: 2 },
    { key: 'most_ing', kind: 'MOST', fam: 'ing', label: 'MOST Engineer', prio: 3 },
    { key: 'most_tac', kind: 'MOST', fam: 'tac', label: 'MOST Tactician', prio: 4 },
    { key: 'most_obj', kind: 'MOST', fam: 'obj', label: 'MOST Objective', prio: 5 },
    { key: 'best_surv', kind: 'SURV', fam: 'morts', label: 'BEST Survivor', prio: 6 },
    { key: 'best_elim', kind: 'BEST', fam: 'elim', label: 'BEST Eliminator', prio: 7 },
    { key: 'best_med', kind: 'BEST', fam: 'med', label: 'BEST Medic', prio: 8 },
    { key: 'best_ing', kind: 'BEST', fam: 'ing', label: 'BEST Engineer', prio: 9 },
    { key: 'best_tac', kind: 'BEST', fam: 'tac', label: 'BEST Tactician', prio: 10 },
    { key: 'best_obj', kind: 'BEST', fam: 'obj', label: 'BEST Objective', prio: 11 }
  ];

  var DEFAULTS = {
    min_participants: 16, ecart_max: 1, pct_membres: 30, delai_capture: 30,
    duree_creneau_h: 6, periodicite: 14, coupure_jour: 6, coupure_heure: '17:00',
    audit_jours: 7, recours_h: 48, delai_changement_jours: 7, max_comptes: 2
  };

  var PROVINCES = [
    { p: 'Antananarivo', v: 'Antananarivo' }, { p: 'Antsiranana', v: 'Antsiranana' },
    { p: 'Fianarantsoa', v: 'Fianarantsoa' }, { p: 'Mahajanga', v: 'Mahajanga' },
    { p: 'Toamasina', v: 'Toamasina' }, { p: 'Toliara', v: 'Toliara' }
  ];

  var CARTES = ['Craqué', 'Ascension', 'Ligne de tranchées', 'Accident de train', "Canal d'Akh", 'Faille'];

  function regles(saison) {
    var R = {}, k;
    for (k in DEFAULTS) R[k] = DEFAULTS[k];
    if (saison) for (k in DEFAULTS) if (saison[k] !== undefined && saison[k] !== '' && saison[k] !== null) R[k] = typeof DEFAULTS[k] === 'number' ? Number(saison[k]) : saison[k];
    return R;
  }

  // ---------- Dates (heure locale de Madagascar, chaînes AAAA-MM-JJTHH:MM) ----------
  function pad(n) { return String(n).padStart(2, '0'); }
  function nowStr(d) {
    d = d || new Date();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  function validDT(s) { return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(String(s || '')); }
  function validD(s) { return /^\d{4}-\d{2}-\d{2}$/.test(String(s || '')); }
  function normDT(s) { s = String(s || '').trim().replace(' ', 'T'); return s.length >= 16 ? s.slice(0, 16) : s; }
  function toMs(s) {
    var p = String(s).split('T'), d = p[0].split('-').map(Number), t = (p[1] || '00:00').split(':').map(Number);
    return Date.UTC(d[0], d[1] - 1, d[2], t[0] || 0, t[1] || 0);
  }
  function fromMs(ms) {
    var x = new Date(ms);
    return x.getUTCFullYear() + '-' + pad(x.getUTCMonth() + 1) + '-' + pad(x.getUTCDate()) + 'T' + pad(x.getUTCHours()) + ':' + pad(x.getUTCMinutes());
  }
  function addDays(ds, n) { return fromMs(toMs(String(ds).slice(0, 10)) + n * 86400000).slice(0, 10); }
  function addMinutes(dts, n) { return fromMs(toMs(dts) + n * 60000); }
  function diffMinutes(a, b) { return Math.round((toMs(b) - toMs(a)) / 60000); }
  function dow(ds) { return new Date(toMs(String(ds).slice(0, 10))).getUTCDay(); }

  // ---------- Périodes ----------
  function inPeriods(per, t) {
    return (per || []).some(function (p) { return p && p.debut && p.debut <= t && (!p.fin || t < p.fin); });
  }
  function suspendedAt(m, t) {
    return (m && m.suspensions || []).some(function (s) { return s && s.debut && s.debut <= t && (!s.fin || t < s.fin); });
  }
  function statutAffiche(m, now) {
    if (!m) return '';
    if (m.statut === 'Actif' && suspendedAt(m, now)) return 'Suspendu';
    return m.statut || '';
  }

  // ---------- Pseudos ----------
  function normPseudo(s) {
    var x = String(s || '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase();
    var y = x.replace(/[^a-z0-9]/g, '');
    return y || x.replace(/\s+/g, '');
  }
  function lev(a, b) {
    if (a === b) return 0;
    var m = a.length, n = b.length, i, j, prev = [], cur;
    if (!m) return n; if (!n) return m;
    for (j = 0; j <= n; j++) prev[j] = j;
    for (i = 1; i <= m; i++) {
      cur = [i];
      for (j = 1; j <= n; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      prev = cur;
    }
    return prev[n];
  }
  function pseudosA(c, t) {
    var h = c.pseudos && c.pseudos.length ? c.pseudos : [{ pseudo: c.pseudo, debut: '', fin: '' }];
    return h.filter(function (p) { return (!p.debut || p.debut <= t) && (!p.fin || t < p.fin); }).map(function (p) { return p.pseudo; });
  }
  function tousPseudos(c) {
    var h = (c.pseudos || []).map(function (p) { return p.pseudo; });
    if (c.pseudo) h.push(c.pseudo);
    return h.filter(function (v, i) { return v && h.indexOf(v) === i; });
  }
  function proche(a, b) {
    if (a.length < 3 || b.length < 3) return false;
    var tol = Math.max(1, Math.floor(Math.min(a.length, b.length) / 5));
    if (lev(a, b) <= tol) return true;
    var court = a.length <= b.length ? a : b, long = court === a ? b : a;
    return court.length >= 4 && long.indexOf(court) >= 0;
  }
  // Rattache une ligne de capture à un compte, selon la date du match. Ne décide jamais seul en cas de doute.
  function resoudre(ligne, comptes, t) {
    if (ligne.res === 'manuel' && ligne.mat) return { mat: ligne.mat, cpt: ligne.cpt || '', res: 'manuel' };
    if (ligne.res === 'non inscrit confirmé') return { mat: '', cpt: '', res: 'non inscrit confirmé' };
    var np = normPseudo(ligne.pseudo);
    if (!np) return { mat: '', cpt: '', res: 'à identifier', note: 'pseudo vide' };
    var exact = comptes.filter(function (c) { return pseudosA(c, t).some(function (p) { return normPseudo(p) === np; }); });
    if (exact.length === 1) return { mat: exact[0].matricule, cpt: exact[0].id, res: 'auto' };
    if (exact.length > 1) return { mat: '', cpt: '', res: 'à identifier', sugg: exact.map(function (c) { return c.id; }), note: 'plusieurs comptes portent ce pseudo' };
    var autre = comptes.filter(function (c) { return tousPseudos(c).some(function (p) { return normPseudo(p) === np; }); });
    if (autre.length) return { mat: '', cpt: '', res: 'à identifier', sugg: autre.map(function (c) { return c.id; }), note: 'pseudo connu à une autre date' };
    var pr = comptes.filter(function (c) { return tousPseudos(c).some(function (p) { return proche(normPseudo(p), np); }); });
    if (pr.length) return { mat: '', cpt: '', res: 'à identifier', sugg: pr.map(function (c) { return c.id; }), note: 'pseudo proche d’un membre' };
    return { mat: '', cpt: '', res: 'non inscrit' };
  }

  // ---------- Comptabilisation d'une ligne ----------
  function ligneCompte(l, match, ctx) {
    if (!l.mat) return { ok: false, raison: l.res === 'à identifier' ? 'à identifier' : 'joueur non inscrit' };
    var m = ctx.membres[l.mat];
    if (!m) return { ok: false, raison: 'matricule inconnu' };
    var t = match.fin;
    if (!validDT(t)) return { ok: false, raison: 'heure de fin manquante' };
    if (!inPeriods(m.periodes, t)) return { ok: false, raison: 'membre hors période active à cette date' };
    if (suspendedAt(m, t)) return { ok: false, raison: 'membre suspendu à cette date' };
    var c = l.cpt ? ctx.comptes[l.cpt] : null;
    if (!c) return { ok: false, raison: 'compte non choisi' };
    if (c.matricule !== l.mat) return { ok: false, raison: 'compte d’un autre membre' };
    if (!inPeriods(c.periodes, t)) return { ok: false, raison: 'compte non actif à cette date' };
    return { ok: true };
  }

  function finCompetition(saison) {
    if (!saison || !validD(saison.fin)) return null;
    return addDays(saison.fin, -regles(saison).audit_jours);
  }

  function bornesCreneau(cr, R) {
    var deb = cr.date + 'T' + (cr.debut || '00:00');
    var fin = cr.fin ? cr.date + 'T' + cr.fin : addMinutes(deb, R.duree_creneau_h * 60);
    if (fin <= deb) fin = addMinutes(fin, 1440);
    return { deb: deb, fin: fin };
  }

  function valeurManquante(v) { return v === '' || v === null || v === undefined || isNaN(Number(v)); }

  // ---------- Contrôles d'un match ----------
  function controlesMatch(match, ctx, saison) {
    var R = regles(saison), B = [], W = [];
    var lignes = match.lignes || [];
    var total = lignes.length;
    var h = lignes.filter(function (l) { return l.faction === 'HAAVK'; }).length;
    var g = lignes.filter(function (l) { return l.faction === 'GTI'; }).length;
    var sansF = total - h - g;
    if (!validDT(match.fin)) B.push('Date et heure de fin du match manquantes.');
    if (total < R.min_participants) B.push(total + ' participant(s) : il en faut au moins ' + R.min_participants + '.');
    if (sansF) B.push(sansF + ' ligne(s) sans faction.');
    var ecart = Math.abs(h - g);
    if (ecart > R.ecart_max) B.push('Écart d’effectif de ' + ecart + ' (HAAVK ' + h + ', GTI ' + g + ') : invalidation automatique, maximum ' + R.ecart_max + '.');
    var manq = [], neg = [];
    lignes.forEach(function (l, i) {
      STATS.forEach(function (s) {
        var v = l[s.k];
        if (valeurManquante(v)) manq.push(i + 1); else if (Number(v) < 0) neg.push(i + 1);
      });
    });
    var uniq = function (a) { return a.filter(function (v, i) { return a.indexOf(v) === i; }); };
    if (manq.length) B.push('Valeur manquante, ligne(s) ' + uniq(manq).join(', ') + ' (mettre 0 si la valeur est nulle).');
    if (neg.length) B.push('Valeur négative, ligne(s) ' + uniq(neg).join(', ') + '.');
    var vus = {}, dupP = [];
    lignes.forEach(function (l) { var k = normPseudo(l.pseudo); if (k) { if (vus[k]) dupP.push(l.pseudo); vus[k] = 1; } });
    if (dupP.length) B.push('Pseudo en double : ' + uniq(dupP).join(', ') + '.');
    var vusM = {}, dupM = [];
    lignes.forEach(function (l) { if (l.mat) { if (vusM[l.mat]) dupM.push(l.mat); vusM[l.mat] = 1; } });
    if (dupM.length) B.push('Même joueur présent plusieurs fois (un seul passage par match, même avec deux comptes) : ' + uniq(dupM).join(', ') + '.');
    var aid = lignes.filter(function (l) { return l.res === 'à identifier'; }).length;
    if (aid) B.push(aid + ' ligne(s) à identifier : choisir le bon compte ou confirmer « non inscrit ».');
    var membres = lignes.filter(function (l) { return l.mat; }).length;
    var requis = Math.ceil(total * R.pct_membres / 100 - 1e-9);
    if (total && membres < requis) B.push(membres + ' membre(s) inscrit(s) sur ' + total + ' participants : il en faut au moins ' + requis + ' (' + R.pct_membres + ' %).');
    if (saison && validDT(match.fin)) {
      if (validD(saison.debut) && match.fin.slice(0, 10) < saison.debut) B.push('Match terminé avant le début de la saison (' + saison.debut + ').');
      var lim = finCompetition(saison);
      if (lim && match.fin.slice(0, 10) > lim) B.push('Match terminé après la date limite des matchs (' + lim + ') : les ' + R.audit_jours + ' derniers jours de la saison sont réservés à l’audit.');
    }
    if (!saison) B.push('Aucune saison choisie.');
    var autres = (ctx.matchsList || []).filter(function (m) { return m.id !== match.id; });
    if (match.type === 'Libre') {
      var cr = match.creneau_id ? ctx.creneaux[match.creneau_id] : null;
      if (!cr) B.push('Match libre sans créneau déclaré et accepté.');
      else {
        if (cr.statut !== 'Accepté') B.push('Créneau ' + cr.id + ' non accepté (' + cr.statut + ').');
        if (validDT(match.fin)) {
          var bo = bornesCreneau(cr, R);
          if (match.fin < bo.deb || match.fin > bo.fin) B.push('Heure de fin hors du créneau accepté (' + bo.deb.replace('T', ' ') + ' → ' + bo.fin.replace('T', ' ') + ').');
        }
        var deja = autres.filter(function (m) { return m.creneau_id === cr.id && m.statut === 'Validé'; });
        if (deja.length) B.push('Un match est déjà validé pour ce créneau (' + deja[0].id + ') : un seul match par créneau.');
      }
      if (!validDT(match.recu)) B.push('Heure de réception de la capture manquante.');
      else if (validDT(match.fin)) {
        var d = diffMinutes(match.fin, match.recu);
        if (d > R.delai_capture) B.push('Capture reçue ' + d + ' min après la fin du match (maximum ' + R.delai_capture + ' min).');
        if (d < 0) W.push('Heure de réception antérieure à la fin du match : à vérifier.');
      }
    } else if (validDT(match.fin)) {
      var memeJour = autres.filter(function (m) { return m.type !== 'Libre' && m.statut === 'Validé' && validDT(m.fin) && m.fin.slice(0, 10) === match.fin.slice(0, 10); });
      if (memeJour.length) W.push('Un autre match officiel est déjà validé ce jour-là (' + memeJour.map(function (m) { return m.id; }).join(', ') + ') : un match par session.');
    }
    lignes.forEach(function (l, i) {
      if (l.mat) { var st = ligneCompte(l, match, ctx); if (!st.ok) W.push('Ligne ' + (i + 1) + ' (' + l.pseudo + ') : non comptabilisée, ' + st.raison + '.'); }
    });
    alertesPerformance(match, ctx).forEach(function (a) { W.push(a); });
    if (!(match.captures && match.captures.length)) W.push('Aucune capture archivée pour ce match (preuve à conserver).');
    return { bloquants: B, alertes: W, total: total, h: h, g: g, membres: membres, requis: requis };
  }

  // Alerte d'anomalie de performance : jamais une preuve ni une sanction automatique.
  function alertesPerformance(match, ctx) {
    var out = [];
    if (!validDT(match.fin)) return out;
    (match.lignes || []).forEach(function (l) {
      if (!l.mat) return;
      var hist = [];
      (ctx.matchsList || []).forEach(function (m) {
        if (m.id === match.id || m.statut !== 'Validé' || !validDT(m.fin) || m.fin >= match.fin) return;
        (m.lignes || []).forEach(function (x) { if (x.mat === l.mat) hist.push(x); });
      });
      if (hist.length < 3) return;
      ['elim', 'score'].forEach(function (k) {
        var moy = hist.reduce(function (s, x) { return s + (Number(x[k]) || 0); }, 0) / hist.length;
        var v = Number(l[k]) || 0;
        if (moy > 0 && v > 2.5 * moy && v - moy >= (k === 'elim' ? 10 : 1000)) {
          out.push('Alerte performance à examiner : ' + l.pseudo + ', ' + (k === 'elim' ? 'éliminations' : 'score') + ' ' + v + ' contre ' + moy.toFixed(1) + ' en moyenne (une anomalie n’est pas une preuve de fraude).');
        }
      });
    });
    return out;
  }

  // ---------- Agrégation et classements ----------
  function agreger(ctx, saison, coupure) {
    var lim = finCompetition(saison), J = {}, nb = 0;
    (ctx.matchsList || []).forEach(function (m) {
      if (m.statut !== 'Validé' || !saison || m.saison_id !== saison.id || !validDT(m.fin)) return;
      if (validD(saison.debut) && m.fin.slice(0, 10) < saison.debut) return;
      if (lim && m.fin.slice(0, 10) > lim) return;
      if (coupure && !(m.fin < coupure)) return;
      nb++;
      (m.lignes || []).forEach(function (l) {
        if (!ligneCompte(l, m, ctx).ok) return;
        var j = J[l.mat];
        if (!j) { j = J[l.mat] = { mat: l.mat, n: 0 }; STATS.forEach(function (s) { j[s.k] = 0; }); }
        j.n++;
        STATS.forEach(function (s) { j[s.k] += Number(l[s.k]) || 0; });
      });
    });
    return { joueurs: Object.keys(J).map(function (k) { return J[k]; }), nbMatchs: nb };
  }

  function quantile(sorted, p) {
    if (!sorted.length) return 0;
    var h = (sorted.length - 1) * p, lo = Math.floor(h), hi = Math.ceil(h);
    return sorted[lo] + (h - lo) * (sorted[hi] - sorted[lo]);
  }
  function sgn(x) { return Math.abs(x) < 1e-9 ? 0 : x; }
  function comparateur(kind, fam) {
    if (kind === 'MOST') return function (a, b) { return sgn(b[fam] - a[fam]) || (b.n - a.n) || sgn(b.score - a.score); };
    if (kind === 'BEST') return function (a, b) { return sgn(b[fam] * a.n - a[fam] * b.n) || (b.n - a.n) || sgn(b.score - a.score); };
    return function (a, b) { return sgn(a.morts * b.n - b.morts * a.n) || (b.n - a.n) || sgn(b.score - a.score); };
  }
  function valeur(c, j) { return c.kind === 'MOST' ? j[c.fam] : j[c.fam] / j.n; }

  function classer(agg, membres) {
    var pop = agg.joueurs.filter(function (j) {
      var m = membres[j.mat];
      return m && m.statut !== 'Retiré' && m.statut !== 'Exclu' && j.n >= 1;
    });
    var ns = pop.map(function (j) { return j.n; }).sort(function (a, b) { return a - b; });
    var seuil = ns.length ? Math.ceil(quantile(ns, 0.5) - 1e-9) : 0;
    var moyS = pop.map(function (j) { return j.score / j.n; }).sort(function (a, b) { return a - b; });
    var q1 = moyS.length ? quantile(moyS, 0.25) : 0;
    var cats = CATS.map(function (c) {
      var cand;
      if (c.kind === 'MOST') cand = pop.filter(function (j) { return j[c.fam] > 0; });
      else if (c.kind === 'BEST') cand = pop.filter(function (j) { return j.n >= seuil && j[c.fam] > 0; });
      else cand = pop.filter(function (j) { return j.n >= seuil && j.score / j.n >= q1 - 1e-9; });
      var cmp = comparateur(c.kind, c.fam);
      var tri = cand.slice().sort(function (a, b) { return cmp(a, b) || (a.mat < b.mat ? -1 : a.mat > b.mat ? 1 : 0); });
      var rang = 0;
      var lignes = tri.map(function (j, i) {
        if (i === 0 || cmp(tri[i - 1], j) !== 0) rang = i + 1;
        return { j: j, rang: rang, val: valeur(c, j), egal: false };
      });
      lignes.forEach(function (r, i) {
        if ((i > 0 && lignes[i - 1].rang === r.rang) || (i < lignes.length - 1 && lignes[i + 1].rang === r.rang)) r.egal = true;
      });
      var titre = null, statut;
      if (!lignes.length) statut = 'Aucun candidat';
      else if (lignes.length > 1 && lignes[1].rang === 1) statut = 'Non attribué';
      else { titre = lignes[0].j; statut = 'Attribué'; }
      return { key: c.key, kind: c.kind, fam: c.fam, label: c.label, prio: c.prio, lignes: lignes, titre: titre, statut: statut };
    });
    return { pop: pop, seuil: seuil, q1: q1, cats: cats };
  }

  // ---------- Lots : un seul par joueur, priorité des 11 catégories, redistribution ----------
  function attribuerLots(cl, lotsDispo) {
    var loti = {}, res = [];
    cl.cats.slice().sort(function (a, b) { return a.prio - b.prio; }).forEach(function (c) {
      var r = { key: c.key, label: c.label, prio: c.prio, lot: !!(lotsDispo && lotsDispo[c.key]), laureat: c.titre ? c.titre.mat : null, statutTitre: c.statut, dejaLoti: null, beneficiaire: null, statut: '', explication: '' };
      if (!r.lot) { r.statut = 'Pas de lot confirmé'; res.push(r); return; }
      if (!c.titre) {
        r.statut = 'Non attribué';
        r.explication = c.statut === 'Aucun candidat' ? 'Aucun joueur éligible.' : 'Égalité parfaite : pas de lauréat unique, le lot reste non attribué.';
        res.push(r); return;
      }
      r.dejaLoti = !!loti[c.titre.mat];
      if (!r.dejaLoti) { r.beneficiaire = c.titre.mat; loti[c.titre.mat] = 1; r.statut = 'Attribué'; r.explication = 'Lot remis au lauréat sportif.'; res.push(r); return; }
      var groupes = [];
      c.lignes.forEach(function (l) {
        var gr = groupes[groupes.length - 1];
        if (gr && gr.rang === l.rang) gr.items.push(l.j); else groupes.push({ rang: l.rang, items: [l.j] });
      });
      for (var i = 0; i < groupes.length; i++) {
        var libres = groupes[i].items.filter(function (j) { return !loti[j.mat]; });
        if (!libres.length) continue;
        if (libres.length === 1) {
          r.beneficiaire = libres[0].mat; loti[libres[0].mat] = 1; r.statut = 'Attribué (redistribution)';
          r.explication = 'Le lauréat a déjà un lot : le lot passe au joueur suivant éligible sans lot (rang ' + groupes[i].rang + '). Le titre reste au lauréat.';
        } else { r.statut = 'Non attribué'; r.explication = 'Égalité parfaite entre plusieurs bénéficiaires possibles : aucun bénéficiaire unique.'; }
        break;
      }
      if (!r.statut) { r.statut = 'Non attribué'; r.explication = 'Tous les joueurs éligibles de cette catégorie ont déjà reçu un lot.'; }
      res.push(r);
    });
    return res;
  }

  // ---------- Calendrier ----------
  function derniereCoupure(now, saison) {
    var R = regles(saison), d = now.slice(0, 10);
    for (var k = 0; k < 8; k++) {
      var c = addDays(d, -k);
      if (dow(c) === R.coupure_jour) { var dt = c + 'T' + R.coupure_heure; if (dt <= now) return dt; }
    }
    return null;
  }
  function publicationsPrevues(saison, today, nb) {
    if (!saison || !validD(saison.premier_provisoire)) return [];
    var R = regles(saison), out = [], d = saison.premier_provisoire, guard = 0;
    while (d < today && guard++ < 500) d = addDays(d, R.periodicite);
    while (out.length < nb && guard++ < 600) { if (validD(saison.fin) && d > saison.fin) break; out.push(d); d = addDays(d, R.periodicite); }
    return out;
  }

  // ---------- Messages Participer → Administration ----------
  function b64urlEncode(str) {
    var bytes = new TextEncoder().encode(str), bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
  function b64urlDecode(s) {
    s = s.replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    var bin = atob(s), bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder().decode(bytes);
  }
  function encodeMsg(o) { return 'DFMM1.' + b64urlEncode(JSON.stringify(o)) + '.FIN'; }
  function decodeMsg(text) {
    text = String(text || '');
    var i = text.indexOf('DFMM1.');
    if (i < 0) throw new Error('Aucun code « DFMM1. » trouvé dans le texte collé.');
    var j = text.indexOf('.FIN', i + 6);
    var raw = text.slice(i + 6, j < 0 ? undefined : j).replace(/[^A-Za-z0-9_-]/g, '');
    var o = JSON.parse(b64urlDecode(raw));
    if (!o || typeof o !== 'object' || !o.t) throw new Error('Code illisible.');
    return o;
  }

  // ---------- Lecture des lignes collées (OCR, tableur ou saisie) ----------
  function nombre(s) {
    s = String(s).trim();
    if (/^-?\d{1,3}([,\s.]\d{3})+$/.test(s) && !/^-?\d+[.,]\d{1,2}$/.test(s)) s = s.replace(/[,\s.]/g, '');
    s = s.replace(',', '.');
    return /^-?\d+(\.\d+)?$/.test(s) ? Number(s) : NaN;
  }
  function parseLignes(text, factionDefaut) {
    var out = [], err = [], fac = factionDefaut || '';
    String(text || '').split(/\r?\n/).forEach(function (raw, idx) {
      var line = raw.trim();
      if (!line) return;
      var up = line.toUpperCase().replace(/[^A-Z]/g, '');
      if ((up === 'HAAVK' || up === 'GTI') && line.replace(/[^0-9]/g, '') === '') { fac = up; return; }
      var faction = fac, pseudo, nums, parts = null;
      if (line.indexOf('\t') >= 0) parts = line.split('\t');
      else if (line.indexOf(';') >= 0) parts = line.split(';');
      if (parts) {
        parts = parts.map(function (p) { return p.trim(); });
        while (parts.length && parts[parts.length - 1] === '') parts.pop();
        if (/^(HAAVK|GTI)$/i.test(parts[0])) faction = parts.shift().toUpperCase();
        pseudo = parts.shift(); nums = parts;
      } else {
        var toks = line.split(/\s+/);
        if (/^(HAAVK|GTI)$/i.test(toks[0])) faction = toks.shift().toUpperCase();
        nums = [];
        while (toks.length && nums.length < 8 && !isNaN(nombre(toks[toks.length - 1]))) nums.unshift(toks.pop());
        pseudo = toks.join(' ');
      }
      if (!pseudo || !nums || nums.length !== 8 || nums.some(function (n) { return isNaN(nombre(n)); })) {
        err.push('Ligne ' + (idx + 1) + ' ignorée : « ' + line.slice(0, 60) + ' » (attendu : pseudo puis 8 nombres).');
        return;
      }
      var l = { faction: faction, pseudo: pseudo };
      STATS.forEach(function (s, i) { l[s.k] = nombre(nums[i]); });
      out.push(l);
    });
    return { lignes: out, erreurs: err };
  }

  return {
    STATS: STATS, CATS: CATS, DEFAULTS: DEFAULTS, PROVINCES: PROVINCES, CARTES: CARTES,
    regles: regles, nowStr: nowStr, validDT: validDT, validD: validD, normDT: normDT,
    addDays: addDays, addMinutes: addMinutes, diffMinutes: diffMinutes, dow: dow,
    inPeriods: inPeriods, suspendedAt: suspendedAt, statutAffiche: statutAffiche,
    normPseudo: normPseudo, lev: lev, resoudre: resoudre, ligneCompte: ligneCompte,
    finCompetition: finCompetition, bornesCreneau: bornesCreneau, controlesMatch: controlesMatch,
    agreger: agreger, quantile: quantile, classer: classer, valeur: valeur, attribuerLots: attribuerLots,
    derniereCoupure: derniereCoupure, publicationsPrevues: publicationsPrevues,
    encodeMsg: encodeMsg, decodeMsg: decodeMsg, parseLignes: parseLignes, nombre: nombre
  };
})();
if (typeof module !== 'undefined') module.exports = L;
