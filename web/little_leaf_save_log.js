/* Session-only save diagnostics. No storage, payloads, raw errors or telemetry. */
(function (root) {
  'use strict';
  const LIMIT = 240;
  const events = [];
  const allowedEvents = new Set(['boot_requested', 'read_result', 'read_accepted', 'read_failure', 'save_requested', 'save_queued', 'save_skipped', 'save_validated', 'save_submitted', 'save_confirmed', 'save_accepted', 'save_failure', 'retry_requested', 'connection_opened', 'connection_closed', 'connection_reopen_requested']);
  const allowedStages = new Set(['boot_open', 'transaction_create', 'object_store', 'get_identity', 'get_active', 'active_result', 'identity_result', 'compare_authority', 'put', 'transaction_complete', 'reopen_existing', 'versionchange', 'forced_close', 'save_prepare']);
  const allowedSources = new Set(['authority', 'legacy-v13', 'fresh', 'native-primary', 'native-import', 'review']);
  const allowedCodes = new Set(['CAMPAIGN_CONFIG', 'CORRUPT_AUTHORITY', 'INVALID_SAVE', 'STORAGE_BLOCKED', 'STORAGE_ABORT', 'LEGACY_UNREADABLE', 'AMBIGUOUS_LEGACY', 'STORAGE_UNAVAILABLE', 'NOT_READY', 'SAVE_BUSY', 'REVISION_CONFLICT', 'REVISION_LIMIT', 'QuotaExceededError', 'SecurityError', 'AbortError', 'UnknownError', 'InvalidStateError', 'VersionError', 'NotFoundError', 'DataError', 'TransactionInactiveError', 'ReadOnlyError', 'ConstraintError', 'STORAGE_ERROR', 'VALIDATION_FAILED', 'STAGING_FAILED', 'INVALID_ACK', 'INVALID_REVISION_ACK', 'INVALID_CREDIT_ACK', 'CREDIT_SYNC_REQUIRED', 'WRITES_SUPPRESSED', 'RECOVERY_BLOCKED', 'NATIVE_SAVE_FAILED', 'BRIDGE_MISSING']);
  let version = 'unknown', sequence = 0, dropped = 0, copyStatus = '', lastRead = null;
  function origin(value) {
    try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) ? url.origin : 'unknown'; } catch (_) { return 'unknown'; }
  }
  function fingerprint(value) {
    if (typeof value !== 'string' || !value || value.length > 128) return '';
    let hash = 2166136261;
    for (const byte of new TextEncoder().encode(value)) hash = Math.imul(hash ^ byte, 16777619) >>> 0;
    return hash.toString(16).padStart(8, '0');
  }
  function context() {
    const value = { origin: 'unknown', frame: 'unknown', referrerOrigin: 'unknown', browser: 'unknown' };
    try { value.origin = origin(root.location.href); } catch (_) {}
    try { value.frame = root.top === root ? 'top-level' : 'embedded'; } catch (_) {}
    try { value.referrerOrigin = origin(root.document.referrer); } catch (_) {}
    try {
      const ua = root.navigator.userAgent;
      for (const [name, pattern] of [['Edge', /Edg(?:e|A|iOS)?\/([0-9.]{1,20})/], ['Firefox', /(?:Firefox|FxiOS)\/([0-9.]{1,20})/], ['Chrome', /(?:Chrome|CriOS)\/([0-9.]{1,20})/], ['Safari', /Version\/([0-9.]{1,20}).*Safari/]]) {
        const match = pattern.exec(ua); if (match) { value.browser = name + ' ' + match[1]; break; }
      }
    } catch (_) {}
    return value;
  }
  const safeContext = context();
  function record(event, fields = {}) {
    // Reject unknown fields and raw messages rather than attempting redaction.
    try {
      if (!allowedEvents.has(event)) return;
      const entry = { sequence: ++sequence, timestamp: new Date().toISOString(), event };
      if (['vault', 'controller', 'native'].includes(fields.layer)) entry.layer = fields.layer;
      if (allowedSources.has(fields.source)) entry.source = fields.source;
      const profile = fingerprint(fields.profileId); if (profile) entry.profile = profile;
      if (Number.isSafeInteger(fields.revision) && fields.revision >= 0) entry.revision = fields.revision;
      if (typeof fields.code === 'string' && fields.code) entry.code = allowedCodes.has(fields.code) ? fields.code : 'STORAGE_ERROR';
      if (allowedStages.has(fields.stage)) entry.stage = fields.stage;
      if (Number.isSafeInteger(fields.connectionGeneration) && fields.connectionGeneration >= 1) entry.connectionGeneration = fields.connectionGeneration;
      if (event === 'read_result' || event === 'read_accepted') lastRead = entry;
      events.push(Object.freeze(entry));
      if (events.length > LIMIT) { events.shift(); dropped++; }
    } catch (_) { /* Diagnostics must never interfere with save control flow. */ }
  }
  function text() {
    return ['Little Leaf save log | app ' + version, 'Session only. Copy before refreshing or closing this page.', 'Submitted is pending. Confirmed means IndexedDB transaction completed. Accepted means game controller accepted its acknowledgement.', 'origin=' + safeContext.origin + ' | frame=' + safeContext.frame + ' | referrerOrigin=' + safeContext.referrerOrigin + ' | browser=' + safeContext.browser, 'Latest read=' + (lastRead ? JSON.stringify(lastRead) : 'not accepted yet'), 'Events retained=' + events.length + '/' + LIMIT + ' | older events dropped=' + dropped, ...events.map(e => e.timestamp + ' #' + e.sequence + ' ' + e.event + Object.entries(e).filter(([key]) => !['sequence', 'timestamp', 'event'].includes(key)).map(([key, value]) => ' ' + key + '=' + value).join(''))].join('\n');
  }
  function fallbackCopy(value) {
    let area;
    try {
      area = root.document.createElement('textarea'); area.value = value;
      area.setAttribute('readonly', ''); area.style.cssText = 'position:fixed;left:0;top:0;opacity:0;pointer-events:none';
      root.document.body.appendChild(area); area.focus(); area.select(); area.setSelectionRange(0, value.length);
      copyStatus = root.document.execCommand('copy') ? 'copied' : 'unavailable';
    } catch (_) { copyStatus = 'unavailable'; }
    finally { try { if (area) area.remove(); root.document.getElementById('canvas').focus(); } catch (_) {} }
  }
  function copy() {
    const value = text(); copyStatus = 'pending';
    try {
      if (root.navigator.clipboard && root.navigator.clipboard.writeText) {
        root.navigator.clipboard.writeText(value).then(() => { copyStatus = 'copied'; }, () => fallbackCopy(value));
      } else fallbackCopy(value);
    } catch (_) { fallbackCopy(value); }
    return copyStatus;
  }
  root.LittleLeafSaveLog = Object.freeze({
    record, text, copy, snapshot: () => events.map(e => ({ ...e })),
    setVersion(value) { if (typeof value === 'string' && /^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9.-]+)?$/.test(value) && value.length <= 40) version = value; },
    get copyStatus() { return copyStatus; }
  });
})(globalThis);
