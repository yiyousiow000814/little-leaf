/* Little Leaf authoritative Web storage. Never mounts or writes Godot IDBFS. */
(function (root) {
  'use strict';
  // This observer never participates in a transaction or changes a result.
  function observe(event, fields = {}) {
    try { if (root.LittleLeafSaveLog) root.LittleLeafSaveLog.record(event, { layer: 'vault', ...fields }); } catch (_) {}
  }
  const DB_NAME = 'little-leaf.authoritative.v1';
  const STORE = 'profiles';
  const ACTIVE = 'active';
  const IDENTITY = 'identity';
  const LIMIT = 1048576;
  const MAX_COINS = 1000000000;
  // Campaign identity is permanent. Disabled/retired configurations never
  // remove receipts or reverse an award. Retired IDs must not be reused.
  const CAMPAIGNS = Object.freeze([Object.freeze({ id: 'little-leaf-0.1.5-existing-profile-compensation', coins: 1000, audience: 'legacy-v13', state: 'enabled' })]);
  function campaignConfig(config) {
    if (!Array.isArray(config)) throw fail('CAMPAIGN_CONFIG', 'Invalid campaign configuration');
    const seen = new Set();
    return config.map(c => {
      if (!c || typeof c.id !== 'string' || !/^[a-z0-9][a-z0-9._-]{0,127}$/.test(c.id) || seen.has(c.id) || !Number.isSafeInteger(c.coins) || c.coins < 1 || c.coins > MAX_COINS || c.audience !== 'legacy-v13' || !['enabled', 'disabled', 'retired'].includes(c.state)) throw fail('CAMPAIGN_CONFIG', 'Invalid campaign configuration');
      seen.add(c.id); return Object.freeze({ ...c });
    });
  }
  function validReceipts(record) {
    const receipts = record.campaigns;
    if (record.format === 1) {
      if (Object.hasOwn(record, 'campaigns')) throw fail('CORRUPT_AUTHORITY', 'Unexpected campaign data in old save format');
      return;
    }
    if (!receipts || typeof receipts !== 'object' || Array.isArray(receipts) || Object.keys(receipts).length > 128) throw fail('CORRUPT_AUTHORITY', 'Campaign receipts are damaged');
    for (const [id, receipt] of Object.entries(receipts)) {
      if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(id) || !receipt || receipt.status !== 'granted' || !Number.isSafeInteger(receipt.coins) || receipt.coins < 1 || receipt.coins > MAX_COINS || !Number.isSafeInteger(receipt.revision) || receipt.revision < 1 || receipt.revision > record.revision || !Number.isFinite(receipt.grantedAt) || receipt.grantedAt < 0 || Object.keys(receipt).sort().join(',') !== 'coins,grantedAt,revision,status') throw fail('CORRUPT_AUTHORITY', 'Campaign receipt is invalid');
    }
  }
  function planCampaigns(payload, origin, current, config, nextRevision, now) {
    const data = parsePayload(payload, 15);
    if (!Number.isSafeInteger(data.coins) || data.coins < 0 || data.coins > MAX_COINS) throw fail('INVALID_SAVE', 'Invalid save wallet');
    const receipts = { ...(current.campaigns || {}) }, awards = [], deferred = [];
    let credit = 0;
    if (origin.source === 'legacy-v13') for (const campaign of config) {
      if (campaign.state !== 'enabled' || Object.hasOwn(receipts, campaign.id)) continue;
      if (data.coins > MAX_COINS - campaign.coins) { deferred.push({ id: campaign.id, coins: campaign.coins, reason: 'wallet_cap' }); continue; }
      data.coins += campaign.coins; credit += campaign.coins;
      receipts[campaign.id] = { status: 'granted', coins: campaign.coins, revision: nextRevision, grantedAt: now };
      awards.push({ id: campaign.id, coins: campaign.coins });
    }
    return { payload: credit ? JSON.stringify(data) : payload, receipts, awards, deferred, credit };
  }
  const SCHEMA = 'little_leaf_reconstructed_cafe';
  const CHECKOUT = 'little_leaf.checkout.v1';
  const MOTION = 'little_leaf.layout_motion.v1';
  const fail = (code, message) => Object.assign(new Error(message), { code });
  const resultError = error => ({ ok: false, code: (typeof error.code === 'string' && error.code) || error.name || 'STORAGE_ERROR', error: error.message || String(error) });
  const uuid = () => root.crypto.randomUUID();
  async function hash(text) {
    const bytes = new TextEncoder().encode(text);
    const digest = await root.crypto.subtle.digest('SHA-256', bytes);
    return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
  }
  function parsePayload(text, version) {
    if (typeof text !== 'string' || new TextEncoder().encode(text).length > LIMIT) throw fail('INVALID_SAVE', 'Save is unreadable or too large');
    let data;
    try { data = JSON.parse(text); } catch (_) { throw fail('INVALID_SAVE', 'Invalid save JSON'); }
    if (!data || typeof data !== 'object' || Array.isArray(data) || data.schema !== SCHEMA || data.version !== version || data.new_reconstruction !== true || data.checkout_format !== CHECKOUT) throw fail('INVALID_SAVE', 'Unsupported save format');
    if (version === 15 && data.layout_motion_format !== MOTION) throw fail('INVALID_SAVE', 'Missing layout movement format');
    if (version === 13 && Object.hasOwn(data, 'layout_motion_format')) throw fail('INVALID_SAVE', 'Legacy save has a foreign movement format');
    return data;
  }
  function fingerprint(record) {
    const value = { format: record.format, profileId: record.profileId, revision: record.revision, createdAt: record.createdAt, updatedAt: record.updatedAt, origin: record.origin, payload: record.payload };
    if (record.format === 2) value.campaigns = record.campaigns;
    return JSON.stringify(value);
  }
  function validRecord(record) {
    if (!record || ![1, 2].includes(record.format) || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(record.profileId) || !Number.isSafeInteger(record.revision) || record.revision < 0 || !Number.isFinite(record.createdAt) || !Number.isFinite(record.updatedAt)) throw fail('CORRUPT_AUTHORITY', 'Authoritative save identity is damaged; recovery is required');
    validReceipts(record);
    if (record.revision === 0) {
      if (record.payload !== null || record.digest !== null || record.origin !== null || record.previous !== null) throw fail('CORRUPT_AUTHORITY', 'Uncommitted save record is damaged');
    } else {
      const origin = record.origin;
      if (typeof record.payload !== 'string' || !/^[a-f0-9]{64}$/.test(record.digest) || !origin || !['fresh', 'legacy-v13', 'import-v15'].includes(origin.source) || !Number.isFinite(origin.importedAt) || (origin.source === 'legacy-v13' ? !/^[a-f0-9]{64}$/.test(origin.legacyDigest) : origin.legacyDigest !== null) || Object.keys(origin).sort().join(',') !== 'importedAt,legacyDigest,source') throw fail('CORRUPT_AUTHORITY', 'Authoritative save record or migration provenance is damaged');
    }
    return record;
  }
  async function verifyRecord(record) {
    validRecord(record);
    if (record.revision) {
      parsePayload(record.payload, 15);
      if (await hash(fingerprint(record)) !== record.digest) throw fail('CORRUPT_AUTHORITY', 'Authoritative save checksum failed; recovery is required');
    }
    return record;
  }
  function openDB(factory, name, create) {
    return new Promise((resolve, reject) => {
      let request, settled = false, absent = false;
      const timer = setTimeout(() => { settled = true; reject(fail('STORAGE_BLOCKED', 'Browser storage did not open in time; keep this page open or reload')); }, 10000);
      function done(error, db) {
        clearTimeout(timer);
        if (settled) { if (db) db.close(); return; }
        settled = true;
        if (error) reject(error); else resolve(db);
      }
      try { request = create ? factory.open(name, 1) : factory.open(name); }
      catch (error) { done(error); return; }
      request.onupgradeneeded = () => {
        if (settled) { request.transaction.abort(); return; }
        if (!create) { absent = true; request.transaction.abort(); return; }
        // Identity + empty profile are installed in the schema transaction.
        // An interruption rolls back the entire new database. A missing row in
        // an existing database is corruption, never evidence of a fresh player.
        const store = request.result.createObjectStore(STORE);
        const id = uuid(), now = Date.now();
        store.add({ format: 2, profileId: id, revision: 0, createdAt: now, updatedAt: now, payload: null, digest: null, origin: null, previous: null, campaigns: {} }, ACTIVE);
        store.add({ format: 1, profileId: id, createdAt: now }, IDENTITY);
      };
      request.onerror = event => { event.preventDefault(); done(absent ? null : request.error, null); };
      request.onblocked = () => done(fail('STORAGE_BLOCKED', 'Storage upgrade is blocked by another tab; close it and reload'));
      request.onsuccess = () => {
        const db = request.result;
        db.onversionchange = () => db.close();
        done(null, db);
      };
    });
  }
  function transaction(db, mode, action) {
    return new Promise((resolve, reject) => {
      let tx, value, actionError, stage = 'transaction_create';
      const mark = value => { stage = value; };
      const tagged = error => Object.assign(new Error(resultError(error).error), { code: resultError(error).code, storageStage: stage, transactionCreated: !!tx });
      try {
        // Strict durability asks supported browsers to flush before completion.
        // Browsers without the options overload retain atomic transaction semantics.
        try { tx = db.transaction(STORE, mode, mode === 'readwrite' ? { durability: 'strict' } : undefined); }
        catch (error) { if (!(error instanceof TypeError)) throw error; tx = db.transaction(STORE, mode); }
        tx.oncomplete = () => { mark('transaction_complete'); resolve(value); };
        tx.onerror = () => {}; // Abort is the authoritative failure boundary.
        tx.onabort = () => reject(actionError || tagged(tx.error || fail('STORAGE_ABORT', 'Save transaction aborted; previous progress is unchanged')));
        const rejectAction = error => { actionError = tagged(error); try { tx.abort(); } catch (_) { reject(actionError); } };
        mark('object_store');
        action(tx.objectStore(STORE), result => { value = result; }, rejectAction, mark);
      } catch (error) { const failure = tagged(error); if (tx) { actionError = failure; try { tx.abort(); } catch (_) {} } reject(failure); }
    });
  }
  async function readLegacy(factory) {
    const db = await openDB(factory, '/userfs', false);
    if (!db) return null;
    try {
      if (!db.objectStoreNames.contains('FILE_DATA')) throw fail('LEGACY_UNREADABLE', 'Legacy browser storage has an unknown format');
      const entries = await new Promise((resolve, reject) => {
        const tx = db.transaction('FILE_DATA', 'readonly');
        const found = [];
        tx.onabort = () => reject(tx.error || fail('LEGACY_UNREADABLE', 'Legacy read failed'));
        tx.onerror = () => {};
        tx.oncomplete = () => resolve(found);
        tx.objectStore('FILE_DATA').openCursor().onsuccess = event => {
          const cursor = event.target.result;
          if (!cursor) return;
          const path = String(cursor.key);
          // Exact v13 profile only. Never choose another experimental profile.
          if (/^\/userfs\/(?:[^/]+\/)*little_leaf_cafe_v13\.json$/.test(path)) found.push({ path, entry: cursor.value });
          cursor.continue();
        };
      });
      if (entries.length > 1) throw fail('AMBIGUOUS_LEGACY', 'Several legacy cafés were found; choose a recovery file explicitly');
      if (!entries.length) return null;
      const { path, entry } = entries[0];
      // Godot native writes use signed HEAP8; IDBFS preserves that byte view.
      if (!entry || !(entry.contents instanceof Uint8Array || entry.contents instanceof Int8Array) || entry.contents.byteLength > LIMIT) throw fail('LEGACY_UNREADABLE', 'Legacy save is unreadable or too large');
      let payload;
      try { payload = new TextDecoder('utf-8', { fatal: true }).decode(entry.contents); } catch (_) { throw fail('INVALID_SAVE', 'Legacy save has invalid text encoding'); }
      parsePayload(payload, 13);
      return { payload, path, digest: await hash(payload) };
    } finally { db.close(); }
  }
  // Presentation projection only. Receipt values come from the verified
  // envelope, including retired campaigns; nothing is inferred from balance.
  function inboxSnapshot(record, campaigns) {
    const paid = Object.entries(record.campaigns || {}).map(([id, receipt]) => ({ id, ...receipt }));
    paid.sort((a, b) => b.grantedAt - a.grantedAt || b.revision - a.revision || a.id.localeCompare(b.id));
    const deferred = record.revision ? planCampaigns(record.payload, record.origin, record, campaigns, record.revision + 1, Date.now()).deferred : [];
    return { ok: true, profileId: record.profileId, revision: record.revision, paid, deferred };
  }
  function createClient(options = {}) {
    // Dependencies may be supplied only by the isolated test harness. The live
    // singleton always uses this origin's IndexedDB and fixed namespace.
    let factory = options.indexedDB, campaigns = null;
    let db = null, record = null, legacy = null, opening = null, busy = false, faulted = false;
    let inboxJson = JSON.stringify({ ok: false });
    let connectionGeneration = 0;
    function installConnection(connection, stage) {
      db = connection;
      const generation = ++connectionGeneration;
      observe('connection_opened', { stage, connectionGeneration: generation });
      connection.onversionchange = () => {
        observe('connection_closed', { stage: 'versionchange', connectionGeneration: generation });
        connection.close();
      };
      connection.onclose = () => observe('connection_closed', { stage: 'forced_close', connectionGeneration: generation });
    }
    function readCurrent(store, resolve, abort, mark) {
      mark('get_identity'); const identityRequest = store.get(IDENTITY);
      identityRequest.onerror = () => mark('get_identity');
      mark('get_active'); const request = store.get(ACTIVE);
      request.onerror = () => mark('get_active');
      request.onsuccess = () => {
        try {
          mark('active_result'); const current = validRecord(request.result);
          mark('identity_result'); const identity = identityRequest.result;
          if (!identity || identity.format !== 1 || identity.profileId !== current.profileId || identity.createdAt !== current.createdAt) throw fail('CORRUPT_AUTHORITY', 'Authoritative profile identity is missing or damaged; recovery is required');
          resolve(current);
        } catch (error) { abort(error); }
      };
    }
    function compareCurrent(current, expectedRevision, expectedProfileId) {
      if (current.profileId !== expectedProfileId || current.revision !== expectedRevision || current.digest !== record.digest) throw fail('REVISION_CONFLICT', 'Another tab saved newer progress; this tab was not saved. Reload before continuing');
      if (fingerprint(current) !== fingerprint(record)) throw fail('CORRUPT_AUTHORITY', 'Saved progress changed unexpectedly; recovery is required');
    }
    async function reopenExisting(expectedRevision, expectedProfileId) {
      observe('connection_reopen_requested', { code: 'InvalidStateError', stage: 'transaction_create', connectionGeneration });
      db.close();
      const connection = await openDB(factory, DB_NAME, false);
      if (!connection) throw fail('CORRUPT_AUTHORITY', 'Saved café storage is missing; keep this page open for recovery');
      try {
        if (connection.version !== 1 || !connection.objectStoreNames.contains(STORE)) throw fail('CORRUPT_AUTHORITY', 'Saved café storage changed format; keep this page open for recovery');
        const current = await transaction(connection, 'readonly', readCurrent);
        await verifyRecord(current);
        compareCurrent(current, expectedRevision, expectedProfileId);
        installConnection(connection, 'reopen_existing');
      } catch (error) { connection.close(); throw error; }
    }
    const client = {
      bootJson: '',
      // A serialized copy cannot mutate the authority or its previous record.
      snapshotJson() { return inboxJson; },
      async boot() {
        if (opening) return opening;
        observe('boot_requested');
        opening = (async () => {
          try {
            campaigns = campaignConfig(options.campaigns === undefined ? CAMPAIGNS : options.campaigns);
            if (!factory) factory = root.indexedDB;
            if (!factory || !root.crypto || !root.crypto.subtle) throw fail('STORAGE_UNAVAILABLE', 'Durable browser storage is unavailable');
            installConnection(await openDB(factory, DB_NAME, true), 'boot_open');
            if (!db.objectStoreNames.contains(STORE)) throw fail('CORRUPT_AUTHORITY', 'Authoritative save store is missing');
            record = await transaction(db, 'readonly', readCurrent);
            await verifyRecord(record);
            if (!record.revision) legacy = await readLegacy(factory);
            inboxJson = JSON.stringify(inboxSnapshot(record, campaigns));
            const result = { ok: true, inbox: JSON.parse(inboxJson), profileId: record.profileId, revision: record.revision, source: record.revision ? 'authority' : legacy ? 'legacy-v13' : 'fresh', payload: record.revision ? record.payload : legacy ? legacy.payload : null };
            observe('read_result', { source: result.source, profileId: result.profileId, revision: result.revision });
            client.bootJson = JSON.stringify(result); return result;
          } catch (error) { faulted = true; const result = resultError(error); observe('read_failure', { code: result.code }); client.bootJson = JSON.stringify(result); return result; }
        })();
        return opening;
      },
      async commit(payload, expectedRevision, expectedProfileId, origin = 'normal') {
        observe('save_requested', { profileId: expectedProfileId, revision: expectedRevision });
        if (!record || faulted) { observe('save_failure', { code: 'NOT_READY' }); return resultError(fail('NOT_READY', 'Save storage is not ready; reload to recover')); }
        if (busy) { observe('save_failure', { code: 'SAVE_BUSY' }); return resultError(fail('SAVE_BUSY', 'A save is still pending')); }
        busy = true;
        try {
          parsePayload(payload, 15);
          if (expectedRevision !== record.revision || expectedProfileId !== record.profileId) throw fail('REVISION_CONFLICT', 'This tab has an old save revision; reload before continuing');
          if (expectedRevision >= Number.MAX_SAFE_INTEGER) throw fail('REVISION_LIMIT', 'Save revision limit reached; export for recovery');
          const nextRevision = expectedRevision + 1;
          const provenance = record.origin || { source: legacy ? 'legacy-v13' : origin === 'import' ? 'import-v15' : 'fresh', legacyDigest: legacy ? legacy.digest : null, importedAt: Date.now() };
          const now = Date.now();
          const plan = planCampaigns(payload, provenance, record, campaigns, nextRevision, now);
          const previous = record.revision ? { ...record, previous: null } : null;
          const candidate = { ...record, format: 2, revision: nextRevision, updatedAt: now, payload: plan.payload, origin: provenance, previous, campaigns: plan.receipts };
          candidate.digest = await hash(fingerprint(candidate));
          observe('save_validated', { profileId: expectedProfileId, revision: expectedRevision });
          const write = () => transaction(db, 'readwrite', (store, resolve, abort, mark) => {
            readCurrent(store, current => {
              mark('compare_authority'); compareCurrent(current, expectedRevision, expectedProfileId);
              mark('put'); store.put(candidate, ACTIVE); resolve(candidate);
              observe('save_submitted', { profileId: expectedProfileId, revision: nextRevision, stage: 'put', connectionGeneration });
            }, abort, mark);
          });
          let next;
          try { next = await write(); }
          catch (error) {
            // Only a synchronous failure before a transaction exists is replayed.
            // Never retry a get/result/put/abort failure or an unknown write outcome.
            if (error.code !== 'InvalidStateError' || error.storageStage !== 'transaction_create' || error.transactionCreated) throw error;
            await reopenExisting(expectedRevision, expectedProfileId);
            next = await write(); // One retry, preserving the exact pending candidate.
          }
          record = next;
          observe('save_confirmed', { profileId: next.profileId, revision: next.revision });
          inboxJson = JSON.stringify(inboxSnapshot(next, campaigns));
          client.bootJson = JSON.stringify({ ok: true, inbox: JSON.parse(inboxJson), profileId: next.profileId, revision: next.revision, source: 'authority', payload: next.payload });
          return { ok: true, inbox: JSON.parse(inboxJson), profileId: next.profileId, revision: next.revision, durable: true, creditedCoins: plan.credit, campaignAwards: plan.awards, campaignDeferred: plan.deferred };
        } catch (error) {
          if (['REVISION_CONFLICT', 'CORRUPT_AUTHORITY'].includes(error.code)) faulted = true;
          observe('save_failure', { profileId: expectedProfileId, revision: expectedRevision, code: resultError(error).code, stage: error.storageStage || 'save_prepare', connectionGeneration });
          return resultError(error);
        } finally { busy = false; }
      },
      creditForSave(payload) {
        if (!record || faulted || !campaigns) return 0;
        try {
          const origin = record.origin || { source: legacy ? 'legacy-v13' : 'fresh' };
          return planCampaigns(payload, origin, record, campaigns, record.revision + 1, Date.now()).credit;
        } catch (_) { return 0; }
      },
      save(payload, revision, profileId, callback) {
        client.commit(payload, revision, profileId).then(result => callback(JSON.stringify(result)));
      },
      close() { if (db) db.close(); db = null; faulted = true; }
    };
    return client;
  }
  root.LittleLeafAuthorityCodec = Object.freeze({ parsePayload, verifyRecord, fingerprint, hash });
  let retrying = null;
  function retry(callback) {
    // A fresh client reopens storage after a transient boot failure. No saved
    // record is deleted, selected, repaired or committed by this operation.
    if (!retrying) {
      retrying = (async () => {
        const candidate = createClient();
        const result = await candidate.boot();
        if (result.ok) {
          root.__littleLeafVault.close();
          root.__littleLeafVault = candidate;
        } else candidate.close();
        return result;
      })().finally(() => { retrying = null; });
    }
    retrying.then(result => callback(JSON.stringify(result)));
  }
  root.LittleLeafVault = Object.freeze({ DB_NAME, STORE, CAMPAIGNS, createClient, retry });
  root.__littleLeafVault = createClient();
})(globalThis);
