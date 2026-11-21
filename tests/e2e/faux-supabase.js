// Imitation en mémoire du client Supabase, pour essayer les écrans sans la vraie base.
(function () {
  const iso = () => new Date().toISOString();
  let seq = 100;
  const DB = window.FAUSSE_BASE;
  const FK = { periodes: 'membre_id', comptes_jeu: 'membre_id', comptes_periodes: 'compte_id', pseudos_historique: 'compte_id', match_lignes: 'match_id', captures: 'match_id', membres_prives: 'membre_id', demandes: 'membre_id' };
  function projeter(table, row, sel) {
    const out = Object.assign({}, row);
    const re = /([a-z_]+)\(([^()]*(?:\([^()]*\)[^()]*)*)\)/g; let m;
    while ((m = re.exec(sel))) {
      const child = m[1]; const fk = FK[child];
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
  Q.prototype.limit = function () { return this; };
  Q.prototype.range = function () { return this; };
  Q.prototype.single = function () { this.one = true; return this; };
  Q.prototype.maybeSingle = function () { this.one = true; this.maybe = true; return this; };
  Q.prototype.insert = function (o) { this.op = 'insert'; this.val = Array.isArray(o) ? o : [o]; return this; };
  Q.prototype.update = function (o) { this.op = 'update'; this.val = o; return this; };
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
      m.motif = p.p_motif; DB.registre.push({ id: ++seq, match_id: m.id, type: 'decision', detail: p.p_decision, date: iso() });
      return null;
    },
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
    storage: { from: () => ({ upload: async () => ({ data: {}, error: null }), createSignedUrl: async () => ({ data: { signedUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=' } }) }) },
    functions: { invoke: async () => ({ data: null, error: null }) }
  };
  window.supabase = { createClient: () => client };
})();
