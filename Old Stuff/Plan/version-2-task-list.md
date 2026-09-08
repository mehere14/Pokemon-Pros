# Battle Card Dex — Version 2 Sequential Task List

**Status:** Draft for review  
**Updated:** September 4, 2026  
**Companion plan:** `Plan/version-2-plan.md`

**Progress notation:** `[ ]` means pending and `[x]` means implemented and verified. Agents must update this file in place, preserve completed marks, and check an exit criterion only after every Work and Tests item in that task is complete.

## Execution Rules

- [ ] Execute tasks in numeric order. A task may begin only after every dependency and exit criterion is satisfied.
- [ ] Keep each task in its own focused change set. Do not mix later features into foundational tasks.
- [ ] Preserve unrelated user changes and inspect the working tree before every task.
- [ ] Tests named under a task are part of that task, not optional follow-up work.
- [ ] Never mutate the Production CloudKit environment during development or automated tests.
- [ ] The initial-build stopping point is Task 28. Items in the Future Backlog are not part of the initial build.
- [ ] Shipping targets, source, metadata, UI strings, bundled resources, logs, analytics, and executable strings must follow the neutral-terminology rule in the companion plan.

## Phase A — Establish a Safe Foundation

### Task 1 — Capture the Baseline and Create Verification Commands

**Depends on:** Nothing.

**Work**

- [ ] Record the current Xcode/Swift versions, deployment targets, supported devices, schemes, signing state, entitlements, bundle IDs, and existing warnings.
- [ ] Add documented, non-interactive commands for building the app, running unit tests, and running UI tests on a named simulator.
- [ ] Record current tracked and untracked files so later agents do not overwrite user-owned material.
- [ ] Confirm the mockup and design document are reference-only and excluded from all app target memberships.

**Tests**

- [ ] Run a clean simulator build of the untouched starter target.
- [ ] Run the starter unit and UI test suites.
- [ ] Inspect the built application bundle and confirm no `Design Mockup/` or `Plan/` files are embedded.

**Exit criterion**

- [ ] Baseline results and exact verification commands are documented; any pre-existing failure is isolated and explained.

### Task 2 — Rename the Shipping Product to Battle Card Dex

**Depends on:** Task 1.

**Work**

- [ ] Rename the Xcode project, app target, unit-test target, UI-test target, schemes, product, executable, source directory, app entry point, and test classes.
- [ ] Set the display name to `Battle Card Dex`.
- [ ] Set the app bundle ID to `com.askcruit.Battle-Card-Dex` and matching neutral IDs for test targets.
- [ ] Rename the CloudKit container reference to `iCloud.com.askcruit.Battle-Card-Dex`.
- [ ] Replace authored UI strings, accessibility labels, logs, symbols, comments, filenames, and asset names with neutral terminology.
- [ ] Do not modify the non-shipping design references except to ensure they have no target membership.

**Tests**

- [ ] Build and launch the renamed app from the renamed shared scheme.
- [ ] Confirm the home-screen/app-process name and bundle metadata say `Battle Card Dex`.
- [ ] Search every shipping source and project-metadata file for the banned franchise token and accented spelling.
- [ ] Run `strings` against the built executable and scan the complete `.app` bundle for the same terms.
- [ ] Confirm the design-reference directories are absent from the archive.

**Exit criterion**

- [ ] The renamed app and both test bundles compile, launch, and pass the shipping terminology scan.

### Task 3 — Add a Permanent Terminology Compliance Gate

**Depends on:** Task 2.

**Work**

- [ ] Add a release-validation script that constructs banned terms from Unicode scalar values so the scanner itself does not contain the literal text.
- [ ] Scan Swift, Objective-C, plist, entitlement, project, scheme, localization, asset, JSON fixture, generated bundle, and executable-string inputs.
- [ ] Exclude only the non-shipping `Plan/` and design-reference directories.
- [ ] Run the gate before archive/release builds and expose it as a standalone verification command.

**Tests**

- [ ] Add a temporary prohibited string in a disposable test fixture and verify the gate fails with its exact file and line.
- [ ] Remove the temporary string and verify the gate passes.
- [ ] Verify both accented and unaccented forms are detected case-insensitively.
- [ ] Verify neutral words containing unrelated partial character sequences do not cause false positives.

**Exit criterion**

- [ ] A failing terminology scan blocks release validation, and the clean renamed project passes.

### Task 4 — Define Build Environments and Central Configuration

**Depends on:** Task 3.

**Work**

- [ ] Add typed `AppConfiguration`, `CloudCatalogConfiguration`, `CacheConfiguration`, `InteractionConstants`, `MotionConstants`, and `DesignConstants` sources.
- [ ] Define Debug, Test, and Release behavior without scattering compiler checks through feature code.
- [ ] Centralize CloudKit container ID, record names, schema version, manifest ID, timeouts, batch sizes, cache budgets, first-seed range, locale, and feature flags.
- [ ] Ensure upstream API hosts and credentials exist only in the separate loader environment, never in the shipping app target.
- [ ] Define a test configuration that uses in-memory stores and fake CloudKit services.

**Tests**

- [ ] Unit-test every environment’s expected configuration values.
- [ ] Inspect the Release app binary and verify loader hosts, API keys, and private-key paths are absent.
- [ ] Verify invalid cache sizes, negative timeouts, and unsupported schema versions fail configuration validation.

**Exit criterion**

- [ ] All static configuration has one typed source of truth and Release contains no loader secrets or upstream endpoints.

### Task 5 — Build the Test Harness and Deterministic Fixtures

**Depends on:** Task 4.

**Work**

- [ ] Create protocol fakes for the public catalog store, local catalog store, image loader, clock, and retry scheduler.
- [ ] Add sanitized deterministic fixtures for creature indexes 1–6, one branching evolution, one no-evolution case, and representative battle cards.
- [ ] Keep raw upstream fixtures outside the shipping app target; normalize and sanitize fixture content before committing it.
- [ ] Add helpers for in-memory SwiftData containers and isolated CloudKit development record namespaces.

**Tests**

- [ ] Verify fixtures decode deterministically and contain no prohibited authored/runtime text.
- [ ] Verify fake services can emit success, empty, stale, offline, throttle, partial-failure, and cancellation states.
- [ ] Verify each test starts with an empty isolated local store and cannot access Production CloudKit.

**Exit criterion**

- [ ] Subsequent data and UI tasks can run deterministically without external network access.

## Phase B — Build the Data Contracts and Storage

### Task 6 — Define Domain Models and Mapping Boundaries

**Depends on:** Task 5.

**Work**

- [ ] Define immutable domain models for `CreatureSummary`, `CreatureProfile`, `CreatureForm`, `CreatureStats`, `MoveSummary`, `MoveDetail`, `Encounter`, `EvolutionChain`, `EvolutionNode`, `EvolutionRequirement`, `BattleCardSummary`, and `BattleCardDetail`.
- [ ] Define loader-only DTOs—Data Transfer Objects—that mirror external JSON, then map them into normalized catalog payloads.
- [ ] Keep DTOs, CloudKit records, SwiftData models, domain models, and view state as separate types.
- [ ] Normalize measurements, optional fields, names, IDs, version groups, types, and evolution conditions.
- [ ] Add a sanitizer that rewrites prohibited generic branding into neutral factual wording or omits unsafe descriptions.

**Tests**

- [ ] Decode sanitized fixtures with missing, null, extra, and unknown fields.
- [ ] Verify DTO-to-catalog and catalog-to-domain mappings.
- [ ] Verify every evolution condition maps correctly, including branching and multiple simultaneous requirements.
- [ ] Verify sanitizer behavior for case, accents, punctuation, and embedded phrases.
- [ ] Verify no raw upstream payload is accepted as a persisted catalog payload.

**Exit criterion**

- [ ] Stable domain contracts exist, mapping tests pass, and prohibited text cannot enter a published payload.

### Task 7 — Implement the Local SwiftData Catalog Mirror

**Depends on:** Task 6.

**Work**

- [ ] Remove the starter `Item` model.
- [ ] Add `CachedCatalogManifest`, `CachedCreature`, `CachedEvolutionChain`, and `CachedCard`.
- [ ] Configure this model container with `cloudKitDatabase: .none`.
- [ ] Add local indexes/uniqueness where safe, stable source-ID upserts, content hashes, schema versions, cache timestamps, and encoded normalized payloads.
- [ ] Implement transactional batch replacement and last-valid-record retention.
- [ ] Provide queries for index ordering, name/number search, generation/type filtering, evolution lookup, and cards related to a creature.

**Tests**

- [ ] Create the model container in memory and on disk.
- [ ] Insert, update, skip unchanged, query, and delete all model types.
- [ ] Verify duplicate source IDs resolve predictably.
- [ ] Simulate a failed batch and confirm previous valid rows remain.
- [ ] Delete the local store and verify it can be recreated empty without migration errors.

**Exit criterion**

- [ ] The device cache is fully usable without CloudKit and all persistence tests pass.

### Task 8 — Define the Public CloudKit Record Schema

**Depends on:** Tasks 6–7.

**Work**

- [ ] Define record codecs for `CatalogManifest`, `CreatureCatalogRecord`, `EvolutionCatalogRecord`, and `CardCatalogRecord`.
- [ ] Use deterministic record names, content hashes, loader timestamps, source timestamps where available, and explicit schema versions.
- [ ] Keep structured payloads below the 1 MB CloudKit record limit.
- [ ] Define required queryable/sortable fields and document the indexes that must be enabled in CloudKit Console.
- [ ] Keep images as source URLs in this phase; do not create `CKAsset` artwork records.

**Tests**

- [ ] Round-trip every record type between normalized models and fake `CKRecord` values.
- [ ] Reject missing required fields, wrong types, unsupported schema versions, oversized payloads, and invalid IDs.
- [ ] Verify deterministic record-name generation for repeated inputs.
- [ ] Verify records and field names use only neutral internal terminology.

**Exit criterion**

- [ ] Record contracts are versioned, size-safe, deterministic, and covered by codec tests.

### Task 9 — Configure the CloudKit Development Container and Security Model

**Depends on:** Task 8.

**Work**

- [ ] Add the neutral iCloud container entitlement and CloudKit capability to the app.
- [ ] Retain the remote-notification background mode if required by the chosen update mechanism.
- [ ] Create record types and indexes in the Development environment.
- [ ] Configure public catalog records as world-readable and writable only by the developer/loader role.
- [ ] Document Development-versus-Production environment selection and prohibit automated Production writes.

**Tests**

- [ ] From a signed development build, read a harmless probe record from the public database.
- [ ] Verify a signed-out device can read the public probe.
- [ ] Verify the production app client cannot create, change, or delete a public catalog record.
- [ ] Verify a test process cannot resolve or mutate the Production environment.

**Exit criterion**

- [ ] Public Development reads work, client writes are denied, and security roles/indexes are documented.

## Phase C — Build the Controlled Catalog Loader

### Task 10 — Scaffold the Loader CLI and Secret Handling

**Depends on:** Tasks 6, 8, and 9.

**Work**

- [ ] Create a separate, non-shipping command-line target or package.
- [ ] Add commands: `seed --range`, `sync --range`, `sync --all`, `validate`, and `dry-run`.
- [ ] Keep the iOS app credential-free: public CloudKit reads use signed entitlements, and the creature-data API requires no key.
- [ ] For local loader runs, read the optional card-source API key, CloudKit server-to-server key ID, and external private-key path from macOS Keychain under a loader-specific service name.
- [ ] Support runtime environment-variable overrides for CI, where values come from the CI platform's encrypted secret store. Permit `.env.local` only as a gitignored, owner-readable local fallback.
- [ ] Keep the CloudKit private signing-key file outside the repository. Never store secrets in source, plist, xcconfig, UserDefaults, SwiftData, CloudKit records, fixtures, logs, checkpoints, reports, or app bundles.
- [ ] Add structured exit codes and machine-readable run reports.

**Tests**

- [ ] Verify each command parses valid arguments and rejects invalid/missing ranges.
- [ ] Verify missing secrets produce a clear preflight error before any network call.
- [ ] Verify local secret retrieval uses Keychain and CI retrieval accepts process-injected values without writing them to disk.
- [ ] Verify `.env` and secret-bearing `.env.*`, private-key, and credential-file patterns are ignored; explicitly allow only a safe `.env.example` containing variable names and placeholders, never values.
- [ ] Verify logs redact injected test secrets.
- [ ] Verify the iOS dependency graph and built app contain no loader module.

**Exit criterion**

- [ ] The loader starts, validates configuration safely, and has no path into the shipping binary.

### Task 11 — Implement Upstream Clients, Pagination, and Rate Limiting

**Depends on:** Task 10.

**Work**

- [ ] Implement loader adapters for creature/species, form, move, encounter, generation/type, evolution, card-search, and card-detail endpoints.
- [ ] Add bounded concurrency per provider, configurable minimum request intervals, pagination, cancellation, timeouts, and response validation.
- [ ] Honor `Retry-After` and provider limit headers where available.
- [ ] Add bounded exponential backoff with jitter for transient failures; never retry permanent validation failures.
- [ ] Coalesce identical requests and deduplicate stable source IDs.

**Tests**

- [ ] Use a stub transport to verify request paths, parameters, headers, and pagination cursors.
- [ ] Simulate 429, timeout, connection loss, 4xx, 5xx, malformed JSON, and partial-page failures.
- [ ] Verify minimum intervals and concurrency ceilings with a deterministic test clock.
- [ ] Verify cancellation stops pending retries.
- [ ] Verify all pages are consumed exactly once and duplicates are removed.

**Exit criterion**

- [ ] The loader can fetch complete normalized source datasets without violating configured limits.

### Task 12 — Implement Catalog Normalization and Referential Validation

**Depends on:** Task 11.

**Work**

- [ ] Join creature, species, form, move, encounter, evolution, and card data by stable source IDs.
- [ ] Complete an evolution chain even when some members fall outside the requested seed range.
- [ ] Relate cards by the provider’s national-index field rather than name matching.
- [ ] Sanitize all stored text and prohibit raw payload persistence.
- [ ] Calculate deterministic content hashes after normalization.
- [ ] Validate required images/URLs, IDs, evolution references, card relationships, schema version, and payload size.

**Tests**

- [ ] Normalize linear, branching, no-evolution, alternate-form, missing-description, and missing-image fixtures.
- [ ] Verify one shared evolution chain is emitted once for multiple requested members.
- [ ] Verify unrelated cards are excluded and multi-creature cards link to every relevant entry.
- [ ] Verify identical semantic input produces the same content hash regardless of source ordering.
- [ ] Verify unsafe text or dangling references block publication.

**Exit criterion**

- [ ] Every normalized catalog batch is deterministic, internally complete, sanitized, and valid before upload.

### Task 13 — Implement Idempotent Public CloudKit Writes

**Depends on:** Task 12.

**Work**

- [ ] Authenticate through CloudKit Web Services with a server-to-server key.
- [ ] Fetch existing hashes and skip unchanged records.
- [ ] Upsert deterministic record IDs in bounded batches.
- [ ] Handle partial batch failures and retry safe individual records.
- [ ] Save a local checkpoint after each committed batch.
- [ ] Publish `CatalogManifest` last and never point clients at a partial catalog version.

**Tests**

- [ ] Use a fake CloudKit service to test create, update, unchanged skip, conflict, throttle, partial failure, and retry exhaustion.
- [ ] Interrupt after a committed batch, resume, and verify no duplicate upstream fetch or public record.
- [ ] Verify a failed data batch leaves the previous manifest active.
- [ ] Verify the manifest is the final write in every successful run.

**Exit criterion**

- [ ] Loader writes are resumable, idempotent, partial-failure safe, and manifest-gated.

### Task 14 — Seed and Validate Creature Indexes 1–30

**Depends on:** Task 13.

**Work**

- [ ] Run the loader in Development with `seed --range 1...30`.
- [ ] Publish 30 complete creature profiles.
- [ ] Publish every unique complete evolution chain referenced by those entries, including required out-of-range family members.
- [ ] Publish all related cards from every API result page.
- [ ] Publish a `testing` manifest with exact counts and supported range.
- [ ] Save the run report and projected public storage/transfer footprint.

**Tests**

- [ ] Run `validate` against the resulting Development catalog.
- [ ] Confirm exactly 30 primary creature entries and no duplicate source IDs.
- [ ] Verify each primary entry resolves its evolution chain and related cards.
- [ ] Compare manifest counts with actual CloudKit query counts.
- [ ] Rerun the unchanged seed and verify all data records are skipped.

**Exit criterion**

- [ ] The first-30 shared catalog is complete, reproducible, validated, and ready for client integration.

## Phase D — Build the Client Data Path

### Task 15 — Implement the Read-Only Public Catalog Client

**Depends on:** Task 14.

**Work**

- [ ] Implement `PublicCatalogStore` over `CKContainer.publicCloudDatabase`.
- [ ] Read the deterministic manifest, fetch records by ID, execute indexed queries, select desired keys, and follow cursors.
- [ ] Map CloudKit failures into typed app errors.
- [ ] Coalesce identical requests and apply bounded transient retries.
- [ ] Expose no mutation interface to application features.

**Tests**

- [ ] Test manifest, record-ID, query, cursor, desired-key, empty, malformed, throttle, offline, cancellation, and partial-result behavior with a fake database.
- [ ] Verify an unsupported catalog schema returns an upgrade-required state.
- [ ] Compile-time test that feature code cannot call save/delete through the store protocol.

**Exit criterion**

- [ ] The app has a tested, read-only, provider-independent public catalog interface.

### Task 16 — Implement the Multi-Level Catalog Coordinator

**Depends on:** Tasks 7 and 15.

**Work**

- [ ] Implement the fixed read order: memory, local SwiftData, public CloudKit.
- [ ] Render valid local data immediately, then compare local/public manifests.
- [ ] Download only missing or changed records and persist successful batches locally.
- [ ] Restrict visible content to the manifest’s supported range.
- [ ] Provide stale-but-usable, refreshing, empty-install, offline, and incompatible-schema states.
- [ ] Ensure Release has no upstream API fallback.

**Tests**

- [ ] Cold install: load from public CloudKit and populate SwiftData.
- [ ] Warm launch: render from SwiftData without waiting for CloudKit.
- [ ] Updated manifest: fetch only records whose hashes changed.
- [ ] Offline warm launch: display local data.
- [ ] Offline empty install: show recoverable service state.
- [ ] Failed refresh: keep last valid local batch.
- [ ] Verify index 31 is unavailable while the test manifest supports only 1–30.

**Exit criterion**

- [ ] Catalog data loads quickly, works offline after first use, refreshes incrementally, and never contacts upstream APIs.

### Task 17 — Implement Image Loading and Device Caching

**Depends on:** Task 16.

**Work**

- [ ] Implement `ImageRepository` with memory caching, configured `URLCache`, request coalescing, cancellation, and small/large image selection.
- [ ] Use small images in grids and large images only for detail/viewer states.
- [ ] Add deterministic placeholders and prevent layout jumps.
- [ ] Keep source images outside public CloudKit assets in the initial build.

**Tests**

- [ ] Verify one network request serves concurrent identical image consumers.
- [ ] Verify cancellation, corrupt data, missing URL, HTTP failure, memory eviction, and disk-cache reuse.
- [ ] Verify grids never request high-resolution card images.
- [ ] Verify cached images display during offline warm launches.

**Exit criterion**

- [ ] Artwork loading is efficient, cancellable, cache-backed, and layout-stable.

## Phase E — Build the Native Experience Incrementally

### Task 18 — Implement the App Shell, Theme, and Root States

**Depends on:** Tasks 4, 5, and 16.

**Work**

- [ ] Replace the starter content with a root feature state machine.
- [ ] Add dark-default, light, and follow-system appearance using `AppStorage`.
- [ ] Add root loading, empty-install, incompatible-schema, CloudKit-unavailable, and retry states using reference styling.
- [ ] Inject dependencies once through `AppDependencies`.

**Tests**

- [ ] Launch with each fake root state and verify the correct screen/action.
- [ ] Verify appearance persists across relaunch and responds to system changes in follow-system mode.
- [ ] Verify retry triggers one catalog refresh and duplicate taps are coalesced.

**Exit criterion**

- [ ] The app launches into deterministic themed states with no starter UI or fatal persistence crash.

### Task 19 — Implement Design Tokens and Reusable Components

**Depends on:** Task 18.

**Work**

- [ ] Implement the complete Electric Burst palette, spacing, radii, typography, shadows, glass materials, inner highlights, chips, buttons, orbital traces, ambient glow, and focus treatment.
- [ ] Bundle Sora, Hanken Grotesk, and Space Grotesk with license notices.
- [ ] Build reusable branded header, icon button, glass tile, gesture pill, type chip, data panel, scrim, panel grip, loading card, and error card.
- [ ] Ensure no design constants are duplicated in feature views.

**Tests**

- [ ] Add component previews for phone/tablet, portrait/landscape, light/dark, large Dynamic Type, increased contrast, and Reduce Transparency.
- [ ] Compare components against cropped mockup references.
- [ ] Verify bundled font names resolve; fail tests if the system-font fallback is used unexpectedly.

**Exit criterion**

- [ ] Reusable components match reference tokens and are ready for feature composition.

### Task 20 — Implement the Launcher Grid

**Depends on:** Tasks 17 and 19.

**Work**

- [ ] Build the launcher header, “Choose Your Battler” copy, lazy grid, creature tiles, region indicator, ambient background, and Surprise Me control.
- [ ] Use two columns on iPhone portrait and three on iPad/landscape.
- [ ] Bind the grid to the manifest-supported creature summaries.
- [ ] Restore accessibility focus and scroll position when returning from detail.

**Tests**

- [ ] Render empty, loading, 6-entry fixture, and 30-entry Development catalog states.
- [ ] Verify stable national-index ordering and lazy image requests.
- [ ] Snapshot phone/tablet portrait and landscape in light/dark.
- [ ] Verify VoiceOver order, labels, and minimum hit targets.

**Exit criterion**

- [ ] The first-30 launcher is responsive, accessible, data-driven, and visually matched.

### Task 21 — Implement Search, Filters, and Surprise Me

**Depends on:** Task 20.

**Work**

- [ ] Make the region indicator open the reference-derived search/filter layer.
- [ ] Add name, national-index, generation, and type filtering with clear/reset.
- [ ] Keep filtering local over the cached manifest range.
- [ ] Implement Surprise Me using the 480 ms rearrangement and rotating sparkle; guarantee a changed visible order when possible.

**Tests**

- [ ] Search exact, prefix, case-insensitive, accented, numeric, empty, and no-result queries.
- [ ] Combine generation and type filters, then clear them.
- [ ] Verify Surprise Me preserves the filtered set and changes order without duplicate entries.
- [ ] Verify Reduce Motion replaces tile travel with a simple state change/fade.

**Exit criterion**

- [ ] Search, filtering, and shuffle work only within published catalog coverage and match the design language.

### Task 22 — Implement Detail Transition and Creature Carousel

**Depends on:** Task 21.

**Work**

- [ ] Implement launcher-to-detail and reverse transitions with the specified 300/420 ms behavior.
- [ ] Build the branded detail header, artwork area, metadata, compact Field Guide panel, controls, and page indicator.
- [ ] Implement interactive horizontal drag with 82% damping, 6% scale reduction, neighbor opacity, 22% threshold, and fast-flick rule.
- [ ] Add 460 ms settling and 220 ms boundary bump.
- [ ] Prefetch adjacent summaries/images without fetching the entire catalog.

**Tests**

- [ ] Test drag immediately below, at, and above 22%.
- [ ] Test flick just below/above 280 ms and 34 points.
- [ ] Verify both boundaries, cancelled drags, rapid reversals, and adjacent prefetch.
- [ ] Verify buttons and VoiceOver adjustable actions produce the same selection state.
- [ ] Snapshot all four device/orientation compositions.

**Exit criterion**

- [ ] Selection, transition, and carousel behavior match the reference and pass threshold tests.

### Task 23 — Implement the Encyclopedia Layer

**Depends on:** Task 22.

**Work**

- [ ] Open the encyclopedia by tapping the compact Field Guide panel.
- [ ] Present all normalized profile sections with lazy containers.
- [ ] Load move details and encounters from the shared/local catalog only when opened.
- [ ] Omit unavailable values cleanly and use neutral factual copy.
- [ ] Add section-level loading/error states without replacing the whole profile.

**Tests**

- [ ] Render complete, partial, no-description, no-encounter, alternate-form, and large-move-list fixtures.
- [ ] Verify lazy sections do not load until requested.
- [ ] Verify one failed section leaves all others usable.
- [ ] Run the terminology compliance scanner over every displayed fixture and screenshot accessibility tree.

**Exit criterion**

- [ ] Encyclopedic data is complete, performant, neutral, and resilient to missing sections.

### Task 24 — Implement the Evolution Swipe-Up Panel

**Depends on:** Task 22.

**Work**

- [ ] Implement interactive upward opening, progressive scrim/scale/blur/brightness, 22% open threshold, and 420 ms settle.
- [ ] Implement panel heights per device/orientation and 12% downward close threshold.
- [ ] Draw connectors over 380 ms after 120 ms; stagger nodes over 330 ms at 70 ms intervals starting at 240 ms; pulse the current node.
- [ ] Support linear, branching, and no-evolution layouts.
- [ ] Selecting a node closes the panel and moves the carousel to that creature, including family members outside the initial primary range when cached for chain completeness.

**Tests**

- [ ] Test opening and closing immediately below/at/above thresholds.
- [ ] Verify linear, branching, multi-condition, and no-evolution fixtures.
- [ ] Verify cancelled/interrupted gestures restore every visual property.
- [ ] Verify node selection, focus restoration, and Reduce Motion alternatives.

**Exit criterion**

- [ ] Evolution data and panel interactions are complete and reference-matched.

### Task 25 — Implement the Related Cards Pull-Down Panel

**Depends on:** Task 22.

**Work**

- [ ] Implement downward interactive opening with the same progressive background treatment and thresholds.
- [ ] Apply reference panel heights, close interactions, card-grid entrance timing, and pagination behavior.
- [ ] Query cards by cached national-index relationships.
- [ ] Display small artwork, name, set, collector number, rarity, type, and HP.
- [ ] Add empty, partial-page, stale, and retry states.

**Tests**

- [ ] Test opening/closing thresholds, scrim close, × close, and gesture cancellation.
- [ ] Verify cards belong to the selected creature and unrelated cards never appear.
- [ ] Verify pagination does not duplicate cards and retains earlier pages on failure.
- [ ] Verify only small images are requested in the grid.
- [ ] Snapshot phone/tablet portrait and landscape panels.

**Exit criterion**

- [ ] Related cards load from the shared catalog and the pull-down behavior matches the mockup.

### Task 26 — Implement the Static Card Viewer and Full Detail

**Depends on:** Task 25.

**Work**

- [ ] Implement the 180 ms backdrop fade and 340 ms card entrance from 24 points below at 0.82 scale.
- [ ] Present static high-resolution artwork without tilt, glare, foil simulation, favorites, or collection controls.
- [ ] Add the full card information layer with normalized available fields.
- [ ] Restore focus to the originating card on every close path.

**Tests**

- [ ] Verify open/close timing, backdrop, ×, accessibility escape, and repeated rapid presentation.
- [ ] Verify high-resolution artwork is requested only after viewer/detail presentation.
- [ ] Render complete and sparse card fixtures without empty labels or broken spacing.
- [ ] Verify price data is neither displayed nor persisted.

**Exit criterion**

- [ ] Static card viewing and details are polished, accessible, and explicitly exclude deferred effects/personal features.

### Task 27 — Complete Responsive Layout and Accessibility

**Depends on:** Tasks 20–26.

**Work**

- [ ] Finalize distinct iPhone portrait, iPhone landscape, iPad portrait, and iPad landscape compositions.
- [ ] Handle safe areas, rotation, multitasking widths, Dynamic Type, VoiceOver, increased contrast, Reduce Motion, Reduce Transparency, and button shapes.
- [ ] Ensure every gesture has a visible and accessibility equivalent.
- [ ] Cancel and settle active gestures safely during rotation/backgrounding.

**Tests**

- [ ] Run UI tests at 390×844, 844×390, 1024×1366, and 1366×1024 in light and dark.
- [ ] Exercise largest supported Dynamic Type sizes and verify content remains reachable.
- [ ] Complete the main flow using VoiceOver-equivalent actions without gestures.
- [ ] Rotate during every interactive gesture and verify stable state afterward.

**Exit criterion**

- [ ] All reference layouts and accessibility modes pass without clipped or unreachable functionality.

## Phase F — Validate, Expand, and Prepare Release

### Task 28 — First-30 End-to-End Acceptance Gate

**Depends on:** Tasks 14–27.

**Work**

- [ ] Run the complete app against the real Development public catalog for indexes 1–30.
- [ ] Capture golden-reference screenshots for all four layouts and both appearances.
- [ ] Profile launch, scrolling, carousel, panels, and card viewer on 60 Hz and ProMotion hardware.
- [ ] Test cold install, warm launch, offline warm launch, failed refresh, and reinstall/reconstruction.
- [ ] Run all unit, integration, UI, accessibility, terminology, bundle-content, and secret scans.

**Tests**

- [ ] Confirm 30 primary entries, complete required evolution families, and all related card pages are reachable.
- [ ] Confirm a clean reinstall rebuilds from public CloudKit without upstream API calls.
- [ ] Confirm an offline warm launch uses SwiftData successfully.
- [ ] Confirm Release has no public write path, upstream host, API key, loader key, prohibited shipping term, Personal Library, or native card-effect code.
- [ ] Confirm no visible dropped frames in the reference interactions.

**Exit criterion**

- [ ] The first-30 build is a shippable-quality vertical slice and every automated/manual gate passes.

### Task 29 — Measure Capacity and Run the Full Catalog Loader

**Depends on:** Task 28.

**Work**

- [ ] Use measured first-30 storage, record counts, transfer, query latency, and loader duration to project full-catalog usage.
- [ ] Obtain explicit approval of the projected CloudKit footprint.
- [ ] Run `dry-run`, then `sync --all` in Development.
- [ ] Resume any interrupted run from checkpoints.
- [ ] Run full referential, size, terminology, and count validation.
- [ ] Mark the Development manifest complete only after validation.

**Tests**

- [ ] Compare projected and actual usage and investigate material variance.
- [ ] Verify deterministic IDs, no duplicate records, complete evolution references, complete card pagination, and all content hashes.
- [ ] Rerun the unchanged full load and verify it performs skips rather than rewrites.
- [ ] Run launcher search/filter and representative details across early, middle, and latest catalog entries.

**Exit criterion**

- [ ] The complete Development catalog is valid, within approved quotas, idempotent, and app-readable.

### Task 30 — Production CloudKit Deployment

**Depends on:** Task 29.

**Work**

- [ ] Freeze and review public record schemas and indexes.
- [ ] Deploy the schema/indexes from Development to Production through CloudKit Console.
- [ ] Run the loader against Production using separately scoped credentials.
- [ ] Validate Production counts, hashes, permissions, and manifest.
- [ ] Enable the full-catalog feature flag only after Production validation succeeds.

**Tests**

- [ ] Run a read-only release candidate against Production.
- [ ] Verify signed-out public reads, local mirror creation, search/filter, representative evolution chains, and related cards.
- [ ] Verify client mutation attempts remain denied.
- [ ] Verify Development records and credentials cannot leak into Production configuration.

**Exit criterion**

- [ ] Production contains a complete validated catalog and the release candidate reads it safely.

### Task 31 — Legal, Attribution, and App Review Gate

**Depends on:** Task 30.

**Work**

- [ ] Obtain legal review of character names, artwork, card images, descriptions, API terms, fonts, app icon, screenshots, metadata, and the neutral naming policy.
- [ ] Resolve source-attribution requirements without violating the shipping terminology rule; treat incompatible requirements as a blocker rather than hiding attribution.
- [ ] Add approved acknowledgements, privacy disclosures, data-source disclosures, and unofficial-app language.
- [ ] Prepare App Store name, subtitle, keywords, description, screenshots, privacy answers, review notes, and support URL using only approved neutral wording.

**Tests**

- [ ] Run the terminology scanner against the final archive and all App Store metadata/screenshots.
- [ ] Verify the app contains no copied GPL implementation or unapproved foil assets.
- [ ] Verify every bundled font and asset has recorded provenance/license.
- [ ] Conduct a final human legal checklist and archive its approval.

**Exit criterion**

- [ ] Counsel-approved rights, attribution, metadata, and archive checks are complete; otherwise public release remains blocked.

### Task 32 — Final Release Candidate

**Depends on:** Task 31.

**Work**

- [ ] Build the final archive from a clean checkout.
- [ ] Run the full automated suite and manual smoke test against Production.
- [ ] Verify crash-free startup with signed-in, signed-out, online, offline-warm, and unavailable-service conditions.
- [ ] Record catalog manifest version, commit, build number, schema version, and rollback procedure.

**Tests**

- [ ] Install through the release distribution path on supported iPhone and iPad hardware.
- [ ] Repeat the launcher → detail → carousel → encyclopedia → evolution → cards → card-detail flow.
- [ ] Verify archive contents, entitlements, bundle IDs, privacy manifest, terminology scan, secret scan, and Production read-only behavior.

**Exit criterion**

- [ ] The archived build passes every technical and legal gate and is ready for submission.

## Future Backlog — Not Part of the Initial Build

### Future Task A — Personal Library

- [ ] Add a separate private CloudKit-backed SwiftData configuration.
- [ ] Add neutral `FavoriteRecord` and `CollectedCard` models.
- [ ] Implement favorite creatures/cards, owned-card variants, quantities, offline changes, reinstall recovery, and two-device synchronization.
- [ ] Test concurrent edits, duplicate reconciliation, offline/online transitions, and private/public-store isolation.

### Future Task B — Native Card Effects

- [ ] Implement an original native Core Motion and SwiftUI tilt/glare/foil effect without copying GPL code or referenced textures.
- [ ] Test motion limits, frame pacing, Reduce Motion, backgrounding, and effect selection by card metadata.
- [ ] Complete a separate license and visual-fidelity review before release.

### Future Task C — Guided Card Scanning

- [ ] Use on-device Vision OCR to read card name and collector number.
- [ ] Query likely catalog matches and require user confirmation before adding a card.
- [ ] Test camera denial, unsupported devices, poor lighting, OCR ambiguity, incorrect matches, offline mode, and accessibility.
