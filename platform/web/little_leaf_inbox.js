/* Presentation-only letter retention and read markers. Never accesses IndexedDB or preferences. */
(function (root) {
  'use strict';
  const PREFIX = 'little-leaf.inbox.read.v1/';
  const DISPLAY_PREFIX = 'little-leaf.inbox.display.v1/';
  const CLOCK_PREFIX = DISPLAY_PREFIX + 'clock/';
  const FUTURE_PREFIX = DISPLAY_PREFIX + 'future/';
  const EXPIRED_PREFIX = DISPLAY_PREFIX + 'expired/';
  const RETENTION_MS = 14 * 86400000;
  const MAX_MARKERS = 2048, MAX_METADATA = 4096, MAX_PROFILES = 16;
  const validProfile = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value);
  function marker(profile, campaign, revision) {
    if (!validProfile(profile) || typeof campaign !== 'string' || !/^[a-z0-9][a-z0-9._-]{0,127}$/.test(campaign) || !Number.isSafeInteger(revision) || revision < 1) return null;
    return PREFIX + profile + '/' + campaign + '/' + revision;
  }
  const displayKey = (prefix, key) => prefix + key.slice(PREFIX.length);
  function createClient(options = {}) {
    const session = new Set(), expired = new Set(), future = new Map(), clocks = new Map(), notes = new Set();
    const storage = () => options.storage === undefined ? root.localStorage : options.storage;
    const warning = 'Letter timing and read status may reset after reload because browser storage is unavailable or full.';
    const warn = () => notes.add(warning);
    function readValue(key) {
      try { return storage().getItem(key); }
      catch (_) { warn(); return null; }
    }
    function readTime(key) {
      const raw = readValue(key), value = Number(raw);
      return raw !== null && raw !== '' && Number.isSafeInteger(value) && value >= 0 ? value : null;
    }
    function readFutureAnchors(keys) {
      const anchors = new Map();
      // Read the original exact-key format without changing it.
      for (const key of keys) {
        const retained = readTime(displayKey(FUTURE_PREFIX, key));
        if (retained !== null) anchors.set(key, retained);
      }
      try {
        const store = storage();
        for (let i = 0; i < store.length; i++) {
          const storedKey = store.key(i) || '';
          if (!storedKey.startsWith(FUTURE_PREFIX)) continue;
          const suffix = storedKey.slice(FUTURE_PREFIX.length), split = suffix.lastIndexOf('/');
          const key = PREFIX + suffix.slice(0, split), stamp = suffix.slice(split + 1), time = Number(stamp);
          if (!keys.has(key) || !/^(0|[1-9][0-9]*)$/.test(stamp) || !Number.isSafeInteger(time) || store.getItem(storedKey) !== '1') continue;
          anchors.set(key, Math.min(anchors.has(key) ? anchors.get(key) : Infinity, time));
        }
      } catch (_) { warn(); }
      return anchors;
    }
    function writeValue(key, value, prefix, limit) {
      const store = storage();
      if (store.getItem(key) === value) return;
      if (store.getItem(key) === null) {
        let count = 0;
        for (let i = 0; i < store.length; i++) if ((store.key(i) || '').startsWith(prefix)) count++;
        if (count >= limit) throw new Error('Presentation metadata limit');
      }
      store.setItem(key, value);
      if (store.getItem(key) !== value) throw new Error('Presentation metadata was not retained');
    }
    function saveMetadata(key, value) {
      try { writeValue(key, String(value), DISPLAY_PREFIX, MAX_METADATA); return true; }
      catch (_) { warn(); return false; }
    }
    function displayTime(profile, persist) {
      let now;
      try { now = options.now === undefined ? Date.now() : options.now(); } catch (_) { now = NaN; }
      if (!Number.isSafeInteger(now) || now < 0) {
        notes.add('The device clock is unavailable; letter timing uses the last known time.');
        now = 0;
      }
      const key = CLOCK_PREFIX + profile, retained = readTime(key);
      now = Math.max(now, clocks.get(profile) || 0, retained || 0);
      if (!clocks.has(profile) && clocks.size >= MAX_PROFILES) clocks.delete(clocks.keys().next().value);
      clocks.set(profile, now);
      // Read on every projection so an old tab cannot reuse its cached clock.
      // Independent expired flags below also survive interleaved clock writes.
      if (persist === true && now !== retained) saveMetadata(key, now);
      return now;
    }
    function isExpired(key) { return expired.has(key) || readValue(displayKey(EXPIRED_PREFIX, key)) === '1'; }
    function expire(key, persist) {
      session.delete(key);
      if (expired.size < MAX_MARKERS) expired.add(key);
      if (persist !== true) return;
      saveMetadata(displayKey(EXPIRED_PREFIX, key), 1);
      // Only the exact expired receipt from the verified input may be pruned.
      // Future anchors and expired flags stay: deleting them could revive mail.
      try {
        const store = storage();
        if (store.getItem(key) !== null) store.removeItem(key);
        if (store.getItem(key) !== null) throw new Error('Read marker was not removed');
      } catch (_) { warn(); }
    }
    return Object.freeze({
      get notice() { return Array.from(notes).join(' '); },
      visibleSnapshotJson(snapshotJson, persist) {
        let snapshot;
        try { snapshot = JSON.parse(snapshotJson); } catch (_) { return '{"ok":false,"paid":[],"deferred":[]}'; }
        // This API accepts only the vault's verified projection; it is not a
        // receipt verifier. Reject malformed input before any metadata writes.
        const seen = new Set();
        if (!snapshot || snapshot.ok !== true || !validProfile(snapshot.profileId) || !Number.isSafeInteger(snapshot.revision) || snapshot.revision < 0 || !Array.isArray(snapshot.paid) || !Array.isArray(snapshot.deferred) || !snapshot.paid.every(receipt => {
          if (!receipt || receipt.status !== 'granted' || !Number.isSafeInteger(receipt.coins) || receipt.coins < 1 || receipt.coins > 1000000000 || !Number.isFinite(receipt.grantedAt) || receipt.grantedAt < 0 || receipt.revision > snapshot.revision) return false;
          const key = marker(snapshot.profileId, receipt.id, receipt.revision);
          if (!key || seen.has(key)) return false;
          seen.add(key);
          return true;
        })) return '{"ok":false,"paid":[],"deferred":[]}';
        const now = displayTime(snapshot.profileId, persist), retainedAnchors = readFutureAnchors(seen), paid = [];
        for (const receipt of snapshot.paid) {
          const key = marker(snapshot.profileId, receipt.id, receipt.revision);
          if (isExpired(key)) { expire(key, persist); continue; }
          const futureKey = displayKey(FUTURE_PREFIX, key), retained = retainedAnchors.has(key) ? retainedAnchors.get(key) : null;
          const anchor = Math.min(retained === null ? Infinity : retained, future.has(key) ? future.get(key) : Infinity);
          let deliveredAt = Math.min(receipt.grantedAt, anchor);
          if (anchor === Infinity && deliveredAt > now) {
            // A future-dated immutable receipt gets a fixed presentation-only
            // first-seen anchor. Never rebase this on later visits or reloads.
            deliveredAt = now;
          }
          if (deliveredAt !== receipt.grantedAt) {
            notes.add('A future-dated letter uses its first visit here for the 14-day stay.');
            let anchored = retained !== null || future.has(key);
            // Distinct timestamp keys are immutable: interleaved first visits
            // cannot replace an earlier anchor with a later tab's clock.
            if (persist === true && deliveredAt !== retained && saveMetadata(futureKey + '/' + deliveredAt, 1)) {
              anchored = true;
              const latest = readFutureAnchors(new Set([key])).get(key);
              if (latest !== undefined) deliveredAt = Math.min(deliveredAt, latest);
            }
            if (future.size < MAX_MARKERS || future.has(key)) { future.set(key, deliveredAt); anchored = true; }
            if (!anchored) {
              // Never keep rebasing an unremembered future receipt each visit.
              notes.add('Timing storage is full; some future-dated letters are hidden.');
              continue;
            }
          }
          if (now - deliveredAt >= RETENTION_MS) { expire(key, persist); continue; }
          paid.push({ ...receipt, deliveredAt });
        }
        return JSON.stringify({ ...snapshot, paid, retentionDays: 14, displayNow: now });
      },
      isRead(profile, campaign, revision) {
        const key = marker(profile, campaign, revision);
        if (!key) return false;
        if (session.has(key)) return true;
        const read = readValue(key) === '1';
        if (read && session.size < MAX_MARKERS) session.add(key);
        return read;
      },
      markRead(profile, campaign, revision, persist) {
        const key = marker(profile, campaign, revision);
        if (!key || isExpired(key)) return false;
        // Reviews and suppressed writes clear only their current-session dot.
        if (session.size >= MAX_MARKERS && !session.has(key)) { warn(); return false; }
        session.add(key);
        if (persist !== true) return true;
        try {
          // Independent acknowledgements avoid stale-tab map writes.
          writeValue(key, '1', PREFIX, MAX_MARKERS);
          return true;
        } catch (_) { warn(); return true; }
      }
    });
  }
  root.LittleLeafInbox = Object.freeze({ PREFIX, DISPLAY_PREFIX, CLOCK_PREFIX, FUTURE_PREFIX, EXPIRED_PREFIX, RETENTION_MS, MAX_MARKERS, MAX_METADATA, MAX_PROFILES, createClient });
  root.__littleLeafInbox = createClient();
})(globalThis);
