# Verification Status

Updated September 6, 2026 (initial-build continuation).

## Green checks

- `Loader/`: `swift test` passes all 24 tests, including the Development catalog-query/relationship validator and paginated-query request coverage.
- The loader has a production `URLSession` transport, a persistent gitignored provider-response cache, and a Development-only CloudKit Web Services adapter. Tests cover signed request composition, hash lookup, force-replace batches, partial failures, cache isolation, and structural rejection of Production writes.
- The Development schema audit found all four catalog record types and all 32 required indexes. The first-30 seed published 30 creatures, 12 evolution chains, and 1,040 cards. An unchanged rerun skipped all 1,082 data records and wrote zero.
- The client read path now uses `catalog-manifest-v1`, matching the seeded Development loader manifest; deterministic integration coverage exercises 30 creatures, 12 evolution chains, 1,040 cards, filtering, associations, and incremental warm refresh.
- `python3 Scripts/terminology_compliance.py all --root .` passes.
- `git diff --check` passes.
- Generic iPhoneOS Debug `build-for-testing` succeeds for the app, unit-test bundle, and UI-test bundle.
- Generic iPhoneOS Release build succeeds; the resulting app passes the complete source/product terminology scan and contains no Loader, Plan, or Design Mockup path.
- Script-level terminology tests pass all 6 tests; `git diff --check` passes.
- A preview UI run passed on iPhone 17 Pro, iOS 26.5: requested launcher/search/detail-flow and launch tests had 0 failures and 0 skips. Result: `/tmp/BattleCardDex-UIPhone/Logs/Test/Test-Battle Card Dex-2026.09.05_22-15-43--0400.xcresult`.
- A signed Debug build and direct Development CloudKit probe ran on the connected iPad Air 11-inch (M3), iPadOS 26.5.2. The probe decoded `CatalogManifest/catalog-manifest-v1` at revision `1788660092`. After fixing persisted-payload URL validation, a cold app launch loaded 31 primary and 1,052 related records with zero misses; a warm launch returned the same ready counts.
- The full `BattleCardDexTests` target passed 55 tests on that connected iPad, including transport-URL sanitization regression coverage. Result: `/tmp/BattleCardDex-iPad-UnitTests/Logs/Test/Test-Battle Card Dex-2026.09.06_08-40-53--0400.xcresult`.

## Environment-dependent gates

- CoreSimulatorService recovered sufficiently to boot an iPhone 17 Pro (iOS 26.5) and execute the limited preview UI run above. The comprehensive snapshot, iPad, orientation, appearance, Dynamic Type, contrast, Reduce Transparency, VoiceOver-action, and panel-gesture matrices have not been executed. A later Dynamic Type/carousel rerun exposed two testable issues, both were fixed, but the post-fix rerun was stopped and is not claimed as passing.
- A signed-in physical-device public read now passes. A signed-out physical-device read and client-write-denial probe remain pending. Development authenticated Create/Write permission is currently intentionally enabled for the four catalog types to support later loader runs; `_world` remains read-only.
- Production deployment, legal review, App Store metadata, and final distribution installation remain intentionally pending.

## Reverification commands

From the repository root:

```sh
python3 Scripts/terminology_compliance.py all --root .
git diff --check
cd Loader && swift test
```

Use the documented Xcode build commands from `Documentation/build-configuration-and-compliance.md` when the simulator service or a physical Development device is available.
