// Imitation en mémoire du client Supabase, pour essayer les écrans sans la vraie base.
(function () {
  const iso = () => new Date().toISOString();
  let seq = 100;
  const DB = window.FAUSSE_BASE;
  const ROTATION = ['Craqué', 'Ascension', 'Ligne de tranchées', 'Accident de train', "Canal d'Akh", 'Faille'];
  const FK = { matchs: 'creneau_id', convocations: 'dossier_id', messages_litige: 'dossier_id', periodes: 'membre_id', comptes_jeu: 'membre_id', comptes_periodes: 'compte_id', pseudos_historique: 'compte_id', match_lignes: 'match_id', captures: 'match_id', membres_prives: 'membre_id', demandes: 'membre_id' };
  function projeter(table, row, sel) {
    const out = Object.assign({}, row);
    const re = /([a-z_]+)\(([^()]*(?:\([^()]*\)[^()]*)*)\)/g; let m;
    while ((m = re.exec(sel))) {
      const child = m[1]; const fk = FK[child];
      const fkUn = child.replace(/s$/, '') + '_id';
      if (fkUn in row && !FK[child + '__inverse']) { const x = (DB[child] || []).find(r => r.id === row[fkUn]); out[child] = x ? projeter(child, x, m[2]) : null; continue; }
      out[child] = (DB[child] || []).filter(r => r[fk] === row.id).map(r => projeter(child, r, m[2]));
    }
    return out;
  }
  function Q(table) {
    this.t = table; this.f = []; this.sel = '*'; this.op = 'select'; this.one = false; this.head = false; this.cnt = false; this.ord = [];
  }
  Q.prototype.select = function (s, o) { if (this.op === 'select') this.sel = s || '*'; this.ret = true; if (o && o.head) this.head = true; if (o && o.count) this.cnt = true; return this; };
  Q.prototype.eq = function (k, v) { this.f.push(r => String(r[k]) === String(v)); return this; };
  Q.prototype.neq = function (k, v) { this.f.push(r => String(r[k]) !== String(v)); return this; };
  Q.prototype.gte = function (k, v) { this.f.push(r => String(r[k]) >= String(v)); return this; };
  Q.prototype.in = function (k, v) { this.f.push(r => v.map(String).includes(String(r[k]))); return this; };
  Q.prototype.not = function (k, op, v) { this.f.push(r => r[k] !== null && r[k] !== undefined); return this; };
  Q.prototype.order = function (k, o) { this.ord.push([k, !(o && o.ascending === false)]); return this; };
  Q.prototype.is = function (k, v) { this.f.push(r => (r[k] === undefined ? null : r[k]) === v); return this; };
  Q.prototype.limit = function () { return this; };
  Q.prototype.range = function () { return this; };
  Q.prototype.single = function () { this.one = true; return this; };
  Q.prototype.maybeSingle = function () { this.one = true; this.maybe = true; return this; };
  Q.prototype.insert = function (o) { this.op = 'insert'; this.val = Array.isArray(o) ? o : [o]; return this; };
  Q.prototype.update = function (o) { this.op = 'update'; this.val = o; return this; };
  Q.prototype.upsert = function (o, opt) { this.op = 'upsert'; this.val = Array.isArray(o) ? o : [o]; this.cles = ((opt && opt.onConflict) || 'id').split(','); return this; };
  Q.prototype.then = function (res, rej) { return Promise.resolve(this.exec()).then(res, rej); };
  Q.prototype.exec = function () {
    const T = DB[this.t] = DB[this.t] || [];
    if (this.op === 'insert') {
      const rows = this.val.map(o => {
        const r = Object.assign({ id: ++seq }, o);
        if (this.t === 'captures') { r.envoyee_le = iso(); r.statut = 'recue'; DB.registre.push({ id: ++seq, match_id: r.match_id, type: 'capture_recue', detail: 'Capture reçue', date: iso() }); }
        if (this.t === 'saisons') { r.active = false; r.statut = r.statut || 'preparation'; }
        if (this.t === 'publications') { r.publie_le = iso(); r.numero = r.type === 'provisoire' ? T.filter(x => x.saison_id === r.saison_id && x.type === 'provisoire').length + 1 : null; }
        T.push(r); return r;
      });
      return { data: this.one ? rows[0] : rows, error: null };
    }
    if (this.op === 'upsert') {
      const rows = this.val.map(o => { const x = T.find(r => this.cles.every(k => String(r[k]) === String(o[k]))); if (x) return Object.assign(x, o); const r = Object.assign({ id: ++seq }, o); T.push(r); return r; });
      return { data: rows, error: null };
    }
    let rows = T.filter(r => this.f.every(f => f(r)));
    if (this.op === 'update') { rows.forEach(r => Object.assign(r, this.val)); return { data: rows, error: null }; }
    this.ord.slice().reverse().forEach(([k, asc]) => rows.sort((a, b) => (String(a[k]) < String(b[k]) ? -1 : String(a[k]) > String(b[k]) ? 1 : 0) * (asc ? 1 : -1)));
    if (this.head) return { data: null, count: rows.length, error: null };
    const data = rows.map(r => projeter(this.t, r, this.sel));
    if (this.one) return data.length ? { data: data[0], error: null } : (this.maybe ? { data: null, error: null } : { data: null, error: { message: 'introuvable' } });
    return { data, error: null, count: data.length };
  };
  const RPC = {
    est_admin: () => true,
    activer_saison: p => { DB.saisons.forEach(s => { s.active = s.id === p.p_saison; if (s.active && s.statut === 'preparation') s.statut = 'en_cours'; }); return null; },
    enregistrer_match: p => {
      p = p.p; let m;
      if (!p.id) { m = { id: ++seq, saison_id: p.saison_id, type: 'katana', demarrage: DB.parametres.find(x => x.cle === 'phase_demarrage').valeur === true, statut: 'brouillon', cree_le: iso() }; DB.matchs.push(m); DB.registre.push({ id: ++seq, match_id: m.id, type: 'match_declare', detail: 'Match de Katana enregistré', date: iso() }); }
      else { m = DB.matchs.find(x => x.id === p.id); if (!['brouillon', 'attente'].includes(m.statut)) throw new Error('Ce match est déjà tranché'); }
      const jr = p.jour_id ? (DB.jours_match || []).find(j => j.id === p.jour_id) : null;
      if (jr && DB.matchs.some(x => x.jour_id === jr.id && x.id !== m.id)) throw new Error('Un match est déjà saisi pour cette date du calendrier.');
      Object.assign(m, { saison_id: p.saison_id, carte: p.carte || (jr && jr.carte) || null, mode: p.mode || null, fin: p.fin, notes: p.notes || null });
      if (m.type === 'katana') Object.assign(m, { jour_id: p.jour_id || null, debut_annonce: p.debut_annonce || (jr && jr.debut) || null });
      DB.match_lignes = DB.match_lignes.filter(l => l.match_id !== m.id);
      (p.lignes || []).forEach((l, i) => { const c = l.compte_id ? DB.comptes_jeu.find(x => x.id === l.compte_id) : null; DB.match_lignes.push(Object.assign({ id: ++seq, match_id: m.id, rang: i + 1, membre_id: c ? c.membre_id : null }, l)); });
      return m.id;
    },
    decider_match: p => {
      const m = DB.matchs.find(x => x.id === p.p_match);
      const caps = DB.captures.filter(c => c.match_id === m.id);
      if (p.p_decision === 'valider') { if (!caps.length) throw new Error('Ajoutez au moins une capture avant de valider.'); m.statut = 'valide'; m.valide_le = iso(); caps.forEach(c => { c.statut = 'retenue'; }); }
      else m.statut = { attente: 'attente', refuser: 'refuse', annuler: 'annule', brouillon: 'brouillon' }[p.p_decision];
      if (m.statut === 'attente' && !(DB.dossiers || []).some(d => d.match_id === m.id)) (DB.dossiers = DB.dossiers || []).push({ id: ++seq, match_id: m.id, ouvert_le: iso(), statut: 'ouvert', est_litige: null });
      m.motif = p.p_motif; DB.registre.push({ id: ++seq, match_id: m.id, type: 'decision', detail: p.p_decision, date: iso() });
      return null;
    },
    sanctionner: p => {
      p = p.p; const t = new Date();
      const fin = p.type === 'suspension' ? new Date(p.fin_jour + 'T00:00:00+03:00').getTime() + 86400000 : null;
      const r = { id: ++seq, membre_id: p.membre_id, type: p.type, motif: p.motif, categorie: p.categorie, debut: t.toISOString(), fin: fin ? new Date(fin).toISOString() : null, match_id: p.match_id || null, recours_jusqu: new Date(t.getTime() + 48 * 3600000).toISOString(), statut: 'active', cree_le: t.toISOString() };
      (DB.sanctions = DB.sanctions || []).push(r); return r.id;
    },
    decider_sanction: p => { const s = DB.sanctions.find(x => x.id === p.p_sanction); if (p.p_decision === 'lever') s.statut = 'levee'; else s.decision_recours = 'maintenue'; s.motif_recours = p.p_motif; s.recours_decide_le = iso(); return null; },
    qualifier_dossier: p => { const d = DB.dossiers.find(x => x.id === p.p_dossier); d.est_litige = p.p_litige; d.faits = p.p_faits; return null; },
    convoquer: p => { (DB.convocations = DB.convocations || []).push({ id: ++seq, dossier_id: p.p_dossier, membre_id: p.p_membre, role: p.p_role, convoque_le: iso(), confirme_le: null }); return null; },
    ecrire_litige: p => { const d = DB.dossiers.find(x => x.id === p.p_dossier); if (d.statut !== 'ouvert') throw new Error('La discussion est fermée'); (DB.messages_litige = DB.messages_litige || []).push({ id: ++seq, dossier_id: p.p_dossier, membre_id: null, texte: p.p_texte, cree_le: iso() }); return null; },
    trancher_dossier: p => {
      const d = DB.dossiers.find(x => x.id === p.p_dossier), m = DB.matchs.find(x => x.id === d.match_id);
      DB.captures.filter(c => c.match_id === m.id).forEach(c => { c.statut = p.p_decision === 'capture_retenue' && c.id === p.p_capture ? 'retenue' : 'ecartee'; });
      m.statut = { capture_retenue: 'valide', match_refuse: 'refuse', match_annule: 'annule' }[p.p_decision];
      Object.assign(d, { statut: 'tranche', decision: p.p_decision, capture_retenue_id: p.p_capture, motif_decision: p.p_motif, decide_le: iso() }); return null;
    },
    valider_synthese: p => { const d = DB.dossiers.find(x => x.id === p.p_dossier); Object.assign(d, { synthese: p.p_synthese, synthese_validee_le: iso(), statut: 'archive' }); return null; },
    captures_a_supprimer: p => { const d = DB.dossiers.find(x => x.id === p.p_dossier); return DB.captures.filter(c => c.match_id === d.match_id && c.statut === 'ecartee').map(c => c.chemin); },
    noter_captures_supprimees: p => { DB.dossiers.find(x => x.id === p.p_dossier).captures_supprimees_le = iso(); return null; },
    sanctionner_dossier: p => { DB.sanctions.find(x => x.id === p.p_sanction).dossier_id = p.p_dossier; return null; },
    repondre_membre: p => { (DB.messages = DB.messages || []).push({ id: ++seq, membre_id: p.p_membre, de_katana: true, texte: p.p_texte, publication_id: null, cree_le: iso(), lu_le: null }); DB.notifications.push({ id: ++seq, membre_id: p.p_membre, texte: 'Nouveau message de Katana', lu: false }); return null; },
    marquer_messages_lus: p => { (DB.messages || []).filter(m => m.membre_id === p.p_membre && !m.de_katana && !m.lu_le).forEach(m => { m.lu_le = iso(); }); return null; },
    marquer_creneaux_vus: () => { DB.creneaux.filter(c => !c.vu_le && c.statut !== 'retenu').forEach(c => { c.vu_le = iso(); }); return null; },
    decider_creneau: p => { const c = DB.creneaux.find(x => x.id === p.p_creneau); c.statut = p.p_decision === 'accepter' ? 'annonce' : 'refuse'; c.vu_le = iso(); if (c.statut === 'annonce') DB.matchs.push({ id: ++seq, saison_id: c.saison_id, type: 'libre', demarrage: false, statut: 'brouillon', creneau_id: c.id, cree_le: iso() }); return null; },
    annuler_creneau: p => { const c = DB.creneaux.find(x => x.id === p.p_creneau); c.statut = 'annule'; c.motif = p.p_motif; DB.matchs.filter(m => m.creneau_id === c.id).forEach(m => { m.statut = 'annule'; }); return null; },
    noter_lecture: p => { DB.captures.filter(c => p.p_captures.includes(c.id)).forEach(c => { c.lecture = p.p_lecture; }); return null; },
    accepter_capture_retard: p => { const c = DB.captures.find(x => x.id === p.p_capture); c.exception = p.p_motif; c.statut = 'recue'; return null; },
    ecarter_captures: p => { const l = DB.captures.filter(c => c.match_id === p.p_match && p.p_captures.includes(c.id) && c.statut === 'recue'); l.forEach(c => { c.statut = 'ecartee'; c.motif = p.p_motif; }); return l.map(c => c.chemin); },
    // Prochains événements (migration 0016). Rôle imité : window.FAUX_ROLE = 'admin' (par défaut), 'membre' ou 'suspendu' ;
    // window.FAUX_MOI = identifiant du membre imité (1 par défaut).
    prochains_evenements: () => {
      const role = window.FAUX_ROLE || 'admin', adm = role === 'admin', moi = adm ? null : (window.FAUX_MOI || 1), actif = role === 'membre';
      const t = Date.now(), plage = 3600000, mb = id => { const x = DB.membres.find(m => m.id === id); return x ? { matricule: x.matricule, nom_gamer: x.nom_gamer } : null; };
      const J = (DB.jours_match || []).slice().sort((a, b) => a.jour.localeCompare(b.jour));
      const jours = J.filter(j => new Date(j.debut).getTime() + plage > t).slice(0, 6).map(j => {
        const sa = (DB.salles || []).find(x => x.jour_id === j.id), parts = (DB.participations || []).filter(x => x.jour_id === j.id);
        const ouv = j.statut === 'prevu' && t < new Date(j.debut).getTime() + plage, prev = J.filter(x => x.jour < j.jour && x.statut !== 'annule').pop();
        return { id: j.id, jour: j.jour, debut: j.debut, carte: j.statut === 'annule' ? null : j.carte, statut: j.statut, motif: j.motif || null, reporte_de: prev && prev.statut === 'reporte' ? prev.jour : null,
          participants: parts.length, moi: moi !== null && parts.some(x => x.membre_id === moi), noms: adm ? parts.map(x => mb(x.membre_id)) : null,
          code: role !== 'suspendu' && ouv && sa ? sa.code : null, mot_de_passe: role !== 'suspendu' && ouv && sa ? sa.mot_de_passe : null, salle_saisie: !!sa && ouv };
      });
      const libres = (DB.creneaux || []).filter(c => c.statut === 'annonce' && new Date(c.debut).getTime() + plage > t).map(c => {
        const sa = (DB.salles || []).find(x => x.creneau_id === c.id), orga = c.organisateur_id === moi, voit = role !== 'suspendu' || false;
        return { id: c.id, debut: c.debut, organisateur: mb(c.organisateur_id), haavk: mb(c.resp_haavk_id), gti: mb(c.resp_gti_id), moi_organisateur: orga,
          code: voit && sa ? sa.code : null, mot_de_passe: voit && sa ? sa.mot_de_passe : null, salle_saisie: !!sa };
      });
      const evenements = (DB.evenements || []).filter(e => !e.retire_le && new Date(e.fin || new Date(e.debut).getTime() + 86400000).getTime() > t).sort((a, b) => String(a.debut).localeCompare(String(b.debut)));
      return { maintenant: new Date().toISOString(), voit_code: role !== 'suspendu', peut_participer: actif, admin: adm, rotation: ROTATION, heure: '16:05', salle_ouverture_min: 15, jours, libres, evenements };
    },
    participer: p => {
      if (window.FAUX_ROLE !== 'membre') throw new Error('Démarche impossible pendant une suspension.');
      const moi = window.FAUX_MOI || 1; DB.participations = (DB.participations || []).filter(x => !(x.jour_id === p.p_jour && x.membre_id === moi));
      if (p.p_oui) DB.participations.push({ jour_id: p.p_jour, membre_id: moi, cree_le: iso() }); return null;
    },
    noter_salle: p => {
      p = p.p; DB.salles = DB.salles || [];
      const k = p.jour_id ? 'jour_id' : 'creneau_id', id = p.jour_id || p.creneau_id;
      DB.salles = DB.salles.filter(x => x[k] !== id);
      if (p.code || p.mot_de_passe) DB.salles.push({ id: ++seq, [k]: id, code: p.code || null, mot_de_passe: p.mot_de_passe || null, modifie_le: iso() });
      return null;
    },
    calendrier_admin: () => (DB.jours_match || []).slice().sort((a, b) => a.jour.localeCompare(b.jour)).map(j => {
      const sa = (DB.salles || []).find(x => x.jour_id === j.id), mt = DB.matchs.find(m => m.jour_id === j.id), t = Date.now();
      return { id: j.id, jour: j.jour, debut: j.debut, carte: j.carte, statut: j.statut, motif: j.motif || null, modifiable: true, passe: new Date(j.debut).getTime() <= t,
        salle_ouverte: t < new Date(j.debut).getTime() + 3600000, code: sa ? sa.code : null, mot_de_passe: sa ? sa.mot_de_passe : null,
        match_id: mt ? mt.id : null, match_statut: mt ? mt.statut : null,
        noms: (DB.participations || []).filter(x => x.jour_id === j.id).map(x => { const m = DB.membres.find(y => y.id === x.membre_id); return { matricule: m.matricule, nom_gamer: m.nom_gamer }; }) };
    }),
    decider_jour: p => {
      const j = DB.jours_match.find(x => x.id === p.p_jour);
      if (p.p_decision === 'retablir') { j.statut = 'prevu'; j.motif = null; }
      else { j.statut = p.p_decision === 'reporter' ? 'reporte' : 'annule'; j.motif = p.p_motif || (p.p_decision === 'reporter' ? 'Carte manquante' : null); }
      // Même calcul que calendrier_recalculer() : la 1re date garde sa carte ; reporte = même carte à la date suivante.
      const J = DB.jours_match.slice().sort((a, b) => a.jour.localeCompare(b.jour)); let idx = 0;
      J.forEach((r, i) => {
        if (i === 0) { const ps = ROTATION.indexOf(r.carte); if (ps >= 0) idx = ps + (r.statut === 'prevu' ? 1 : 0); return; }
        if (r.statut === 'annule') { r.carte = null; return; }
        r.carte = ROTATION[idx % ROTATION.length]; if (r.statut === 'prevu') idx++;
      });
      return null;
    },
    // Rappels (migration 0020) : rien n'est envoyé ; l'état imite une clé prête et 2 téléphones.
    rappels_moi: () => ({ peut: true, actifs: true, cle_publique: 'B' + 'A'.repeat(86), telephones: (DB.abonnements_push || []).length }),
    abonner_rappels: p => { (DB.abonnements_push = DB.abonnements_push || []).push(p.p); return null; },
    desabonner_rappels: p => { DB.abonnements_push = (DB.abonnements_push || []).filter(x => x.endpoint !== p.p_endpoint); return null; },
    essai_rappel: () => null,
    rappels_admin: () => ({ actifs: true, tache: true, cle_prete: true, telephones: 2, personnes: 2, en_echec: 0, dernier_reveil: '2026-11-21T07:00:00Z',
      dernier_envoi: '2026-11-21T07:00:05Z', dernier_bilan: { envoyes: 2, echecs: 0, oublies: 0, messages: 1 }, envoyes_7j: 3 }),
    identifier_ligne: p => { const l = DB.match_lignes.find(x => x.id === p.p_ligne); l.resolution = p.p_compte ? 'manuel' : 'non_inscrit_confirme'; l.identifie_le = iso(); return null; }
  };
  const client = {
    auth: {
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      getSession: async () => ({ data: { session: localStorage.getItem('faux-visiteur') ? null : { user: { id: 'admin-faux', email: 'admin@test.invalid' } } } }),   // faux-visiteur : personne n'est connecté
      signOut: async () => ({})
    },
    from: t => new Q(t),
    rpc: async (n, p) => { window.APPELS = (window.APPELS || []).concat([[n, p]]); try { return { data: RPC[n] ? RPC[n](p || {}) : null, error: null }; } catch (e) { return { data: null, error: { message: e.message } }; } },
    storage: { from: () => ({ remove: async () => ({ data: [], error: null }), upload: async () => ({ data: {}, error: null }), createSignedUrl: async () => ({ data: { signedUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=' } }) }) },
    functions: { invoke: async (n, o) => { window.APPELS = (window.APPELS || []).concat([['fonction:' + n, o && o.body]]); return window.FAUX_INVOKE ? window.FAUX_INVOKE(n, o) : { data: null, error: null }; } }
  };
  window.supabase = { createClient: () => client };
})();
