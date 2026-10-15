# Ordinary refresh ownership

An ordinary refresh previously generated a new writer ID while the same tab's
server lease remained live. This could show the other-device warning immediately
after a successful explicit device switch, without another running device.

The candidate retains an account-scoped sessionStorage runtime ID only for a
reload and only after acquiring its exclusive WebLock. New navigations and
account changes use a fresh ID; an overlapping holder blocks entry. Exit during
startup and account change close writer authority before releasing the lock.
After successful boot, the document retains its lock so the native pagehide
snapshot can finish its asynchronous, best-effort local save under the existing
guards. The browser releases remaining locks when the document unloads; no
unload listener or timer releases writer identity ahead of a pending save.
A retained document retains the lock. The server owner and epoch still decide
ownership. Existing Save-and-update receipts use a
fresh requester and their original strict one-use handoff. Unsupported WebLocks
retain fresh-ID behavior; they are not qualified for ordinary refresh continuity.

Run `node tests/persistence/firebase_session_refresh.js` for generated takeover/refresh,
overlap, copied/new-tab, account, closed/crashed runtime, competing server owner,
update and unavailable storage/lock cases. The existing boot presentation test
observes startup cancellation, active-pagehide deferred journal completion and
account-change closure using the real client with synthetic SDK/DOM/storage.
These checks neither sign in a player nor access or rewrite player saves.
Ownership startup has its own 15-second network deadline before the journal or
cloud client is created. Timeout, account change or startup page exit closes the
session before releasing the runtime lock and rejects that startup permanently.
Late transaction callbacks cannot install authority, listeners or a client.
An already submitted session write may still commit; timeout never means abort
and starts no replacement takeover. The existing client initial-save-read
deadline remains separate. Recovery choice revalidation also uses that existing
network deadline, retaining both saves and all account/digest/CAS guards.
Actual browser refresh/duplicate-tab/BFCache acceptance and exact release qualification
remain separate gates; synthetic results do not establish the cause or repair
of a particular player's live warning.

PR188 owns the separate [frozen manual browser diagnostic](https://github.com/yiyousiow000814/little-leaf/blob/a1c8446947350a0a1da85c47dba19d7ab8ab3819/tests/diagnostics/firebase_refresh_browser.js). It is not included or run as this same-itch candidate's acceptance. Any later browser check needs its own exact source binding, disposable profile and coordinated runtime window.
