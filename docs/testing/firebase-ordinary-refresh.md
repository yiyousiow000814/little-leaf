# Ordinary refresh ownership

An ordinary refresh previously generated a new writer ID while the same tab's
server lease remained live. This could show the other-device warning immediately
after a successful explicit device switch, without another running device.

The candidate retains an account-scoped sessionStorage runtime ID only for a
reload and only after acquiring its exclusive WebLock. New navigations and
account changes use a fresh ID; an overlapping holder blocks entry. Page exit
and account change close writer authority before releasing the lock. The server
owner and epoch still decide ownership. Existing Save-and-update receipts use a
fresh requester and their original strict one-use handoff. Unsupported WebLocks
retain fresh-ID behavior; they are not qualified for ordinary refresh continuity.

Run `node tests/persistence/firebase_session_refresh.js` for generated takeover/refresh,
overlap, copied/new-tab, account, closed/crashed runtime, competing server owner,
update and unavailable storage/lock cases. The existing boot presentation test
observes runtime wiring and pagehide closure with synthetic SDK/DOM boundaries.
These checks neither sign in a player nor access or rewrite player saves.
Actual browser refresh/duplicate-tab acceptance and exact release qualification
remain separate gates; synthetic results do not establish the cause or repair
of a particular player's live warning.

PR188 owns the separate [frozen manual browser diagnostic](https://github.com/yiyousiow000814/little-leaf/blob/a1c8446947350a0a1da85c47dba19d7ab8ab3819/tests/diagnostics/firebase_refresh_browser.js). It is not included or run as this same-itch candidate's acceptance. Any later browser check needs its own exact source binding, disposable profile and coordinated runtime window.
