// La sauvegarde complète (Administration > Sauvegarde) doit lire toutes les tables créées par les migrations.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const racine = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(racine, 'index.html'), 'utf8');
const liste = html.match(/const TABLES_SAUVEGARDE = \[([^\]]*)\]/);
const sauvegardees = liste ? [...liste[1].matchAll(/'([a-z_]+)'/g)].map(m => m[1]) : [];

const dossier = path.join(racine, 'supabase', 'migrations');
const creees = fs.readdirSync(dossier).filter(f => f.endsWith('.sql')).sort()
  .flatMap(f => [...fs.readFileSync(path.join(dossier, f), 'utf8').matchAll(/create table (?:if not exists )?public\.([a-z_]+)/gi)].map(m => m[1]));

test('la liste des tables sauvegardées est lisible', () => {
  assert.ok(sauvegardees.length > 0);
});

test('chaque table créée par une migration est dans la sauvegarde', () => {
  const oubliees = creees.filter(t => !sauvegardees.includes(t));
  assert.deepEqual(oubliees, [], 'Tables absentes de TABLES_SAUVEGARDE : ' + oubliees.join(', '));
});

test('la sauvegarde ne cite que des tables qui existent', () => {
  const inconnues = sauvegardees.filter(t => !creees.includes(t));
  assert.deepEqual(inconnues, [], 'Tables inconnues : ' + inconnues.join(', '));
});

test('la sauvegarde lit toutes les colonnes de chaque table (dont membres.hors_concours, migration 0020)', () => {
  assert.ok(sauvegardees.includes('membres'));
  assert.match(html, /SB\.from\(t\)\.select\('\*'\)/);
  const mig = fs.readFileSync(path.join(dossier, '0020_hors_concours.sql'), 'utf8');
  assert.match(mig, /alter table public\.membres add column hors_concours boolean not null default false/);
});
