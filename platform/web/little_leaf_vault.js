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
  const HOLD = 'little_leaf.layout_hold.v1';
  const STORAGE = 'little_leaf.storage.v1';
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
    if (!data || typeof data !== 'object' || Array.isArray(data) || data.schema !== SCHEMA || (data.version !== version && !(version === 15 && [16, 17].includes(data.version))) || data.new_reconstruction !== true || data.checkout_format !== CHECKOUT) throw fail('INVALID_SAVE', 'Unsupported save format');
    if (version === 15 && data.layout_motion_format !== MOTION) throw fail('INVALID_SAVE', 'Missing layout movement format');
    if (version === 13 && Object.hasOwn(data, 'layout_motion_format')) throw fail('INVALID_SAVE', 'Legacy save has a foreign movement format');
    // v16 remains in this profile/authority. Older clients reject its version;
    // neither import nor an award may downgrade or strip its suspended work.
    const runtime = data.runtime, service = runtime && runtime.service;
    const hasHold = Object.hasOwn(data, 'layout_hold_format') || (runtime && Object.hasOwn(runtime, 'layout_hold_format')) || (service && Object.hasOwn(service, 'layout_hold'));
    if (data.version === 16 || (data.version === 17 && hasHold)) {
      const hold = service && service.layout_hold;
      if (data.layout_hold_format !== HOLD || !runtime || runtime.layout_hold_format !== HOLD || !hold || hold.format !== HOLD || Object.keys(hold).sort().join(',') !== 'dishes,floor,format,guests,hosts,staff') throw fail('INVALID_SAVE', 'Missing layout hold format');
      for (const [key, limit] of [['hosts', 512], ['guests', 60], ['staff', 64], ['dishes', 512], ['floor', 512]])
        if (!Array.isArray(hold[key]) || hold[key].length > limit) throw fail('INVALID_SAVE', 'Invalid layout hold bounds');
    } else if (Object.hasOwn(data, 'layout_hold_format') || (runtime && Object.hasOwn(runtime, 'layout_hold_format')) || (service && Object.hasOwn(service, 'layout_hold')))
      throw fail('INVALID_SAVE', 'Legacy save has foreign layout hold state');
    validateStorage(data);
    return data;
  }
  // Storage is part of the one save payload, never a second stock balance.
  // Validate one canonical union of placed and stored furniture.
  const OWNED_KINDS = ['table','chair','bench','stove','beverage','sink','counter','bin','register','plant','lamp','bookshelf','rug','divider'];
  const DINING_COSTS = {oak_single:[140,280],cottage_single:[420],retro_single:[1200],refined_single:[3600],legacy_bench:[175]};
  const integer = (value, min, max) => Number.isSafeInteger(value) && value >= min && value <= max;
  function validateStorage(data) {
    if (data.version !== 17) {
      if (Object.hasOwn(data, 'storage') || Object.hasOwn(data, 'storage_format')
        || (Array.isArray(data.items) && data.items.some(item => item && Object.hasOwn(item, 'paid_cost'))))
        throw fail('INVALID_SAVE', 'Legacy save has foreign Storage state');
      return;
    }
    const storage = data.storage;
    if (data.storage_format !== STORAGE || !storage || Object.keys(storage).sort().join(',') !== 'dining_sets,items'
      || !Array.isArray(data.items) || !Array.isArray(data.dining_sets) || !Array.isArray(storage.items) || !Array.isArray(storage.dining_sets))
      throw fail('INVALID_SAVE', 'Missing Storage contract');
    const owned = new Map(); let registers = 0, highest = 0;
    for (const [items, stored] of [[data.items, false], [storage.items, true]]) {
      for (const item of items) {
        if (!item || typeof item !== 'object' || Array.isArray(item) || !integer(item.id, 1, 1000000000)
          || !OWNED_KINDS.includes(item.kind) || !integer(item.x, 0, 17) || !integer(item.z, 0, 17) || !integer(item.rot, 0, 3)
          || owned.has(item.id) || (Object.hasOwn(item, 'paid_cost') && !integer(item.paid_cost, 0, 1000000000))
          || (stored && Object.keys(item).sort().join(',') !== (Object.hasOwn(item, 'paid_cost') ? 'id,kind,paid_cost,rot,x,z' : 'id,kind,rot,x,z')))
          throw fail('INVALID_SAVE', 'Invalid or duplicated owned furniture');
        owned.set(item.id, item); highest = Math.max(highest, item.id);
        if (item.kind === 'register') registers++;
      }
    }
    if (registers > 1) throw fail('INVALID_SAVE', 'Duplicate owned register');
    const hosts = data.runtime?.service?.layout_hold?.hosts || [], held = new Set();
    for (const host of hosts) {
      if (!host || !integer(host.id, 1, 1000000000) || held.has(host.id) || !OWNED_KINDS.includes(host.kind)
        || (owned.has(host.id) && owned.get(host.id).kind !== host.kind)) throw fail('INVALID_SAVE', 'Invalid held furniture identity');
      held.add(host.id); highest = Math.max(highest, host.id);
    }
    if (!integer(data.next_item_id, highest + 1, 1000000001)) throw fail('INVALID_SAVE', 'Invalid owned furniture sequence');
    for (const [items, groups] of [[data.items, data.dining_sets], [storage.items, storage.dining_sets]]) {
      const byId = new Map(items.map(item => [item.id, item])), grouped = new Set(), directions = [[0,1],[-1,0],[0,-1],[1,0]];
      for (const group of groups) {
        const table = byId.get(group?.table_id), seat = byId.get(group?.seat_id), costs = DINING_COSTS[group?.variant];
        if (!group || Object.keys(group).sort().join(',') !== 'id,paid_cost,rot,seat_id,table_id,variant'
          || group.id !== group.table_id || group.table_id === group.seat_id || !integer(group.rot, 0, 3)
          || !table || !seat || table.kind !== 'table' || seat.kind !== (group.variant === 'legacy_bench' ? 'bench' : 'chair')
          || grouped.has(table.id) || grouped.has(seat.id) || !costs || !costs.includes(group.paid_cost)
          || seat.x - table.x !== directions[group.rot][0] || seat.z - table.z !== directions[group.rot][1])
          throw fail('INVALID_SAVE', 'Invalid stored dining set');
        grouped.add(table.id); grouped.add(seat.id);
      }
    }
  }
  function storageFingerprint(data) {
    const storage = data.storage || {items:[], dining_sets:[]};
    const items = storage.items.map(item => {
      const value = {id:item.id, kind:item.kind, x:item.x, z:item.z, rot:item.rot};
      if (Object.hasOwn(item, 'paid_cost')) value.paid_cost = item.paid_cost;
      return value;
    }).sort((a,b) => a.id-b.id);
    const dining_sets = storage.dining_sets.map(group => ({id:group.id, table_id:group.table_id, seat_id:group.seat_id,
      variant:group.variant, rot:group.rot, paid_cost:group.paid_cost})).sort((a,b) => a.id-b.id);
    return JSON.stringify({items,dining_sets});
  }
  function fingerprint(record) {
    const value = { format: record.format, profileId: record.profileId, revision: record.revision, createdAt: record.createdAt, updatedAt: record.updatedAt, origin: record.origin, payload: record.payload };
    if (record.format >= 2) value.campaigns = record.campaigns;
    if (record.format === 3) value.mailState = record.mailState;
    return JSON.stringify(value);
  }
  function validRecord(record) {
    if (!record || ![1, 2, 3].includes(record.format) || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(record.profileId) || !Number.isSafeInteger(record.revision) || record.revision < 0 || !Number.isFinite(record.createdAt) || !Number.isFinite(record.updatedAt)) throw fail('CORRUPT_AUTHORITY', 'Authoritative save identity is damaged; recovery is required');
    validReceipts(record);
    if (record.format === 3) {
      const state = record.mailState;
      if (!state || state.schema !== 1 || !Number.isSafeInteger(state.claimSequence) || state.claimSequence < 1
        || !Number.isSafeInteger(state.stockRevision) || state.stockRevision < 0
        || Object.keys(state).sort().join(',') !== 'claimSequence,schema,stockRevision') throw fail('CORRUPT_AUTHORITY', 'Mail save watermark is damaged');
    } else if (Object.hasOwn(record, 'mailState')) throw fail('CORRUPT_AUTHORITY', 'Unexpected mail save watermark');
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
  // A bounded, immutable pre-grid archive in the same authority's own store.
  // Payload strings are retained verbatim; hashes never use parsed/re-encoded saves.
  const GRID = 'little_leaf.grid_building.v1', CENTERED_GRID = 'little_leaf.grid_building.v2', ARCHIVE = 'little-leaf.pre-grid.v1';
  const MAX_PRE_GRID_ARCHIVES = 8;
  function buildingPayload(text, version = 15) {
    const data = parsePayload(text, version);
    const generation = data.wall_format === 3 && data.building_format === GRID ? 1
      : data.wall_format === 4 && data.building_format === CENTERED_GRID ? 2 : 0;
    const modern = data.wall_format === 3 || data.wall_format === 4 || Object.hasOwn(data, 'building_format');
    if (Object.hasOwn(data, 'wall_format') && ![1, 2, 3, 4].includes(data.wall_format))
      throw fail('INVALID_SAVE', 'Unsupported building save format');
    if (modern && (version !== 15 || !generation || data.wall_attachment_format !== 2 || data.starter_geometry_version !== 1 || typeof data.register_unplaced !== 'boolean' || !Array.isArray(data.built_walls) || !Array.isArray(data.wall_attachments) || (!data.floor_finishes || typeof data.floor_finishes !== 'object' || Array.isArray(data.floor_finishes))))
      throw fail('INVALID_SAVE', 'Unified building save contract is incomplete');
    return { data, modern, generation };
  }
  async function preGridArchive(source, nextPayload, legacy = null, recordText = JSON.stringify(source)) {
    const target = buildingPayload(nextPayload);
    await verifyRecord(source);
    if (!target.modern || (!source.revision && !legacy)) return null;
    const payload = source.revision ? source.payload : legacy.payload;
    const version = source.revision ? 15 : 13;
    // Every forward building-format transition retains its exact source, including v1 to centered v2.
    if (buildingPayload(payload, version).generation >= target.generation) return null;
    if (JSON.stringify(JSON.parse(recordText)) !== JSON.stringify(source)) throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Original save identity changed');
    const payloadDigest = await hash(payload);
    if (legacy && (!source.revision && legacy.digest !== payloadDigest)) throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Legacy save checksum changed');
    const body = { format: ARCHIVE, profileId: source.profileId, revision: source.revision, digest: source.digest,
      legacyDigest: source.revision ? null : payloadDigest, recordText, payload, payloadDigest };
    return { ...body, archiveDigest: await hash(JSON.stringify(body)) };
  }
  async function verifyPreGridArchives(text) {
    if (text === null) return [];
    let list;
    try { list = JSON.parse(text); } catch (_) { throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Original building archive is unreadable'); }
    if (!Array.isArray(list) || !list.length || list.length > MAX_PRE_GRID_ARCHIVES) throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Original building archive is damaged');
    const ids = new Set();
    for (const archive of list) {
      const { archiveDigest, ...body } = archive || {};
      if (body.format !== ARCHIVE || Object.keys(body).join(',') !== 'format,profileId,revision,digest,legacyDigest,recordText,payload,payloadDigest'
        || typeof body.payload !== 'string' || body.payloadDigest !== await hash(body.payload) || archiveDigest !== await hash(JSON.stringify(body)))
        throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Original building archive checksum failed');
      const source = JSON.parse(body.recordText); await verifyRecord(source);
      if (source.profileId !== body.profileId || source.revision !== body.revision || source.digest !== body.digest
        || (source.revision ? source.payload !== body.payload || body.legacyDigest !== null : body.legacyDigest !== body.payloadDigest))
        throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Original building archive identity failed');
      buildingPayload(body.payload, source.revision ? 15 : 13);
      const id = JSON.stringify([body.profileId, body.revision, body.digest, body.legacyDigest]);
      if (ids.has(id)) throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'Original building archive has duplicate identities');
      ids.add(id);
    }
    return list;
  }
  async function ensurePreGridArchive(storage, source, nextPayload, guard, legacy = null, recordText = JSON.stringify(source)) {
    const archive = await preGridArchive(source, nextPayload, legacy, recordText);
    await guard(); if (!archive) return null;
    const before = await storage.read(); await guard();
    const list = await verifyPreGridArchives(before); await guard();
    const found = list.find(a => a.profileId === archive.profileId && a.revision === archive.revision && a.digest === archive.digest && a.legacyDigest === archive.legacyDigest);
    if (found && JSON.stringify(found) !== JSON.stringify(archive)) throw fail('PRE_GRID_ARCHIVE_DAMAGED', 'A different original archive already exists');
    if (!found && list.length >= MAX_PRE_GRID_ARCHIVES) throw fail('PRE_GRID_ARCHIVE_FULL', 'Original save archive is full; earlier copies will not be replaced');
    const text = found ? before : JSON.stringify([...list, archive]);
    // install checks the original authority and archive CAS in one transaction.
    await storage.install(before, text); await guard();
    // A separate read after transaction completion is the required proof.
    const readback = await storage.read(); await guard();
    if (readback !== text) throw fail('PRE_GRID_ARCHIVE_UNVERIFIED', 'Original save archive could not be verified; progress was not replaced');
    await verifyPreGridArchives(readback); await guard();
    return Object.freeze({ text });
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
          const archiveKey = 'pre-grid-v1/' + record.profileId;
          const archiveGuard = () => { if (faulted || !db) throw fail('NOT_READY', 'Save storage closed during migration'); };
          const proof = await ensurePreGridArchive({
            read: () => transaction(db, 'readonly', (store, resolve) => { const request = store.get(archiveKey); request.onsuccess = () => resolve(request.result ?? null); }),
            install: (before, text) => transaction(db, 'readwrite', (store, resolve, abort, mark) => {
              readCurrent(store, current => {
                try { archiveGuard(); compareCurrent(current, expectedRevision, expectedProfileId); } catch (error) { abort(error); return; }
                const request = store.get(archiveKey);
                request.onsuccess = () => { try {
                  archiveGuard(); if ((request.result ?? null) !== before) throw fail('REVISION_CONFLICT', 'Original archive changed in another tab');
                  if (before !== text) store.put(text, archiveKey); resolve(text);
                } catch (error) { abort(error); } };
              }, abort, mark);
            })
          }, record, candidate.payload, archiveGuard, legacy);
          const write = () => transaction(db, 'readwrite', (store, resolve, abort, mark) => {
            readCurrent(store, current => {
              const publish = () => { try {
                archiveGuard(); mark('compare_authority'); compareCurrent(current, expectedRevision, expectedProfileId);
                mark('put'); store.put(candidate, ACTIVE); resolve(candidate);
                observe('save_submitted', { profileId: expectedProfileId, revision: nextRevision, stage: 'put', connectionGeneration });
              } catch (error) { abort(error); } };
              if (!proof) { publish(); return; }
              const request = store.get(archiveKey);
              request.onsuccess = () => { if (request.result !== proof.text) abort(fail('PRE_GRID_ARCHIVE_UNVERIFIED', 'Original archive changed before save')); else publish(); };
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
  root.LittleLeafAuthorityCodec = Object.freeze({ parsePayload, buildingPayload, verifyRecord, fingerprint, storageFingerprint, hash, ensurePreGridArchive, verifyPreGridArchives });
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
