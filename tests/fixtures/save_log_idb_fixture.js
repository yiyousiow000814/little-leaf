'use strict';
// Deterministic, serial, atomic transaction model for observer parity tests.
// Deliberately not a substitute for a browser's IndexedDB implementation.
const clone = value => structuredClone(value);
class FixtureStore {
  constructor(tx, name) { this.transaction = tx; this.name = name; }
  request(kind, args, action) {
    const tx = this.transaction;
    tx.db.factory.trace.push([kind, tx.db.name, this.name, ...clone(args)]);
    const request = { result: undefined, error: null };
    tx.pending++;
    tx.enqueue(() => {
      if (tx.aborted) return;
      try {
        request.result = action();
        request.onsuccess?.({ target: request });
        if (kind === 'put' && tx.db.name === 'little-leaf.authoritative.v1' && tx.db.factory.abortAfterPut) {
          tx.db.factory.abortAfterPut = false;
          tx.db.factory.requestSucceededBeforeAbort = true;
          tx.abort();
        }
      } catch (error) { request.error = error; tx.error = error; tx.abort(); request.onerror?.({ target: request, preventDefault() {} }); }
      finally { tx.pending--; tx.finish(); }
    });
    return request;
  }
  get(key) { return this.request('get', [key], () => clone(this.transaction.data.get(this.name).get(key))); }
  put(value, key) {
    if (this.transaction.db.factory.throwPut) throw new DOMException('PRIVATE_QUOTA_ERROR', 'QuotaExceededError');
    return this.request('put', [value, key], () => {
    if (this.transaction.mode === 'readonly') throw new Error('Readonly write');
    this.transaction.data.get(this.name).set(key, clone(value)); return key;
  }); }
  add(value, key) { return this.request('add', [value, key], () => {
    if (this.transaction.mode === 'readonly') throw new Error('Readonly write');
    if (this.transaction.data.get(this.name).has(key)) throw new Error('Duplicate key');
    this.transaction.data.get(this.name).set(key, clone(value)); return key;
  }); }
  openCursor() {
    const tx = this.transaction, request = {};
    tx.db.factory.trace.push(['openCursor', tx.db.name, this.name]);
    let entries, index = 0;
    const advance = () => {
      tx.pending++; tx.enqueue(() => {
        if (tx.aborted) return;
        entries ||= Array.from(tx.data.get(this.name)).sort(([a], [b]) => String(a).localeCompare(String(b)));
        const entry = entries[index++];
        request.result = entry ? { key: entry[0], value: clone(entry[1]), continue: advance } : null;
        request.onsuccess?.({ target: request }); tx.pending--; tx.finish();
      });
    };
    advance(); return request;
  }
}
class FixtureTx {
  constructor(db, names, mode, upgrade = false) {
    Object.assign(this, { db, names, mode, upgrade, error: null, pending: 0, tasks: [], active: false, aborted: false, done: false });
    db.state.queue.push(this); queueMicrotask(() => db.drain());
  }
  objectStore(name) { return new FixtureStore(this, name); }
  enqueue(action) { this.tasks.push(action); this.pump(); }
  pump() { if (this.active) while (this.tasks.length) queueMicrotask(this.tasks.shift()); }
  start() {
    this.active = true;
    this.data = new Map(Array.from(this.db.state.stores, ([name, rows]) => [name, new Map(Array.from(rows, ([key, value]) => [key, clone(value)]))]));
    this.pump(); this.finish();
  }
  finish() {
    if (this.done || !this.active || (!this.aborted && this.pending)) return;
    queueMicrotask(() => {
      if (this.done || (!this.aborted && this.pending)) return;
      this.done = true;
      if (!this.aborted && this.mode !== 'readonly') this.db.state.stores = this.data;
      this.db.factory.trace.push([this.aborted ? 'abort' : 'complete', this.db.name, this.mode, this.upgrade]);
      if (!this.upgrade && this.mode === 'readwrite' && this.db.name === 'little-leaf.authoritative.v1') {
        if (this.aborted) this.db.factory.aborts++; else this.db.factory.commits++;
      }
      if (this.aborted) this.onabort?.({ target: this }); else this.oncomplete?.({ target: this });
      this.db.state.queue.shift(); this.db.drain();
    });
  }
  abort() { if (this.done) throw new Error('Transaction complete'); this.aborted = true; this.pending = 0; this.finish(); }
}
class FixtureDB {
  constructor(factory, name, state) {
    Object.assign(this, { factory, name, state, closed: false });
    this.objectStoreNames = { contains: name => state.stores.has(name) };
  }
  createObjectStore(name) {
    this.factory.trace.push(['createObjectStore', this.name, name]);
    this.state.stores.set(name, new Map()); this.upgrade.data?.set(name, new Map());
    return this.upgrade.objectStore(name);
  }
  transaction(names, mode, options) {
    this.factory.trace.push(['transaction', this.name, names, mode, options]);
    if (this.closed) throw Object.assign(new Error('Closed'), { name: 'InvalidStateError' });
    if (this.factory.fallbackStrict && options) throw new TypeError('Options unsupported');
    return new FixtureTx(this, names, mode);
  }
  close() { this.factory.trace.push(['close', this.name]); this.closed = true; }
  drain() { const next = this.state.queue[0]; if (next && !next.active) next.start(); }
}
class FixtureIDB {
  constructor() { Object.assign(this, { databases: new Map(), trace: [], commits: 0, aborts: 0, requestSucceededBeforeAbort: false }); }
  open(name, version) {
    this.trace.push(['open', name, version]);
    if (this.throwOpen) throw new DOMException('PRIVATE_ERROR_MARKER', 'SecurityError');
    const request = {};
    queueMicrotask(() => {
      let state = this.databases.get(name);
      if (!state) {
        state = { stores: new Map(), version: version || 1, queue: [] }; this.databases.set(name, state);
        const db = new FixtureDB(this, name, state); request.result = db;
        request.transaction = new FixtureTx(db, [], 'readwrite', true); db.upgrade = request.transaction;
        request.transaction.oncomplete = () => request.onsuccess?.({ target: request });
        request.transaction.onabort = () => {
          this.databases.delete(name); request.error = new DOMException('Upgrade aborted', 'AbortError');
          request.onerror?.({ target: request, preventDefault() {} });
        };
        request.onupgradeneeded?.({ target: request }); request.transaction.finish();
      } else { request.result = new FixtureDB(this, name, state); request.onsuccess?.({ target: request }); }
    });
    return request;
  }
  snapshot() {
    return JSON.stringify(Array.from(this.databases).sort(([a], [b]) => a.localeCompare(b)).map(([name, state]) => [name, Array.from(state.stores).map(([store, rows]) => [store, Array.from(rows)])]),
      (_, value) => ArrayBuffer.isView(value) ? { type: value.constructor.name, bytes: Array.from(value) } : value);
  }
}
module.exports = { FixtureIDB };
