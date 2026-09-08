# Battle Card Dex — Initial-Build Acceptance Report

**Updated:** September 5, 2026

## Result

The implementation is buildable and has received a limited simulator UI pass, but the initial build is **not accepted as a complete Task 28 vertical slice**. This report records only evidence actually obtained during this continuation; unchecked plan items remain unchecked.

## Completed continuation work

- The app read path now requests `catalog-manifest-v1`, which matches the seeded Development manifest. It batches public record reads with explicit desired keys, renders warm local data before refresh, and fetches changed records after a manifest comparison.
- Deterministic client coverage models the published first-30 catalog: 30 creature records, 12 evolution chains, and 1,040 cards, including filtering, related-card association, and warm incremental refresh.
- The launcher preserves scroll position and VoiceOver focus after detail dismissal. Surprise Me now always changes a multi-entry filtered order. Detail prefetch is restricted to adjacent artwork.
- The carousel has visible controls and accessibility-adjustable actions, settles when backgrounded, and observes Reduce Motion. Evolution selection dismisses its panel; the card viewer has an entrance transition and returns focus to its originating card.
- The public-catalog documentation now reflects the authoritative Development role: `_icloud` Create/Write is intentionally enabled for the four Development catalog record types. It was not changed.

## Executed verification

| Check | Result |
| --- | --- |
| `cd Loader && swift test` | Passed: 24 tests, 0 failures. |
| `python3 -m unittest discover -s Scripts -p 'test_*.py' -v` | Passed: 6 tests, 0 failures. |
| `python3 Scripts/terminology_compliance.py all --root .` | Passed. |
| `git diff --check` | Passed. |
| Debug generic-iPhoneOS `build-for-testing` | Passed; app, unit-test bundle, and UI-test bundle compiled. |
| Release generic-iPhoneOS build | Passed. |
| Release app source/product terminology scan | Passed. |
| Release bundle path check | No Loader, Plan, or Design Mockup path found. |
| Preview UI: launcher/search/detail flow and launch on iPhone 17 Pro (iOS 26.5) | Passed: 2 requested tests, 0 failures, 0 skips. Result: `/tmp/BattleCardDex-UIPhone/Logs/Test/Test-Battle Card Dex-2026.09.05_22-15-43--0400.xcresult`. |

## Evidence limits and remaining gates

- Task 14 remains open: the live Development `validate` invocation, actual query-count comparison, relationship proof against live records, and measured footprint report were intentionally not completed in this continuation after the catalog was confirmed seeded and the work was redirected to the app UI.
- The signed Development public-read probe was not run. The authenticated client mutation-denial probe cannot pass while the intentionally enabled Development `_icloud` Create/Write role remains in effect.
- The post-fix Dynamic Type/carousel UI rerun was stopped; do not treat it as passed. No iPad, orientation, appearance, screenshot, contrast, Reduce Transparency, VoiceOver-action, panel-gesture, 60 Hz/ProMotion, cold/warm/offline real-catalog, or live error-flow matrix is claimed.
- Task 19 custom-font evidence is blocked: the workspace contains no approved Sora, Hanken Grotesk, or Space Grotesk font files, license/provenance notices, or `UIAppFonts` registration. No fonts were downloaded or copied.
- The current feature flow does not independently exercise the public-store indexed-query/cursor path, even though deterministic fake-store coverage exists.
- Production deployment, Production mutation, Tasks 29–32, and every Future Backlog item were untouched.
