# Client Catalog and Native Experience Specification

## Read path

The app composes `PublicCloudKitCatalogStore`, `SwiftDataLocalCatalogStore`, and `URLSessionImageRepository` once through `AppDependencies`. `CatalogCoordinator` resolves requested records in the fixed memory → local → public order, coalesces concurrent loads, retains successful documents locally, and maps offline/empty/stale/incompatible results to explicit root states. It never constructs an upstream provider client.

The public store accepts deterministic record identifiers, bridges `CKRecord` values through the versioned codecs, validates hashes and projected fields, maps CloudKit network/throttle/not-found errors, and exposes only `fetch`. Feature code cannot save or delete a catalog record. Image loading has a separate memory dictionary plus configured `URLCache`; a URL's in-flight task is shared by concurrent consumers, and the caller chooses small artwork for grids or large artwork for the static viewer.

## Root and launcher

`CatalogViewModel` is the main-actor presentation adapter. It requests the manifest plus the configured first range, maps valid creature payloads into immutable domain profiles, and keeps the state machine finite: loading, ready, stale, empty-install, offline, or incompatible-schema. The launcher uses a lazy adaptive grid (two phone columns, three at large widths), stable index ordering, neutral placeholder artwork, an appearance `AppStorage` preference (`dark`, `light`, `system`), and an opt-in preview launch environment for deterministic UI tests.

Image loading remains strictly demand-driven: lazy grids request only visible creature artwork and small card images, while a large card image is requested only after its viewer opens. Every successfully fetched image is written atomically to `Library/Application Support/BattleCardDex/ImageCache` under a SHA-256 URL key and excluded from device backup. This store has no age or size eviction policy, so the offline collection accumulates across launches; the separate 32 MB memory tier may evict freely without deleting durable files. As with any app-owned data, uninstalling the app or explicitly clearing its container removes the collection.

Search and filters remain local to the loaded summaries. Name matching is case/diacritic-insensitive, numeric queries match national index, and generation/type predicates combine with clear/reset. Surprise Me preserves the filtered set and changes order using a 480 ms animation. Every tile has a combined VoiceOver label and a minimum-size button-equivalent path.

## Detail and panels

The detail surface is a static, accessible composition with metadata, core data, Field Guide, Evolution, and Related Cards actions. The gesture constants are centralized: carousel travel is damped to 82%, scale reduces by at most 6%, commit is 22%, fast flicks use 280 ms/34 pt, panels open at 22% and close at 12%, and standard settling is 420–460 ms. Native sheets provide the progressive scrim/material treatment for encyclopedia, evolution, and cards. Related cards are relationship-filtered and card detail intentionally excludes price, favorites, collection controls, tilt, glare, and foil simulation.

Detail navigation uses the same pure `CarouselInteractionModel` as the test harness, with previous/next controls and an accessibility-adjustable action as gesture equivalents. Evolution panels render the normalized tree (including members outside the primary range) rather than inferring neighbors from numeric IDs. Grid artwork is requested through `ImageRepository`; card grids use `smallImageURL`, while the static viewer requests `largeImageURL` only when presented. Missing or cancelled image loads remain in a deterministic, fixed-size placeholder.

`BATTLE_CARD_DEX_USE_PREVIEW=1` uses six deterministic summaries for snapshot/UI-flow verification without CloudKit. Live Development reads remain opt-in through the existing CloudKit probe tests.

## Verification status

The current source compiles for a generic iPhoneOS device in Debug and Release configurations, and `build-for-testing` compiles both the unit-test and UI-test bundles. The loader package tests and terminology gate pass. Simulator execution is still an environment dependency: on the current host, CoreSimulatorService is unavailable, so UI snapshots and runtime UI tests have not been claimed as executed.

The first-30 Development catalog is seeded: 30 creatures, 12 evolution chains, and 1,040 related cards. The unchanged rerun skipped all 1,082 data records and wrote zero. On September 6, 2026, a signed Debug build on a connected iPad decoded the Development manifest and loaded all 31 primary plus 1,052 related records with zero misses on cold and warm launches. A payload-validation defect that treated provider/CDN URLs as visible prose was fixed by allowing only explicitly named HTTPS `*URL` transport fields; user-visible content remains sanitized. Signed-out public-read and client-write-denial probes remain pending. No application code contains loader credentials or mutation APIs.
