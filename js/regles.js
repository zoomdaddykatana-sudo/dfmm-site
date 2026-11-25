/* LEAGUE UV — DFMM : règles de calcul, sans affichage (testables à part).
   Référence : cahier « LEAGUE UV — Règles et sanctions » (21/11/2026).
   Aucune valeur réglable n'est écrite ici : elles viennent toutes de la table
   « parametres » de Supabase (section 10 du cahier), passées par regles(). */
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

  // Ordre obligatoire de priorité des lots (cahier, section 8)
  var CATS = [
    { key: 'most_elim', kind: 'MOST', fam: 'elim', label: 'MOST Eliminator', prio: 1 },
    { key: 'most_med', kind: 'MOST', fam: 'med', label: 'MOST Medic', prio: 2 },
    { key: 'most_ing', kind: 'MOST', fam: 'ing', label: 'MOST Engineer', prio: 3 },
    { key: 'most_obj', kind: 'MOST', fam: 'obj', label: 'MOST Objective', prio: 4 },
    { key: 'most_tac', kind: 'MOST', fam: 'tac', label: 'MOST Tactician', prio: 5 },
    { key: 'best_surv', kind: 'SURV', fam: 'morts', label: 'BEST Survivor', prio: 6 },
    { key: 'best_elim', kind: 'BEST', fam: 'elim', label: 'BEST Eliminator', prio: 7 },
    { key: 'best_med', kind: 'BEST', fam: 'med', label: 'BEST Medic', prio: 8 },
    { key: 'best_ing', kind: 'BEST', fam: 'ing', label: 'BEST Engineer', prio: 9 },
    { key: 'best_obj', kind: 'BEST', fam: 'obj', label: 'BEST Objective', prio: 10 },
    { key: 'best_tac', kind: 'BEST', fam: 'tac', label: 'BEST Tactician', prio: 11 }
  ];

  var PROVINCES = [
    { p: 'Antananarivo', v: 'Antananarivo' }, { p: 'Antsiranana', v: 'Antsiranana' },
    { p: 'Fianarantsoa', v: 'Fianarantsoa' }, { p: 'Mahajanga', v: 'Mahajanga' },
    { p: 'Toamasina', v: 'Toamasina' }, { p: 'Toliara', v: 'Toliara' }
  ];

  var CARTES = ['Craqué', 'Ascension', 'Ligne de tranchées', 'Accident de train', "Canal d'Akh", 'Faille'];

  // ---------- Paramètres (section 10) : tous obligatoires, aucune valeur par défaut ----------
  var PARAMS_REQUIS = [
    'participants_min', 'ecart_factions_max', 'seuil_membres_pct', 'delai_capture_min', 'delai_declaration_h',
    'plage_fin_h', 'coupure_jour', 'coupure_heure', 'publication_jour', 'periodicite_jours',
    'verification_finale_h', 'reclamation_h', 'comptes_max', 'comptes_actifs_max',
    'delai_changement_compte_jours', 'convocation_h', 'attente_h', 'recours_h', 'suspension_max_jours',
    'alerte_facteur', 'alerte_ecart_elim', 'alerte_ecart_score'
  ];
  function regles(params) {
    var R = {}, manquants = [];
    PARAMS_REQUIS.forEach(function (k) {
      var v = params ? params[k] : undefined;
      if (v === undefined || v === null || v === '') manquants.push(k); else R[k] = v;
    });
    if (manquants.length) throw new Error('Paramètre(s) manquant(s) : ' + manquants.join(', ') + '.');
    return R;
  }

  // ---------- Dates (heure de Madagascar, chaînes AAAA-MM-JJTHH:MM) ----------
  function pad(n) { return String(n).padStart(2, '0'); }
  function nowStr(d) {
    d = d || new Date();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  // Instant du serveur (ex. 2026-11-21T13:05:00Z) → heure de Madagascar « AAAA-MM-JJTHH:MM ».
  function versLocal(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return '';
    var p = {};
    new Intl.DateTimeFormat('en-GB', { timeZone: 'Indian/Antananarivo', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
      .formatToParts(d).forEach(function (x) { p[x.type] = x.value; });
    return p.year + '-' + p.month + '-' + p.day + 'T' + p.hour + ':' + p.minute;
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
    return (m && m.suspensions || []).some(function (s) { return s && s.debut && !s.annulee && s.debut <= t && (!s.fin || t < s.fin); });
  }
  function statutAffiche(m, now) {
    if (!m) return '';
    if (m.statut === 'Actif' && suspendedAt(m, now)) return 'Suspendu';
    return m.statut || '';
  }

  // ---------- UID ----------
  // UID collé depuis le jeu ou une messagerie : on enlève les caractères invisibles, les espaces
  // et le mot « UID », et on change les chiffres « larges » en chiffres normaux (NFKC).
  // Une vraie faute (lettre, tiret…) reste : le contrôle 5 à 25 chiffres la refuse.
  // Même nettoyage que la fonction serveur « inscription » (tests/inscription.test.js).
  var UID_RE = /^\d{5,25}$/;
  function normUid(u) {
    var s = String(u == null ? '' : u).normalize('NFKC');
    s = s.replace(/[\s\u00AD\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/g, '');
    return s.replace(/^uid:?/i, '');
  }
  function uidValide(u) { return UID_RE.test(normUid(u)); }

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

  // ---------- Une ligne rapporte-t-elle des points ? (= membre confirmé dans ce match) ----------
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
    if ((l.exclue_sanction)) return { ok: false, raison: 'statistiques retirées par décision' };
    return { ok: true };
  }

  // Seuil de membres confirmés : pourcentage du total des participants, arrondi vers le bas.
  function membresRequis(total, R) { return Math.floor(total * R.seuil_membres_pct / 100 + 1e-9); }

  // Plage de l'heure de fin d'un match libre : de l'heure annoncée à « plage_fin_h » heures après.
  function bornesCreneau(cr, R) {
    var deb = cr.date + 'T' + (cr.debut || '00:00');
    return { deb: deb, fin: addMinutes(deb, R.plage_fin_h * 60) };
  }

  // Plage de l'heure de fin d'un match de Katana : du début annoncé à « plage_fin_h » heures après (null sans début).
  function bornesKatana(match, R) {
    if (!validDT(match.debut_annonce)) return null;
    return { deb: match.debut_annonce, fin: addMinutes(match.debut_annonce, R.plage_fin_h * 60) };
  }

  function valeurManquante(v) { return v === '' || v === null || v === undefined || isNaN(Number(v)); }

  // ---------- Contrôles d'un match ----------
  // bloquants : le match ne peut pas être validé ; attente : le match passe « en attente » (Katana tranche) ;
  // alertes : information pour Katana, jamais de sanction automatique.
  // criteres : liste complète des critères, chacun { nom, etat: 'ok' | 'non' | 'attente' | 'sans_objet', detail }.
  function controlesMatch(match, ctx, saison, R) {
    var B = [], A = [], W = [], C = [];
    var crit = function (nom, etat, detail) { C.push({ nom: nom, etat: etat, detail: detail || '' }); };
    var lignes = match.lignes || [];
    var total = lignes.length;
    var h = lignes.filter(function (l) { return l.faction === 'HAAVK'; }).length;
    var g = lignes.filter(function (l) { return l.faction === 'GTI'; }).length;
    var sansF = total - h - g;
    if (!validDT(match.fin)) B.push('Date et heure de fin du match manquantes.');
    if (total < R.participants_min) B.push(total + ' participant(s) : il en faut au moins ' + R.participants_min + '.');
    if (sansF) B.push(sansF + ' ligne(s) sans faction.');
    var ecart = Math.abs(h - g);
    if (ecart > R.ecart_factions_max) B.push('Écart d’effectif de ' + ecart + ' (HAAVK ' + h + ', GTI ' + g + ') : maximum ' + R.ecart_factions_max + '.');
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
    // Membres confirmés : seules les lignes qui rapportent des points ; une ligne à identifier ne compte pas avant vérification.
    var membres = lignes.filter(function (l) { return ligneCompte(l, match, ctx).ok; }).length;
    var requis = membresRequis(total, R);
    if (total && membres < requis) B.push(membres + ' membre(s) confirmé(s) sur ' + total + ' participants : il en faut au moins ' + requis + ' (' + R.seuil_membres_pct + ' %, arrondi vers le bas).');
    var aid = lignes.filter(function (l) { return l.res === 'à identifier'; }).length;
    if (aid) W.push(aid + ' ligne(s) à identifier : le match peut être validé sans elles ; une fois identifiées, elles compteront pour les classements suivants.');
    if (saison && validDT(match.fin)) {
      if (validD(saison.debut) && match.fin.slice(0, 10) < saison.debut) B.push('Match terminé avant le début de la saison (' + saison.debut + ').');
      if (validD(saison.fin) && match.fin.slice(0, 10) > saison.fin) B.push('Match terminé après la fin de la saison (' + saison.fin + ').');
    }
    if (!saison) B.push('Aucune saison choisie.');
    // Délai d'envoi : pour tous les matchs (Katana compris), sauf la saisie de démarrage.
    if (!match.demarrage && !match.delai_exception) {
      if (!validDT(match.envoi)) B.push('Heure d’envoi de la capture manquante.');
      else if (validDT(match.fin)) {
        var d = diffMinutes(match.fin, match.envoi);
        if (d > R.delai_capture_min) B.push('Capture envoyée ' + d + ' min après la fin du match (maximum ' + R.delai_capture_min + ' min) : rejetée.');
        if (d < 0) W.push('Heure d’envoi antérieure à l’heure de fin lue sur la capture : à vérifier.');
      }
    }
    var autres = (ctx.matchsList || []).filter(function (m) { return m.id !== match.id; });
    if (match.type === 'Libre') {
      var cr = match.creneau_id ? ctx.creneaux[match.creneau_id] : null;
      if (!cr) B.push('Match libre sans créneau déclaré.');
      else {
        if (cr.statut === 'Annulé') B.push('Créneau ' + cr.id + ' annulé.');
        if (validDT(match.fin)) {
          var bo = bornesCreneau(cr, R);
          if (match.fin < bo.deb || match.fin > bo.fin) A.push('Heure de fin hors de la plage du créneau (' + bo.deb.replace('T', ' ') + ' → ' + bo.fin.replace('T', ' ') + ') : match en attente.');
        }
        var deja = autres.filter(function (m) { return m.creneau_id === cr.id && m.statut === 'Validé'; });
        if (deja.length) B.push('Un match est déjà validé pour ce créneau (' + deja[0].id + ') : un seul match par créneau.');
      }
    } else {
      // Retard (décision de Katana du 22/11/2026, pour tous les matchs) : la fin doit tomber entre le début annoncé
      // et « plage_fin_h » heures après ; sinon match en attente, comme un match libre (choix 1 B). Début annoncé obligatoire.
      var bK = bornesKatana(match, R);
      if (!bK) B.push('Début annoncé du match manquant (heure de début prévue, par exemple 16:05).');
      else if (validDT(match.fin) && (match.fin < bK.deb || match.fin > bK.fin)) A.push('Heure de fin hors de la plage du début annoncé (' + bK.deb.replace('T', ' ') + ' → ' + bK.fin.replace('T', ' ') + ') : match en attente.');
    }
    lignes.forEach(function (l, i) {
      if (l.mat) { var st = ligneCompte(l, match, ctx); if (!st.ok) W.push('Ligne ' + (i + 1) + ' (' + l.pseudo + ') : non comptée, ' + st.raison + '.'); }
    });
    alertesPerformance(match, ctx, R).forEach(function (a) { W.push(a); });
    if (!(match.captures && match.captures.length)) W.push('Aucune capture archivée pour ce match (preuve à conserver).');
    // Liste complète des critères (mêmes contrôles que ci-dessus, présentés un par un).
    var dansSaison = saison && validDT(match.fin) && !(validD(saison.debut) && match.fin.slice(0, 10) < saison.debut) && !(validD(saison.fin) && match.fin.slice(0, 10) > saison.fin);
    crit('Saison choisie et match terminé pendant la saison', !saison || !validDT(match.fin) ? (saison ? 'sans_objet' : 'non') : (dansSaison ? 'ok' : 'non'),
      !saison ? 'aucune saison' : !validDT(match.fin) ? 'heure de fin manquante' : (saison.debut || '?') + ' → ' + (saison.fin || 'en cours'));
    crit('Date et heure de fin du match', validDT(match.fin) ? 'ok' : 'non', validDT(match.fin) ? match.fin.replace('T', ' ') : 'manquantes');
    crit('Au moins ' + R.participants_min + ' participants', total >= R.participants_min ? 'ok' : 'non', total + ' participant(s)');
    crit('Chaque ligne a une faction', sansF ? 'non' : 'ok', sansF ? sansF + ' ligne(s) sans faction' : '');
    crit('Écart entre les factions de ' + R.ecart_factions_max + ' joueur au plus', ecart > R.ecart_factions_max ? 'non' : 'ok', 'HAAVK ' + h + ', GTI ' + g + ', écart ' + ecart);
    crit('Statistiques complètes (8 valeurs par ligne)', manq.length ? 'non' : 'ok', manq.length ? 'ligne(s) ' + uniq(manq).join(', ') : '');
    crit('Aucune valeur négative', neg.length ? 'non' : 'ok', neg.length ? 'ligne(s) ' + uniq(neg).join(', ') : '');
    crit('Aucun pseudo en double', dupP.length ? 'non' : 'ok', uniq(dupP).join(', '));
    crit('Un seul passage par joueur', dupM.length ? 'non' : 'ok', uniq(dupM).join(', '));
    crit('Au moins ' + R.seuil_membres_pct + ' % de membres confirmés', total && membres < requis ? 'non' : 'ok', membres + ' sur ' + total + ', minimum ' + requis);
    if (match.demarrage) crit('Capture envoyée au plus ' + R.delai_capture_min + ' min après la fin', 'sans_objet', 'saisie de démarrage');
    else if (match.delai_exception) crit('Capture envoyée au plus ' + R.delai_capture_min + ' min après la fin', 'ok', 'retard accepté');
    else if (!validDT(match.envoi)) crit('Capture envoyée au plus ' + R.delai_capture_min + ' min après la fin', 'non', 'heure d’envoi manquante');
    else if (!validDT(match.fin)) crit('Capture envoyée au plus ' + R.delai_capture_min + ' min après la fin', 'sans_objet', 'heure de fin manquante');
    else { var dd = diffMinutes(match.fin, match.envoi); crit('Capture envoyée au plus ' + R.delai_capture_min + ' min après la fin', dd > R.delai_capture_min ? 'non' : 'ok', dd + ' min'); }
    if (match.type === 'Libre') {
      var crL = match.creneau_id ? ctx.creneaux[match.creneau_id] : null;
      crit('Créneau déclaré et non annulé', crL && crL.statut !== 'Annulé' ? 'ok' : 'non', crL ? 'créneau ' + crL.id : 'aucun créneau');
      if (crL && validDT(match.fin)) { var bL = bornesCreneau(crL, R); crit('Fin dans la plage du créneau', match.fin < bL.deb || match.fin > bL.fin ? 'attente' : 'ok', bL.deb.replace('T', ' ') + ' → ' + bL.fin.replace('T', ' ')); }
      else crit('Fin dans la plage du créneau', 'sans_objet', crL ? 'heure de fin manquante' : 'aucun créneau');
      var dejaL = crL ? autres.filter(function (m) { return m.creneau_id === crL.id && m.statut === 'Validé'; }) : [];
      crit('Un seul match validé par créneau', dejaL.length ? 'non' : 'ok', dejaL.length ? 'déjà validé : ' + dejaL[0].id : '');
    } else {
      var bK2 = bornesKatana(match, R), nomK = 'Fin au plus ' + R.plage_fin_h + ' h après le début annoncé';
      crit('Début annoncé du match', bK2 ? 'ok' : 'non', bK2 ? bK2.deb.replace('T', ' ') : 'manquant');
      if (bK2 && validDT(match.fin)) crit(nomK, match.fin < bK2.deb || match.fin > bK2.fin ? 'attente' : 'ok', bK2.deb.replace('T', ' ') + ' → ' + bK2.fin.replace('T', ' '));
      else crit(nomK, 'sans_objet', bK2 ? 'heure de fin manquante' : 'début annoncé manquant');
    }
    return { bloquants: B, attente: A, alertes: W, criteres: C, total: total, h: h, g: g, membres: membres, requis: requis };
  }

  // Lecture d'une capture par claude.ai : compare l'effectif annoncé ({HAAVK, GTI}, numéros des tableaux) aux lignes
  // de l'éditeur, et signale les lignes sans pseudo. Ne change aucune règle : aide à repérer une ligne oubliée.
  function verifierLecture(r, lignes) {
    var P = [], eff = r && r.effectif, nb = { HAAVK: 0, GTI: 0 }, sansP = [], partis = 0;
    (lignes || []).forEach(function (l, i) { if (nb[l.faction] !== undefined) nb[l.faction]++; if (!String(l.pseudo || '').trim()) sansP.push(i + 1); });
    ((r && r.lignes) || []).forEach(function (x) { if (x && x.parti === true) partis++; });
    if (eff && typeof eff === 'object') {
      ['HAAVK', 'GTI'].forEach(function (f) {
        var e = Number(eff[f]);
        if (eff[f] !== null && eff[f] !== undefined && isFinite(e) && e !== nb[f]) P.push('La capture compte ' + e + ' joueur(s) ' + f + ', mais ' + nb[f] + ' ligne(s) ' + f + ' ont été lues : ' + (e > nb[f] ? 'ajoutez la ou les lignes oubliées' : 'retirez la ou les lignes en trop') + ' (« Ajouter une ligne »), en recopiant la capture.');
      });
    }
    if (sansP.length) P.push('Pseudo à recopier depuis la capture, ligne(s) ' + sansP.join(', ') + '.');
    return { problemes: P, effectif: eff || null, lu: nb, partis: partis };
  }

  // Motif proposé à partir des contrôles : les critères non remplis (bloquants puis attente), une phrase par ligne.
  function motifDepuisControles(c) {
    var l = (c.bloquants || []).concat(c.attente || []);
    return l.length ? 'Critère(s) non rempli(s) : ' + l.join(' ') : '';
  }

  // ---------- Concordance des captures d'un match libre (section 4) ----------
  // lectures : [{nom, lecture: {carte, vainqueur, lisible, lignes:[{faction, pseudo, score…tac}]}}], une par envoyeur.
  // Mêmes pseudos, mêmes statistiques par joueur, même carte, même vainqueur ; sinon le match passe en attente.
  function comparerLectures(lectures) {
    var ecarts = [], alertes = [];
    var ls = (lectures || []).filter(function (x) { return x && x.lecture; });
    ls.forEach(function (x) { if (x.lecture.lisible === false) alertes.push('Capture de ' + x.nom + ' jugée floue ou partiellement illisible par claude.ai : elle ne peut pas être acceptée.'); });
    if (ls.length < 2) return { concordant: ecarts.length === 0, ecarts: ecarts, alertes: alertes, n: ls.length };
    var ref = ls[0], cle = function (l) { return (l.faction || '') + '|' + normPseudo(l.pseudo); };
    var idx = function (lec) { var o = {}; (lec.lignes || []).forEach(function (l) { o[cle(l)] = l; }); return o; };
    var a = idx(ref.lecture);
    ls.slice(1).forEach(function (x) {
      var b = idx(x.lecture), qui = ref.nom + ' et ' + x.nom;
      if (normPseudo(ref.lecture.carte || '') !== normPseudo(x.lecture.carte || '')) ecarts.push('Carte différente (' + qui + ') : ' + (ref.lecture.carte || '—') + ' / ' + (x.lecture.carte || '—') + '.');
      var va = ref.lecture.vainqueur || '', vb = x.lecture.vainqueur || '';
      if (va && vb && va !== vb) ecarts.push('Vainqueur différent (' + qui + ') : ' + va + ' / ' + vb + '.');
      else if (!va || !vb) alertes.push('Vainqueur non lu sur une capture (' + qui + ') : à vérifier à l’œil.');
      Object.keys(a).forEach(function (k) {
        var la = a[k], lb = b[k];
        if (!lb) { ecarts.push('Joueur ' + la.pseudo + ' (' + la.faction + ') absent de la capture de ' + x.nom + '.'); return; }
        var d = STATS.filter(function (s) { return String(la[s.k]) !== String(lb[s.k]); }).map(function (s) { return s.court + ' ' + la[s.k] + ' / ' + lb[s.k]; });
        if (d.length) ecarts.push('Joueur ' + la.pseudo + ' : ' + d.join(', ') + ' (' + qui + ').');
      });
      Object.keys(b).forEach(function (k) { if (!a[k]) ecarts.push('Joueur ' + b[k].pseudo + ' (' + b[k].faction + ') absent de la capture de ' + ref.nom + '.'); });
    });
    return { concordant: ecarts.length === 0, ecarts: ecarts, alertes: alertes, n: ls.length };
  }

  // Alerte d'anomalie de performance : jamais une preuve ni une sanction automatique. Seuils réglables.
  function alertesPerformance(match, ctx, R) {
    var out = [];
    if (!validDT(match.fin)) return out;
    var ecartMin = { elim: R.alerte_ecart_elim, score: R.alerte_ecart_score };
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
        if (moy > 0 && v > R.alerte_facteur * moy && v - moy >= ecartMin[k]) {
          out.push('Alerte performance à examiner : ' + l.pseudo + ', ' + (k === 'elim' ? 'éliminations' : 'score') + ' ' + v + ' contre ' + moy.toFixed(1) + ' en moyenne (une anomalie n’est pas une preuve de fraude).');
        }
      });
    });
    return out;
  }

  // ---------- Ce qui entre dans un classement ----------
  // opts.coupure : samedi 16 h (provisoire) ou lendemain de la fin de saison (final).
  // opts.limiteDecisions : instant après lequel une décision ou une identification compte pour le classement suivant
  //   (la coupure pour un provisoire ; la publication pour le classement final).
  function matchDansClassement(m, saison, opts) {
    if (m.statut !== 'Validé' || !saison || m.saison_id !== saison.id || !validDT(m.fin)) return false;
    if (validD(saison.debut) && m.fin.slice(0, 10) < saison.debut) return false;
    if (validD(saison.fin) && m.fin.slice(0, 10) > saison.fin) return false;
    var lim = opts.limiteDecisions || opts.coupure;
    if (m.attente_decide_le && lim && !(m.attente_decide_le < lim)) return false; // tranché après la coupure → suivant
    if (m.type === 'Katana' || m.demarrage) return true;                             // exempté de la coupure de 16 h
    var envoi = validDT(m.envoi) ? m.envoi : null;
    return !opts.coupure || (envoi !== null && envoi < opts.coupure);
  }
  function ligneDansClassement(l, m, ctx, opts) {
    if (!ligneCompte(l, m, ctx).ok) return false;
    var lim = opts.limiteDecisions || opts.coupure;
    if (l.res === 'manuel' && l.identifie_le && lim && !(l.identifie_le < lim)) return false; // identifiée après → suivant
    return true;
  }

  function agreger(ctx, saison, opts) {
    opts = opts || {};
    var J = {}, nb = 0;
    (ctx.matchsList || []).forEach(function (m) {
      if (!matchDansClassement(m, saison, opts)) return;
      nb++;
      (m.lignes || []).forEach(function (l) {
        if (!ligneDansClassement(l, m, ctx, opts)) return;
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

  // Classement des 11 titres. Retirés, exclus et suspendus (à la date « aInstant ») : hors médiane, hors Q1, non candidats.
  // Membre hors concours (membres[mat].hc, décision de Katana du 25/11/2026) : hors médiane et hors Q1 ; il figure
  // dans une liste s'il remplit les conditions (seuil, Q1, total > 0 calculés sans lui), sans rang (« HC ») ;
  // les autres sont numérotés et départagés comme s'il n'existait pas ; il n'est jamais lauréat.
  function classer(agg, membres, aInstant) {
    var tous = agg.joueurs.filter(function (j) {
      var m = membres[j.mat];
      if (!m || m.statut === 'Retiré' || m.statut === 'Exclu' || j.n < 1) return false;
      return !(aInstant && suspendedAt(m, aInstant));
    });
    var estHC = function (j) { return !!(membres[j.mat] && membres[j.mat].hc); };
    var pop = tous.filter(function (j) { return !estHC(j); });
    var hc = tous.filter(estHC);
    var ns = pop.map(function (j) { return j.n; }).sort(function (a, b) { return a - b; });
    var seuil = ns.length ? Math.ceil(quantile(ns, 0.5) - 1e-9) : 0;
    var moyS = pop.map(function (j) { return j.score / j.n; }).sort(function (a, b) { return a - b; });
    var q1 = moyS.length ? quantile(moyS, 0.25) : 0;
    var cats = CATS.map(function (c) {
      var cand;
      if (c.kind === 'MOST') cand = tous.filter(function (j) { return j[c.fam] > 0; });
      else if (c.kind === 'BEST') cand = tous.filter(function (j) { return j.n >= seuil && j[c.fam] > 0; });
      else cand = tous.filter(function (j) { return j.n >= seuil && j.score / j.n >= q1 - 1e-9; });
      var cmp = comparateur(c.kind, c.fam);
      var tri = cand.slice().sort(function (a, b) { return cmp(a, b) || (a.mat < b.mat ? -1 : a.mat > b.mat ? 1 : 0); });
      var rang = 0, k = 0, prec = null;
      var lignes = tri.map(function (j) {
        if (estHC(j)) return { j: j, rang: null, val: valeur(c, j), egal: false, hc: true };
        k++;
        if (!prec || cmp(prec, j) !== 0) rang = k;
        prec = j;
        return { j: j, rang: rang, val: valeur(c, j), egal: false, hc: false };
      });
      var classes = lignes.filter(function (l) { return !l.hc; });
      classes.forEach(function (r, i) {
        if ((i > 0 && classes[i - 1].rang === r.rang) || (i < classes.length - 1 && classes[i + 1].rang === r.rang)) r.egal = true;
      });
      // Égalité parfaite en tête après les 3 critères : co-lauréats (jamais un membre hors concours).
      var laureats = classes.filter(function (l) { return l.rang === 1; }).map(function (l) { return l.j; });
      var statut = !laureats.length ? 'Aucun candidat' : laureats.length > 1 ? 'Co-lauréats' : 'Attribué';
      return { key: c.key, kind: c.kind, fam: c.fam, label: c.label, prio: c.prio, lignes: lignes, laureats: laureats, statut: statut };
    });
    return { pop: pop, hc: hc, seuil: seuil, q1: q1, cats: cats };
  }

  // Classement figé d'une publication (contenu enregistré) → même forme que classer(), pour attribuerLots.
  // Publication sans « hc » (avant le 25/11/2026) : personne n'est hors concours.
  function classementDepuisPublication(contenu) {
    var cats = ((contenu && contenu.categories) || []).map(function (c) {
      var def = CATS.filter(function (x) { return x.key === c.key; })[0] || {};
      var horsC = (c.lignes || []).filter(function (l) { return l.hc; }).map(function (l) { return l.mat; });
      return { key: c.key, kind: c.kind || def.kind, fam: def.fam, label: c.label || def.label, prio: def.prio, statut: c.statut,
        laureats: (c.laureats || []).filter(function (x) { return horsC.indexOf(x.mat) < 0; }).map(function (x) { return { mat: x.mat }; }),
        lignes: (c.lignes || []).map(function (l) { return { j: { mat: l.mat }, rang: l.hc ? null : l.rang, val: l.val, egal: !l.hc && !!l.egal, hc: !!l.hc }; }) };
    });
    return { cats: cats, seuil: contenu && contenu.seuil, q1: contenu && contenu.q1 };
  }

  // ---------- Lots : un seul par joueur, priorité des 11 catégories, redistribution ----------
  function attribuerLots(cl, lotsDispo) {
    var loti = {}, res = [];
    cl.cats.slice().sort(function (a, b) { return a.prio - b.prio; }).forEach(function (c) {
      var r = { key: c.key, label: c.label, prio: c.prio, lot: !!(lotsDispo && lotsDispo[c.key]), laureats: c.laureats.map(function (j) { return j.mat; }), statutTitre: c.statut, dejaLoti: null, beneficiaire: null, statut: '', explication: '' };
      if (!r.lot) { r.statut = 'Pas de lot confirmé'; res.push(r); return; }
      if (!c.laureats.length) { r.statut = 'Non attribué'; r.explication = 'Aucun joueur éligible.'; res.push(r); return; }
      if (c.laureats.length > 1) { r.statut = 'Non attribué'; r.explication = 'Co-lauréats : le titre est partagé, sans lot.'; res.push(r); return; }
      var laureat = c.laureats[0].mat;
      r.dejaLoti = !!loti[laureat];
      if (!r.dejaLoti) { r.beneficiaire = laureat; loti[laureat] = 1; r.statut = 'Attribué'; r.explication = 'Lot remis au lauréat sportif.'; res.push(r); return; }
      var groupes = [];
      c.lignes.forEach(function (l) {
        if (l.hc) return; // hors concours : jamais bénéficiaire d'un lot
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
  // Coupure d'un provisoire : le dernier « coupure_jour » avant la date de publication, à « coupure_heure ».
  function coupurePour(datePublication, R) {
    for (var k = 1; k <= 7; k++) {
      var d = addDays(datePublication, -k);
      if (dow(d) === R.coupure_jour) return d + 'T' + R.coupure_heure;
    }
    return null;
  }
  // Coupure du classement final : tous les matchs de la saison comptent, jusqu'à la fin officielle
  // de la saison de Delta Force (dernier jour inclus) ; aucun gel avant la fin.
  function coupureFinale(saison) { return validD(saison && saison.fin) ? addDays(saison.fin, 1) + 'T00:00' : null; }
  // Vérification de fin de saison : « verification_finale_h » heures après la fin officielle.
  function finVerificationFinale(saison, R) {
    var c = coupureFinale(saison);
    return c ? addMinutes(c, R.verification_finale_h * 60) : null;
  }
  // Publication du classement final : le premier « publication_jour » (dimanche) qui suit la fin de la vérification.
  function publicationFinale(saison, R) {
    var v = finVerificationFinale(saison, R);
    if (!v) return null;
    var d = v.slice(0, 10);
    if (v > d + 'T00:00') d = addDays(d, 1);
    for (var k = 0; k < 7; k++) { if (dow(d) === R.publication_jour) return d; d = addDays(d, 1); }
    return null;
  }
  function publicationsPrevues(saison, today, nb, R) {
    if (!saison || !validD(saison.premier_provisoire)) return [];
    var out = [], d = saison.premier_provisoire, guard = 0;
    while (d < today && guard++ < 500) d = addDays(d, R.periodicite_jours);
    while (out.length < nb && guard++ < 600) { if (validD(saison.fin) && d > saison.fin) break; out.push(d); d = addDays(d, R.periodicite_jours); }
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
    STATS: STATS, CATS: CATS, PROVINCES: PROVINCES, CARTES: CARTES, PARAMS_REQUIS: PARAMS_REQUIS,
    regles: regles, nowStr: nowStr, versLocal: versLocal, validDT: validDT, validD: validD, normDT: normDT,
    addDays: addDays, addMinutes: addMinutes, diffMinutes: diffMinutes, dow: dow,
    inPeriods: inPeriods, suspendedAt: suspendedAt, statutAffiche: statutAffiche,
    normUid: normUid, uidValide: uidValide,
    normPseudo: normPseudo, lev: lev, resoudre: resoudre, ligneCompte: ligneCompte, membresRequis: membresRequis,
    bornesCreneau: bornesCreneau, controlesMatch: controlesMatch, motifDepuisControles: motifDepuisControles, verifierLecture: verifierLecture, comparerLectures: comparerLectures, alertesPerformance: alertesPerformance,
    matchDansClassement: matchDansClassement, ligneDansClassement: ligneDansClassement,
    agreger: agreger, quantile: quantile, classer: classer, valeur: valeur, attribuerLots: attribuerLots, classementDepuisPublication: classementDepuisPublication,
    coupurePour: coupurePour, coupureFinale: coupureFinale, finVerificationFinale: finVerificationFinale, publicationFinale: publicationFinale,
    publicationsPrevues: publicationsPrevues,
    encodeMsg: encodeMsg, decodeMsg: decodeMsg, parseLignes: parseLignes, nombre: nombre
  };
})();
if (typeof module !== 'undefined') module.exports = L;
