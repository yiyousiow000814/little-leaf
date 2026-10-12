// Run against the fully guarded patched export: node this-file.js path/to/index.js
// Native deletion is stubbed; real browser acceptance remains a separate gate.
'use strict';
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
function expression(marker) {
  const start = source.indexOf(marker);
  assert(start >= 0, marker);
  const open = source.indexOf('{', start);
  let end = open + 1, depth = 1;
  while (depth) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; end++; }
  return source.slice(start + marker.length, end);
}
const scope = {GL: {counter: 1, buffers: [], vaos: [], syncs: [], textures: [], errors: [],
  recordError(code) { this.errors.push(code); }}, HEAP32: new Int32Array(3),
  GLctx: {currentPixelPackBufferBinding: 0, currentPixelUnpackBufferBinding: 0,
    deleted: 0, deleteBuffer() { this.deleted++; },
    deleteVertexArray() { this.deleted++; }, deleteSync() { this.deleted++; }}};
vm.createContext(scope);
vm.runInContext('GL.getNewId=' + expression('getNewId:'), scope);
for (const [fn, marker] of [['buffers', 'Buffers'], ['vaos', 'VertexArrays'], ['syncs', 'Sync']])
  vm.runInContext('delete_' + fn + '=' + expression('_emscripten_glDelete' + marker + '='), scope);
function create(table) { const id = scope.GL.getNewId(scope.GL[table]); const obj = {name: id}; scope.GL[table][id] = obj; return obj; }
function remove(table, obj) {
  if (table === 'syncs') scope.delete_syncs(obj.name);
  else { scope.HEAP32[0] = obj.name; scope['delete_' + table](1, 0); }
}
const survivors = ['buffers', 'vaos', 'syncs'].map(t => [t, create(t)]);
let plateau;
for (let cycle = 0; cycle < 20000; cycle++) {
  for (const table of ['buffers', 'vaos', 'syncs']) {
    const obj = create(table), id = obj.name;
    assert(id > 0);
    if (table === 'buffers') scope.GLctx.currentPixelPackBufferBinding = scope.GLctx.currentPixelUnpackBufferBinding = id;
    remove(table, obj);
    assert.strictEqual(obj.name, 0);
    assert.strictEqual(scope.GL[table][id], null);
    if (table === 'buffers') {
      assert.strictEqual(scope.GLctx.currentPixelPackBufferBinding, 0);
      assert.strictEqual(scope.GLctx.currentPixelUnpackBufferBinding, 0);
    }
    const count = scope.GL[table].littleLeafFreeIds.length;
    scope.HEAP32.set([id, id, 0]);
    if (table === 'syncs') { scope.delete_syncs(id); scope.delete_syncs(0); }
    else scope['delete_' + table](3, 0);
    assert.strictEqual(scope.GL[table].littleLeafFreeIds.length, count);
  }
  const lengths = ['buffers', 'vaos', 'syncs'].map(t => scope.GL[t].length);
  if (!cycle) plateau = lengths;
  else assert.deepStrictEqual(lengths, plateau);
  for (const [t, obj] of survivors) assert.strictEqual(scope.GL[t][obj.name], obj);
}
assert(scope.GL.errors.every(code => code === 1281));
assert.strictEqual(scope.GL.errors.length, 20000);
assert.deepStrictEqual(plateau, [5, 6, 7]);
assert.strictEqual(scope.GLctx.deleted, 60000);
const texture1 = create('textures'), texture2 = create('textures');
assert(texture2.name > texture1.name);
assert.strictEqual(scope.GL.textures.littleLeafFreeIds, undefined);
assert.strictEqual(scope.GL.counter, 9);
console.log(JSON.stringify({cycles: 20000, tableLengths: plateau, liveSurvivors: 3, counter: scope.GL.counter, result: 'passed'}));
