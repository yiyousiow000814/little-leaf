# itch Google entry candidate (0.1.10a)

Base: PR113 `f690cb7e0c7d1e04c64dc6a3cf6a8cfbb0b50473`. This is an unpublished shell-only candidate; the parent task owns Draft PR publication.

## Player choice

On `itch.io`, its subdomains, `itch.zone`, and its subdomains, the ordinary Web shell displays a cream/olive entry card on the existing sky background before local vault boot. The account link reads **Play with Google — opens a new tab** and points directly to `https://little-leaf-41e5d.firebaseapp.com/` with `target="_blank" rel="noopener noreferrer"`. It uses ordinary user-initiated browser navigation. The existing itch page remains available.

The visible explanation is: **Sign in on the official account game for cloud saves. Account progress is separate: your existing itch progress does not transfer automatically.** The separate **Continue local play on itch** button uncovers the existing loader and starts the existing vault → preferences → engine chain. Nothing remembers this choice; returning/reloading shows the choice again. Short landscapes can scroll the card. Both controls have at least 44px height and visible keyboard focus.

Other hosts, including Firebase Hosting, keep automatic startup. CrazyGames uses its unchanged separate shell. The entry adds no Firebase SDK, embedded login, storage access, data transfer, automatic navigation, or account initialization to itch. The Firebase staging marker remains usable. Existing embedded vault, preferences, inbox and diagnostic bodies remain unchanged. No game rules, save schemas, security rules, workflows, credentials, release/version metadata, art or audio change.

## Verification

```sh
node tests/itch_entry.js
python -m unittest ci.test_itch_entry
node tests/boot_presentation.js
python tests/test_firebase_build.py
PLAYWRIGHT_MODULE=/path/to/playwright CHROME_BIN=/path/to/chrome node tests/itch_entry_browser.cjs
```

The new Python wrapper is discovered by the existing ordinary Web CI unittest gate. The exact-script synthetic test checks itch hostname boundaries, no entry access to storage/network/account APIs, delayed local boot, startup order, non-itch automatic startup, wording, destination and link attributes. The existing loader suite passes 95 checks; Firebase synthetic staging passes.

The browser test uses a fresh context, a stub engine and intercepted requests for every URL. It loads the exact shell at an offline itch hostname fixture, never a private itch page or real Firebase/Google service. Chrome 151.0.7922.138 passed 1280×800, 390×844 and 568×320 layout/reachability checks, keyboard activation, exact new-tab destination, isolated opener, local startup order, and a sandboxed iframe opening a top-level account fixture. All owned browser resources closed. Baseline/candidate PNGs and `browser.json` are in ignored `evidence/itch-entry/` in the isolated checkout.

On this Windows checkout, existing raw source-byte tests fail because standalone `.js`/`.mjs` files are checked out with CRLF while the `-text` HTML shell retains LF. The raw failures reproduce against the pinned base, including the Firebase harness's import-stripping regex. An evidence-only reader wrapper normalizing CRLF to LF passes legacy byte storage, compensation inbox storage, save-log privacy/observers, web performance lifecycle, CrazyGames storage, and Firebase boot presentation. It changes no tracked source. See `regressions.json` and associated logs. These normalized checks do not substitute for ordinary CI on its native checkout.

## Remaining acceptance

No complete Godot build/export, hosted itch behavior, real Google sign-in, account save continuity, or itch-to-account migration is verified by these shell checks. The actual itch iframe popup policy needs hosted acceptance through an authorized route; the local fixture is evidence of browser semantics only. Fresh ordinary Web CI/export remains required for the final source. Production/release and saves were not touched. This candidate provides a route to the account game and makes no claim that account progress has been migrated.
