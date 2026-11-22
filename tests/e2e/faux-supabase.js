// Imitation en mémoire du client Supabase, pour essayer les écrans sans la vraie base.
(function () {
  const iso = () => new Date().toISOString();
  let seq = 100;
  const DB = window.FAUSSE_BASE;
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
      Object.assign(m, { saison_id: p.saison_id, carte: p.carte || null, mode: p.mode || null, fin: p.fin, notes: p.notes || null });
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
    identifier_ligne: p => { const l = DB.match_lignes.find(x => x.id === p.p_ligne); l.resolution = p.p_compte ? 'manuel' : 'non_inscrit_confirme'; l.identifie_le = iso(); return null; }
  };
  const client = {
    auth: {
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      getSession: async () => ({ data: { session: { user: { id: 'admin-faux', email: 'admin@test.invalid' } } } }),
      signOut: async () => ({})
    },
    from: t => new Q(t),
    rpc: async (n, p) => { window.APPELS = (window.APPELS || []).concat([[n, p]]); try { return { data: RPC[n] ? RPC[n](p || {}) : null, error: null }; } catch (e) { return { data: null, error: { message: e.message } }; } },
    storage: { from: () => ({ remove: async () => ({ data: [], error: null }), upload: async () => ({ data: {}, error: null }), createSignedUrl: async () => ({ data: { signedUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=' } }) }) },
    functions: { invoke: async (n, o) => { window.APPELS = (window.APPELS || []).concat([['fonction:' + n, o && o.body]]); return window.FAUX_INVOKE ? window.FAUX_INVOKE(n, o) : { data: null, error: null }; } }
  };
  window.supabase = { createClient: () => client };
})();
