# Retained compiled cloud diagnostic eligibility

The pinned a7 export is only a debugging aid for changes that leave every native export input unchanged. It is never release qualification.

Diagnostic8 on d474 passed29 assertions. Once0.1.10a metadata and retained release notes changed, diagnostic9 correctly refused the old native artifact at data/release_notes.json before running a game. This was an expected source-eligibility refusal, not a new runtime failure.

The local successor checks eligibility before downloading/using retained artifacts. Unsupported native/data/project changes produce a bounded ineligible_native_source_changed receipt and skip only this obsolete debugging route. The strict validate_changes and artifact/hash verification remain unchanged for eligible runs. No continue-on-error or false runtime-pass result is used. Fresh complete Web and explicit Firebase Stage gates remain mandatory.

Ordinary PR Web CI has firebase_preview=false; listed Firebase steps are skipped. The Stage Firebase preview workflow supplies firebase_preview=true and must be dispatched for the exact final source before fresh Firebase qualification. Neither workflow deploys production rules or hosting.
