/* CrazyGames-only variant. SDK Data is the sole store; no local fallback/migration. */
(function (root) {
  'use strict';
  const KEY = 'little-leaf.cg.profile.v1', PREFS = 'little-leaf.cg.preferences.v1';
  const LIMIT = 1048576, reserve = 1024;
  const codec = root.LittleLeafAuthorityCodec;
  let sdk, opening, record, revisionText, scope, epoch = 0, faulted = false, busy = false;
  let playing = false, loading = false;
  const error = (code, message) => Object.assign(new Error(message), { code });
  const failure = e => ({ ok: false, code: typeof e.code === 'string' ? e.code : 'PLATFORM_STORAGE_ERROR', error: e.message || 'Platform storage could not be opened' });
  function log(event, fields = {}) { try { root.LittleLeafSaveLog?.record(event, { layer: 'vault', ...fields }); } catch (_) {} }
  function bounded(promise, ms) {
    let timer;
    return Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(error('PLATFORM_STORAGE_ERROR', 'Platform loading timed out. Reload to try again.')), ms); })]).finally(() => clearTimeout(timer));
  }
  function capacity(value, preferences) {
    if (new TextEncoder().encode(JSON.stringify({ [KEY]: value, [PREFS]: preferences || '' })).length > LIMIT - reserve)
      throw error('PLATFORM_DATA_LIMIT', 'This café exceeds the platform save limit. The previous save is unchanged.');
  }
  async function currentScope() {
    // A change witness only, never authentication or an account database selector.
    if (!sdk.user.isUserAccountAvailable) return 'account-unavailable';
    const user = await sdk.user.getUser();
    return user ? JSON.stringify([user.__dangerousUserId, user.username]) : 'guest';
  }
  function invalidate() {
    epoch++; faulted = true; root.LittleLeafPlatform.ready = false;
    try { sdk.game.gameplayStop(); } catch (_) {}
    playing = false;
  }
  async function initialise() {
    if (!root.CrazyGames?.SDK) throw error('PLATFORM_STORAGE_ERROR', 'The platform SDK could not load. Reload to try again.');
    sdk = root.CrazyGames.SDK;
    await bounded(sdk.init(), 20000);
    if (!['local', 'crazygames'].includes(sdk.environment)) throw error('PLATFORM_STORAGE_ERROR', 'Open this version on CrazyGames or a local test server.');
    sdk.game.loadingStart(); loading = true;
    sdk.user.addAuthListener(invalidate);
    scope = await currentScope();
  }
  function ready() {
    if (!record || faulted) throw error('NOT_READY', 'Platform progress is paused. Reload before continuing.');
  }
  async function guard(generation) {
    ready();
    if (epoch !== generation || await currentScope() !== scope || faulted) { invalidate(); throw error('PLATFORM_ACCOUNT_CHANGED', 'Your platform account changed. Reload to load its progress.'); }
  }
  const client = {
    storageKind: 'crazygames-data', bootJson: '',
    async boot() {
      if (opening) return opening;
      opening = (async () => {
        log('boot_requested');
        try {
          await initialise();
          const generation = epoch;
          const raw = sdk.data.getItem(KEY);
          if (raw === null) {
            const now = Date.now();
            record = { format: 2, profileId: root.crypto.randomUUID(), revision: 0, createdAt: now, updatedAt: now, payload: null, digest: null, origin: null, previous: null, campaigns: {} };
            revisionText = JSON.stringify(record);
            await guard(generation);
            capacity(revisionText, sdk.data.getItem(PREFS));
            // Data-module acceptance, not an assertion of remote persistence.
            sdk.data.setItem(KEY, revisionText);
          } else {
            if (typeof raw !== 'string') throw error('CORRUPT_AUTHORITY', 'Platform save data is unreadable.');
            try { record = JSON.parse(raw); } catch (_) { throw error('CORRUPT_AUTHORITY', 'Platform save data is damaged.'); }
            await codec.verifyRecord(record);
            revisionText = raw;
            await guard(generation);
          }
          root.LittleLeafPlatform.ready = true;
          const result = { ok: true, source: record.revision ? 'authority' : 'fresh', profileId: record.profileId, revision: record.revision, payload: record.payload };
          log('read_result', result); client.bootJson = JSON.stringify(result); return result;
        } catch (e) {
          invalidate(); const result = failure(e); log('read_failure', { code: result.code }); client.bootJson = JSON.stringify(result); return result;
        }
      })(); return opening;
    },
    creditForSave() { return 0; },
    async commit(payload, expectedRevision, expectedProfileId) {
      if (busy) return failure(error('SAVE_BUSY', 'A platform submission is still pending.'));
      busy = true;
      const generation = epoch;
      try {
        ready(); codec.parsePayload(payload, 15);
        if (expectedProfileId !== record.profileId || expectedRevision !== record.revision) throw error('REVISION_CONFLICT', 'This page has an old save revision. Reload before continuing.');
        if (expectedRevision >= Number.MAX_SAFE_INTEGER) throw error('REVISION_LIMIT', 'Save revision limit reached.');
        const next = { ...record, revision: expectedRevision + 1, payload, updatedAt: Date.now(), previous: null, origin: record.origin || { source: 'fresh', legacyDigest: null, importedAt: Date.now() } };
        next.digest = await codec.hash(codec.fingerprint(next));
        const text = JSON.stringify(next);
        await guard(generation);
        // Synchronous comparison detects a changed SDK cache, not server CAS.
        if (sdk.data.getItem(KEY) !== revisionText) throw error('REVISION_CONFLICT', 'Platform progress changed. Reload before continuing.');
        capacity(text, sdk.data.getItem(PREFS));
        sdk.data.setItem(KEY, text);
        record = next; revisionText = text;
        log('platform_save_accepted', { profileId: next.profileId, revision: next.revision });
        const boot = { ok: true, source: 'authority', profileId: next.profileId, revision: next.revision, payload: next.payload };
        client.bootJson = JSON.stringify(boot);
        return { ok: true, profileId: next.profileId, revision: next.revision, durable: false, platformAccepted: true, cloudConfirmed: false, creditedCoins: 0 };
      } catch (e) {
        if (['REVISION_CONFLICT', 'CORRUPT_AUTHORITY', 'PLATFORM_ACCOUNT_CHANGED'].includes(e.code)) invalidate();
        const result = failure(e); log('save_failure', { code: result.code }); return result;
      } finally { busy = false; }
    },
    save(payload, revision, profileId, callback) { client.commit(payload, revision, profileId).then(result => callback(JSON.stringify(result))); },
    close() { invalidate(); }
  };
  const preferences = {
    bootJson: '', lastError: '',
    async boot() {
      try {
        ready(); await guard(epoch);
        const raw = sdk.data.getItem(PREFS);
        let text = '';
        if (raw !== null) {
          let value; try { value = JSON.parse(raw); } catch (_) { throw error('PLATFORM_STORAGE_ERROR', 'Platform preferences are damaged.'); }
          if (!value || value.format !== 1 || typeof value.text !== 'string' || new TextEncoder().encode(value.text).length > 65536) throw error('PLATFORM_STORAGE_ERROR', 'Platform preferences are unreadable.');
          text = value.text;
        }
        const result = { ok: true, source: raw === null ? 'default' : 'preferences', text };
        preferences.bootJson = JSON.stringify(result); return result;
      } catch (e) { invalidate(); const result = failure(e); preferences.bootJson = JSON.stringify(result); return result; }
    },
    writeText(text) {
      try {
        ready(); if (sdk.data.getItem(KEY) !== revisionText) { invalidate(); throw error('PLATFORM_ACCOUNT_CHANGED', 'Platform progress changed. Reload.'); }
        if (typeof text !== 'string' || new TextEncoder().encode(text).length > 65536) throw error('INVALID_SAVE', 'Preferences are too large.');
        const value = JSON.stringify({ format: 1, text }); capacity(revisionText, value);
        sdk.data.setItem(PREFS, value); preferences.bootJson = JSON.stringify({ ok: true, source: 'preferences', text }); return true;
      } catch (_) { preferences.lastError = 'Platform preferences could not be submitted.'; return false; }
    },
    acceptLoaded() { return true; }
  };
  root.LittleLeafPlatform = {
    ready: false, muteAudio: false, firstGameplayAt: 0, musicReady: false,
    update(active) {
      if (!sdk || faulted) return;
      try {
      this.muteAudio = !!sdk.game.settings.muteAudio;
      if (loading && active) { sdk.game.loadingStop(); loading = false; }
      if (active !== playing) { active ? sdk.game.gameplayStart() : sdk.game.gameplayStop(); playing = active; if (active && !this.firstGameplayAt) this.firstGameplayAt = Date.now(); }
      } catch (_) { invalidate(); }
    }
  };
  root.__littleLeafVault = client; root.__littleLeafPreferences = preferences;
  root.LittleLeafVault = Object.freeze({ retry() { root.location.reload(); } });
})(globalThis);
