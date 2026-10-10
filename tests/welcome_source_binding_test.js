'use strict';
const {sourcePath}=require('./source_paths.js');
// Source binding only: no audio observations, browser or engine execution.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const {hash} = require('./wall_compatibility_helpers');
const {verifySource, SERVICE_MP3} = require('./welcome_audio_helpers');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'welcome-source-binding-'));
let checks = 0;
try {
  const source = path.join(temp, 'source'), web = path.join(temp, 'web');
  fs.mkdirSync(source); fs.mkdirSync(web);
  const git = (...args) => cp.execFileSync('git', ['-c', 'user.name=Offline QA', '-c',
    'user.email=qa@example.invalid', ...args], {cwd: source, encoding: 'utf8'}).trim();
  git('init', '-q');
  const files = {'project.godot': 'synthetic source', [SERVICE_MP3]: 'synthetic hash fixture'};
  for (const [name, text] of Object.entries(files)) {
    const file = sourcePath(source,name);
    fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text);
  }
  git('add', '.'); git('commit', '-qm', 'Synthetic head H');
  const head = git('rev-parse', 'HEAD');
  git('commit', '--allow-empty', '-qm', 'Synthetic same-tree built merge M');
  const built = git('rev-parse', 'HEAD');
  git('checkout', '-q', head);
  const bytes = Buffer.from('synthetic packed bytes');
  fs.writeFileSync(path.join(web, 'index.pck'), bytes);
  const manifest = {source_commit: built, toolchain_verification: 'checksum-pinned-official-archives',
    packed_smoke: 'passed', production_sha256: Object.fromEntries(Object.entries(files).map(([n, t]) => [n, hash(t)])),
    files: {'index.pck': {bytes: bytes.length, sha256: hash(bytes)}}};
  const save = m => fs.writeFileSync(path.join(web, 'release-manifest.json'), JSON.stringify(m));
  save(manifest);
  const binding = verifySource(web, source, built);
  assert.notEqual(head, built); assert.equal(binding.source_commit, head);
  assert.equal(binding.built_source_commit, built); checks++;
  assert.equal(verifySource(web, source).built_source_commit, built); checks++;
  assert.throws(() => verifySource(web, source, head), /exact source commit/); checks++;
  fs.appendFileSync(path.join(web, 'index.pck'), '!');
  assert.throws(() => verifySource(web, source, built), /size/); checks++;
  fs.writeFileSync(path.join(web, 'index.pck'), bytes);
  save({...manifest, production_sha256: {}});
  assert.throws(() => verifySource(web, source, built), /Source differs/); checks++;
  git('checkout', '-q', built);
  fs.writeFileSync(path.join(source, 'project.godot'), 'changed source');
  git('add', '.'); git('commit', '-qm', 'Synthetic changed merge');
  const changed = git('rev-parse', 'HEAD'); git('checkout', '-q', head);
  save({...manifest, source_commit: changed, production_sha256: {...manifest.production_sha256,
    'project.godot': hash('changed source')}});
  assert.throws(() => verifySource(web, source, changed), /source trees must be identical/); checks++;
  console.log(JSON.stringify({checks, failures: [], scope: 'Synthetic Git H/M source and packed-file binding only'}));
} finally {fs.rmSync(temp, {recursive: true, force: true});}
