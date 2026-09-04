# Battle Card Dex — Version 2 Plan

**Status:** Draft for review  
**Updated:** September 4, 2026

## 1. Product Summary

Battle Card Dex is a native SwiftUI app for iPhone and iPad that combines a complete, interactive creature field guide with evolution data and related battle cards.

Version 2 merges the original product, API, SwiftData, and CloudKit plan with the approved interactive design direction. The application must feel and behave like the supplied mockup while replacing its sample data with live PokéAPI and Pokémon TCG API content.

Version 2 includes:

- Every supported species across all generations.
- Encyclopedic creature profiles.
- Complete and branching evolution chains with evolution requirements.
- Trading cards related to each creature.
- A shared catalog cache in CloudKit’s public database so every installation benefits from the same preloaded creature, evolution, and card data.
- A local SwiftData mirror for fast launches and offline reuse of records previously downloaded from public CloudKit.
- Light and dark appearances on iPhone and iPad, in portrait and landscape.

Version 2 does not include the Personal Library, favorites, an owned-card collection, camera card scanning, OCR, visual card recognition, native holographic card effects, pricing, grading, card condition, card language, purchase history, social features, or “seen creature” tracking. The Personal Library and native card effects remain documented as future phases.

## 2. Sources of Truth

Implementation must follow these sources in priority order:

1. `Design Mockup/index.html`, `Design Mockup/styles.css`, and `Design Mockup/app.js` are the authority for screen composition, navigation, gestures, transitions, animation sequencing, and device-specific layout.
2. `Plan/design.md` is the authority for colors, typography, spacing, shapes, elevation, and component styling.
3. This plan is the authority for product scope, data behavior, persistence, API boundaries, errors, accessibility, and verification.
4. Where a CSS value and `design.md` differ slightly, the rendered mockup value takes precedence so the native result matches the approved visual reference.

The mockup files remain immutable reference material during implementation. Screens not represented in the mockup must extend its existing components and motion language; they must not fall back to visually unrelated stock SwiftUI layouts.

### 2.1 Shipping Name and Neutral-Terminology Rule

- The product name and user-facing brand are exactly **Battle Card Dex**.
- Rename the Xcode project, targets, schemes, executable, Swift app entry point, source directories, test targets, display name, bundle identifiers, entitlements, and CloudKit container to neutral Battle Card Dex names.
- Use `BattleCardDexApp`, `Creature`, `CreatureProfile`, `CreatureRepository`, `CreatureCatalogRecord`, and `CachedCreature`-style identifiers. Do not use the prohibited franchise term in Swift symbols, comments, filenames, target metadata, authored UI copy, accessibility labels, analytics events, logs, fixture names, or bundled assets.
- Use “Field Guide,” “national index,” “creature,” “evolution,” and “battle card” in authored UI copy.
- Add a case-insensitive Unicode-aware release scan that fails when the prohibited term or its accented spelling occurs in any shipping source, generated bundle, executable strings, plist, entitlement, localization, asset name, test target that ships, or archive metadata.
- `Plan/` and the non-shipping `Design Mockup/` reference are documentation inputs and are excluded from the app target and release archive. External provider names may appear in planning/legal documentation and in the separately distributed maintenance loader, but never in the iOS app target.
- The loader sanitizes all remotely sourced text before publication to public CloudKit. Any description containing prohibited branding is rewritten into neutral factual language or omitted; raw upstream payloads are never copied wholesale into the public catalog or iOS cache.
- Remote card images may visibly contain third-party marks even though they are not bundled. Character names and artwork may also be independently protected. A generic app name is therefore not an App Review or intellectual-property guarantee; obtain a legal/licensing review before public distribution.

## 3. Application Experience

### 3.1 Launcher and National Field Guide

- Open on the reference launcher with shipping copy changed to “Choose Your Battler.”
- Replace the PROS wordmark with DEX bolt branding while preserving its size, position, typography, and motion. Preserve the region indicator, atmospheric glows, orbital traces, glass creature tiles, type-colored bottom traces, and Surprise Me action.
- Replace the six sample creatures with a lazy National Field Guide grid ordered by canonical national index number.
- Use two columns on iPhone portrait and three columns on iPad and landscape layouts, matching the reference proportions and spacing.
- Initially fetch a lightweight species index containing stable IDs and names. Fetch artwork and details lazily and prefetch only nearby visible entries.
- Make the region indicator interactive without changing its appearance. It opens a design-matched search and filter layer with:
  - Name and national-index-number search.
  - Generation filter.
  - Type filter.
  - Clear/reset action.
- Keep filtering local when the required index is available. Load generation and type membership from PokéAPI on demand and cache it.
- Surprise Me shuffles the current loaded/filtered result window, guarantees a visibly different order when possible, and uses the mockup’s 480 ms rearrangement animation and rotating sparkle.
- Keep the trailing sparkle as the non-interactive app-state ornament shown in the initial mockup. Its future Library behavior is deferred.

### 3.2 Launcher-to-Detail Transition

- Tapping a creature tile stores it as the focus-return target and opens the primary detail experience.
- Fade the launcher over 300 ms while translating it 7% left.
- Enter the detail layer from 7% right at 0.985 scale.
- Complete the transition over 420 ms using the reference spring curve.
- The custom back control reverses the transition and restores focus to the originating tile.

### 3.3 Primary Creature Detail

The primary detail must preserve the mockup’s hierarchy:

- Branded top bar, custom back button, region text, and decorative sparkle.
- Pull-down Cards gesture pill.
- Large artwork carousel with neighboring creatures.
- Previous/next controls and animated page indicator.
- National index number, name, type chips, evolution stage, and short description.
- Compact Field Guide data panel showing height, weight, genus/category, primary ability, gender ratio, and calculated weaknesses.
- Pulsing “Live scan” visual treatment; this is a decorative data-state indicator and not camera scanning.
- Swipe-up Evolutions gesture pill.

### 3.4 Encyclopedic Creature Data

Tapping the compact Field Guide data panel opens a full-screen encyclopedia layer using the mockup’s glass surfaces, typography, chips, gradients, and horizontal transition language.

The layer contains, when supplied by PokéAPI:

- Official artwork, standard sprites, shiny artwork, and alternate forms.
- Names, national index number, genus, sanitized descriptions, generation, color, shape, and habitat.
- Height, weight, base experience, capture rate, base happiness, growth rate, and held items.
- Types, abilities, hidden abilities, base stats, and calculated weaknesses.
- Gender ratio, egg groups, hatch information, baby status, varieties, and forms.
- Game indices and game/version availability.
- Moves grouped and filterable by game version and learning method.
- Move name, type, damage class, power, accuracy, PP, priority, and effect on demand when a move is opened.
- Encounter locations loaded on demand rather than during the initial profile request.

Missing fields must be omitted or presented as unavailable without breaking the layout. Large sections use lazy containers and do not block the primary detail screen.

### 3.5 Horizontal Creature Carousel

- Artwork follows the finger continuously.
- Visual drag distance equals 82% of finger travel.
- The current creature scales down by as much as 6% during a drag.
- The incoming neighbor fades from 45% to 100% opacity with progress.
- Commit to the next item when horizontal travel exceeds 22% of carousel width.
- Also commit for a flick completed within 280 ms that travels more than 34 points.
- Otherwise return to the current item.
- Settle over 460 ms with `cubic-bezier(0.22, 0.82, 0.24, 1)` translated to an equivalent SwiftUI timing curve.
- Attempting to move beyond either boundary produces the reference 220 ms bump.
- Arrow controls, keyboard commands where available, and VoiceOver adjustable actions invoke the same state transition.
- Carousel gestures take priority inside the artwork region. Global vertical panel gestures do not begin from the carousel, modal, or another interactive control.

### 3.6 Related Cards Pull-Down Panel

- A downward gesture outside excluded controls selects the cards panel after 6 points of vertical travel.
- The panel follows the finger from above the display.
- Interactive progress is measured against 42% of the app height.
- As the panel travels, scale the underlying detail from 1.0 to 0.985, increase blur to 6 points, reduce brightness to 88%, and fade in the scrim proportionally.
- Open after downward travel exceeds 22% of screen height; otherwise return it offscreen.
- Settle over 420 ms using `cubic-bezier(0.20, 0.90, 0.24, 1)` translated to SwiftUI.
- Tapping the Cards gesture pill performs the same transition.
- Panel height is 83% on iPhone portrait, 56% on iPad portrait, and full height on iPhone landscape.
- Close through the × control, scrim tap, accessibility action, or an upward panel drag exceeding 12% of app height.
- Related cards enter over 320 ms, staggered by 45 ms beginning after an 80 ms delay.
- Query related cards using `nationalPokedexNumbers`, not name matching.
- Paginate the card gallery and show image, name, set, collector number, rarity, type, and HP.
- Tapping a card opens the card viewer.

### 3.7 Card Detail and Viewer

- Fade the dark blurred backdrop over 180 ms.
- Enter the card over 340 ms from 24 points below at 0.82 scale.
- Close from the × control, backdrop, accessibility escape, or system dismissal action and restore focus to the originating card.
- Present the card image without Core Motion tilt, procedural glare, foil simulation, or copied third-party textures in the initial build.
- Provide an action beneath the artwork to open full card information.
- Full card information includes available subtypes, HP, types, rules, abilities, attacks, weaknesses, resistances, retreat cost, evolution text, set, collector number, rarity, artist, flavor text, regulation mark, and legalities.
- Price fields supplied by the API are not displayed or persisted in Version 2.

### 3.8 Evolution Swipe-Up Panel

- An upward drag uses the same progressive scale, blur, brightness, scrim, 22% opening threshold, and 420 ms spring as the cards panel.
- Panel height is 58% on iPhone portrait, 51% on iPad portrait, and full height on iPhone landscape.
- Close through ×, scrim, accessibility action, or a downward drag exceeding 12% of app height.
- Draw the yellow-to-orange connector over 380 ms after a 120 ms delay.
- Enter evolution nodes over 330 ms with 70 ms staggering beginning at 240 ms.
- Pulse the current stage once over 420 ms at 1.045 scale.
- Selecting a node closes the panel and changes the primary creature selection.
- Recursively decode evolution families rather than assuming a linear three-stage chain.
- Display all supplied requirements, including trigger, level, item, held item, trade, friendship, affection, beauty, time, location, weather, gender, known move, known move type, party species/type, and upside-down-device requirements.
- Branching chains adapt the connector layout while preserving the reference node styling and animation order.
- Creatures with no evolutions show a complete empty state in the same panel.

### 3.9 Future Phase: Personal Library

The Personal Library is not part of the initial Version 2 build. Preserve it as the next user-feature phase without allowing it to shape the initial public catalog schema.

Its future scope remains:

- Favorite creatures.
- Favorite cards.
- Owned cards grouped by card and printing variant.
- Normal, holofoil, reverse holofoil, first-edition normal, first-edition holofoil, and unspecified variants.
- Manual quantity changes, followed later by guided OCR card scanning.
- Private SwiftData/CloudKit synchronization so user-owned data survives reinstall and syncs across the user’s devices.

## 4. Design System

### 4.1 Canonical Tokens

- Electric yellow: `#F7E61A`.
- Orange: `#EF671A`.
- Plum: `#8849A6`.
- Dark base surface: `#171021`.
- Light base surface: `#F5EFF7`.
- Preserve all additional surface, content, outline, error, fixed, and inverse colors defined in `Plan/design.md`.
- Preserve the 8-point baseline rhythm, 16-point phone margins, 64-point large-layout margins where applicable, and the documented 4/12/24/48/80-point spacing scale.
- Preserve 8-point standard radii, 24-point large-container radii, and pill-shaped interactive chips.

### 4.2 Typography

- Bundle Sora for display and headline text.
- Bundle Hanken Grotesk for body content.
- Bundle Space Grotesk for labels, metadata, and uppercase technical text.
- Include all required font licenses in the application acknowledgements.
- Match the mockup’s device-specific type sizes and line heights. Dynamic Type may expand deep-detail layouts but must preserve the visual hierarchy.

### 4.3 Surfaces and Depth

- Recreate glass surfaces with SwiftUI materials, controlled opacity, borders, and blur.
- Use one-pixel low-opacity borders and top inner highlights.
- Use tonal layers and tinted indigo/plum shadows instead of generic black drop shadows.
- Preserve creature-specific ambient radial glows and the background orbital line motif.
- Preserve yellow-to-orange progress and connector gradients.
- Use type-specific chip colors with accessible foreground contrast.
- Dark appearance is the default. Light and follow-system modes are available from a small appearance control and persisted with `AppStorage`; this does not require the deferred Personal Library.

### 4.4 Device Layouts

- Implement distinct compositions for iPhone portrait, iPhone landscape, iPad portrait, and iPad landscape.
- Do not implement landscape as a mechanically rotated portrait stack.
- Portrait centers the artwork over compact metadata.
- iPad and landscape use artwork/detail columns matching the mockup.
- iPhone landscape omits the long primary description; it remains accessible through the encyclopedia layer.
- Respect safe areas while maintaining the reference content proportions.

### 4.5 Motion and Accessibility

- Store gesture thresholds and animation timings in `InteractionConstants` and `MotionConstants`.
- Store colors, typography, spacing, shape, shadow, and layout values in `DesignConstants`.
- Put user-facing copy in a String Catalog.
- Reduce Motion replaces parallax, tilt, shuffle travel, staggered entrances, and repeating hints with near-instant fades.
- Every gesture has an equivalent visible control and VoiceOver action.
- Opening and closing layers must move accessibility focus predictably and restore it to the initiating element.
- Support VoiceOver, Dynamic Type, increased contrast, Reduce Transparency, button shapes, and landscape text sizing.
- Do not introduce unreferenced haptics, stock navigation transitions, or unrelated default component styling.

## 5. Architecture

### 5.1 Application Layers

- **App shell:** local model container, dependency construction, appearance, and root error handling.
- **Features:** launcher, creature detail, encyclopedia, cards, evolution, and appearance settings.
- **Domain:** provider-independent creature, evolution, move, encounter, and card models.
- **Data:** public CloudKit client, local SwiftData mirror, upstream API DTOs and mapping used by the loader, repositories, and image cache.
- **Design system:** tokens, reusable controls, glass surfaces, chips, motion modifiers, and gesture coordinators.
- **Catalog loader:** a separate developer-operated command-line tool that reads upstream APIs, validates and normalizes responses, and writes public CloudKit records.

Views consume observable feature models and domain values. Views must not construct CloudKit queries, decode provider responses, or contain cache reconciliation logic.

### 5.2 Dependency Boundaries

Create a central `AppDependencies` value and inject protocol-backed services:

- `CreatureRepository` loads the species index, creature profiles, species data, forms, moves, encounters, types, and generations.
- `EvolutionRepository` loads and maps recursive evolution chains.
- `CardRepository` searches related cards and loads card details.
- `PublicCatalogStore` reads versioned records from `CKContainer.publicCloudDatabase`.
- `LocalCatalogStore` reads and writes the device-only SwiftData mirror.
- `ImageRepository` loads and caches artwork and card images while coalescing duplicate requests.

Use async/await and cancellation throughout. Shared mutable caches use actors. UI-facing observable models remain main-actor isolated.

### 5.3 Networking

The iOS app uses a CloudKit client responsible for:

- Reading the catalog manifest.
- Fetching deterministic record IDs and performing indexed queries against the public database.
- Following CloudKit query cursors.
- Selecting only required record fields.
- Retrying safe transient CloudKit failures with bounded backoff.
- Mapping public records into domain models and the local SwiftData mirror.

The separate loader uses one generic upstream API client responsible for:

- Base URL and endpoint composition.
- Percent encoding, including Pokémon TCG query syntax.
- HTTP status validation.
- JSON decoding.
- Request cancellation.
- Request coalescing.
- Retry of safe transient failures with bounded backoff.
- Translation into typed app errors.

Provider-specific loader adapters own PokéAPI and Pokémon TCG endpoint knowledge. API DTOs never become SwiftData models or public CloudKit records directly; validated mapping produces stable catalog payloads.

> **DTO definition:** DTO means **Data Transfer Object**. It is a Swift type shaped specifically like an external JSON response so the decoder can read it. A DTO is not the app’s long-term database model or UI model. Keeping DTOs at the API boundary prevents a provider’s naming or response changes from spreading throughout the app.

### 5.4 Configuration and DRY

Create `AppConfiguration` as the single source for:

- PokéAPI and Pokémon TCG API base URLs.
- Endpoint paths.
- CloudKit container ID, public record-type names, catalog schema version, and manifest record ID.
- Timeouts and retry limits.
- Pokédex and card page sizes.
- Memory and disk cache budgets.
- Prefetch distance.
- Default locale.
- Feature flags.
- Seed range for integration testing, initially National Pokédex IDs 1–30.
- Loader request concurrency, minimum request interval, batch size, and checkpoint location.

Use centralized endpoint builders, record mappers, DTO fragments, formatters, image components, and loading/error components. Avoid duplicate models or view-specific copies of the same parsing and business rules.

No third-party runtime packages are required for Version 2.

## 6. Shared Catalog and Cache Architecture

### 6.1 Source APIs

The catalog loader—not the production iOS client—uses PokéAPI v2 at `https://pokeapi.co/api/v2/` for species indexes, creature and species details, evolution chains, moves, encounters, forms, generations, and types.

The loader uses Pokémon TCG API v2 at `https://api.pokemontcg.io/v2/` for related cards and card details. Related-card queries use the provider’s national-index field, and all pagination is completed before a creature’s cache entry is marked ready.

PokéAPI asks clients to cache under its fair-use policy. Pokémon TCG applies stricter request limits. Centralizing upstream access in a controlled loader prevents every user installation from repeating the same global requests.

### 6.2 Four-Level Read Policy

The initial application read path is fixed in this order:

1. **In-memory cache:** current screens, current creature family, adjacent carousel entries, and recently viewed cards.
2. **Local SwiftData mirror:** structured catalog records previously downloaded on this device.
3. **Public CloudKit database:** the shared, versioned catalog available to every installation.
4. **Upstream APIs:** loader only. Release builds never call PokéAPI or Pokémon TCG directly. A debug-only fallback may be enabled for developer diagnosis but must never write public CloudKit from the client.

On launch, read the local manifest immediately, render available cached data, then compare it with the public `CatalogManifest`. Download only missing or changed records. A reinstall loses the device mirror but reconstructs it from the public database without contacting upstream providers.

### 6.3 Public CloudKit Records

Use direct CloudKit APIs through `CKContainer.publicCloudDatabase`; SwiftData’s managed CloudKit integration is not the public-cache mechanism.

Apple references: [public CloudKit database](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase), [CloudKit record limits](https://developer.apple.com/documentation/cloudkit/ckrecord), and [SwiftData CloudKit configuration](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct).

Public record types are:

- `CatalogManifest`
  - Deterministic record name `catalog-v1`.
  - Catalog schema version, content version, publication state, build timestamp, supported national-index range, and creature/evolution/card counts.
  - The loader updates the manifest only after all records in a run have been validated and committed.
- `CreatureCatalogRecord`
  - Deterministic record name such as `creature-0001`.
  - National Pokédex ID, normalized name, generation, types, summary artwork URLs, content hash, source timestamp when available, loader timestamp, schema version, and a compact encoded profile payload.
- `EvolutionCatalogRecord`
  - Deterministic record name such as `evolution-chain-0001`.
  - Evolution-chain ID, member species IDs, content hash, loader timestamp, schema version, and a compact encoded recursive chain payload.
- `CardCatalogRecord`
  - Deterministic record name derived from the Pokémon TCG card ID.
  - Card ID, related National Pokédex IDs, normalized name, set ID/name, collector number, rarity, small/large image URLs, content hash, loader timestamp, schema version, and a compact encoded card-detail payload.

Keep each non-asset record below CloudKit’s 1 MB record limit. Add queryable/sortable indexes for manifest version, National Pokédex ID, normalized name, generation, types, evolution member IDs, card-related Pokédex IDs, set ID, and collector number as required by app queries.

For the first implementation, public CloudKit stores structured data and source image URLs. Images continue to use their source CDNs plus the device HTTP cache. Do not duplicate all card artwork as `CKAsset` until storage, transfer, licensing, and performance measurements justify it.

### 6.4 Local SwiftData Persistent Models

Replace the starter `Item` with a device-only SwiftData configuration using `cloudKitDatabase: .none`. These models mirror public records and are disposable/rebuildable:

- `CachedCatalogManifest`
  - Manifest ID, schema version, content version, publication state, source counts, refresh timestamp, and last successful synchronization timestamp.
- `CachedCreature`
  - National Pokédex ID, normalized name, generation, types, artwork URLs, content hash, schema version, encoded normalized profile payload, and cached timestamp.
- `CachedEvolutionChain`
  - Chain ID, member species IDs, content hash, schema version, encoded normalized chain payload, and cached timestamp.
- `CachedCard`
  - TCG card ID, related Pokédex IDs, normalized name, set metadata, collector number, rarity, image URLs, content hash, schema version, encoded normalized card payload, and cached timestamp.

Use stable source identifiers for app-level upserts. Because this store is only a local mirror, it may use local indexes and uniqueness enforcement where SwiftData supports them. Catalog replacement occurs transactionally per downloaded batch; a failed refresh leaves the last valid local record in place.

The future Personal Library will use separate user-owned SwiftData models and a separate private CloudKit configuration. Do not mix future favorites or collection records into the public catalog record types or the device cache schema.

### 6.5 Public Database Security and Availability

- Configure public catalog record types as world-readable and writable only by the developer/loader role.
- Production clients perform no public database mutations.
- Reads remain available even when a user is not signed into iCloud; show a recoverable service state if CloudKit itself is unavailable.
- Public catalog data consumes the app container’s CloudKit quota, so record and asset growth must be measured before the full import.
- Use deterministic record names and content hashes for idempotent loader reruns and incremental updates.
- Keep development and production environments separate. Validate completely in Development, deploy schema/indexes, then run an explicit production load.

### 6.6 Initial 30-Creature Seed

The first integration milestone caches National Pokédex IDs 1 through 30 inclusive.

For those creatures, the loader must publish:

- Complete normalized creature and species profiles required by the initial UI.
- Every unique evolution chain referenced by those creatures, including members whose IDs fall outside 1–30 when required to make a chain complete.
- All related Pokémon TCG cards returned through fully followed API pagination.
- A manifest marked `testing` with exact record counts and the supported range `1...30`.

The app is restricted by a feature flag to the manifest’s supported range during this milestone. Integration testing must not silently fall through to upstream APIs for creature index 31 and above.

### 6.7 Full Catalog Loader

Create a separate, resumable command-line loader with these modes:

- `seed --range 1...30` for the initial test catalog.
- `sync --all` for a complete catalog load.
- `sync --range` for repair or staged expansion.
- `validate` for referential integrity, counts, required fields, hashes, and payload-size checks without writing.
- `dry-run` for reporting intended creates, updates, skips, and failures.

Loader behavior:

- Keep all credentials out of the iOS app. Public CloudKit reads use the app's signed entitlements and container configuration, while the creature-data API requires no API key.
- For local loader runs, store the optional card-source API key and CloudKit server-to-server key ID in macOS Keychain under the loader's service name. Keep the CloudKit private signing-key file outside the repository and store only its path in Keychain.
- For CI or hosted loader runs, use the platform's encrypted secret store and inject credentials only into the loader process at runtime.
- Allow environment-variable overrides for automation, but never commit `.env` files. If a developer temporarily uses `.env.local`, require it to be gitignored, owner-readable only, and excluded from logs and reports.
- Never store secrets in source files, `Info.plist`, `.xcconfig`, UserDefaults, SwiftData, CloudKit records, fixtures, checkpoints, logs, reports, or the built app bundle.
- Enforce provider-specific concurrency and minimum request intervals from configuration.
- Honor rate-limit headers and `Retry-After`; apply bounded exponential backoff with jitter for transient responses.
- Follow every API pagination cursor and deduplicate creatures, evolution chains, and cards by stable source ID.
- Normalize DTOs into versioned catalog payloads and validate before upload.
- Calculate a content hash and skip unchanged public records.
- Upsert deterministic record IDs in bounded batches and retry partial CloudKit failures individually where safe.
- Persist a local checkpoint after each committed batch so an interrupted run resumes without repeating completed upstream calls.
- Write a machine-readable run report with fetched, created, updated, skipped, failed, and rate-limited counts.
- Publish the manifest last. Never expose a partially loaded run as the active catalog version.

Use CloudKit Web Services with a server-to-server key for loader writes, following Apple’s [server-to-server authentication guidance](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html). The private signing key exists only in the loader environment. No credential is created or stored until the loader is implemented and configured.

After the 30-creature milestone passes, run and validate the full loader, promote the manifest to `complete`, and only then enable the full National Field Guide in the production configuration.

## 7. Deferred Personal Persistence

The initial Version 2 build has no user-generated persistent models and no private CloudKit synchronization. SwiftData is used for the local public-catalog mirror, while direct CloudKit APIs read the global public database.

In the next Personal Library phase, add a separate private CloudKit-backed SwiftData configuration containing:

- `FavoriteRecord` for creature and card favorites.
- `CollectedCard` representing each physical card copy and its printing variant.

Keep user records separate from public catalog records. Store stable catalog IDs plus small display snapshots so the Library remains understandable if catalog data is temporarily unavailable.

## 8. Future Native Card Effects and Licensing

Native tilt, glare, and holographic effects are deferred from the initial build. The initial viewer preserves the mockup’s modal layout and opening/closing transition but presents static card artwork.

For the future effect phase, note that the nested `Design Mockup/pokemon-cards-css-main` reference is GPLv3 and includes externally attributed textures.

- Do not copy its Svelte/CSS source, foil textures, masks, or third-party images into Battle Card Dex.
- Create an original native effect using Core Motion, SwiftUI transforms, procedural gradients, blend modes, noise, and masks.
- Match the observable tilt, glare position, depth, foil movement, and spring return of the approved reference.
- Select effect parameters from the card’s rarity, subtype, and chosen variant when sufficient metadata exists; otherwise use the standard glare treatment.
- Keep the effect implementation isolated behind reusable `InteractiveCardView` and `CardEffectStyle` interfaces.
- If direct reuse of the GPL source or assets is later requested, stop for an explicit licensing decision before including them.

Add an About/Data Sources screen with counsel-approved source attribution, font acknowledgements, asset notices, and an unofficial fan-app disclaimer. Do not embed prohibited branding in this screen; if a provider requires wording that conflicts with the neutral-terminology rule, treat that as a release blocker. Complete an intellectual-property and App Store review before public release.

## 9. Failure and Empty States

- Use mockup-derived glass cards, typography, and Electric Burst actions for loading, empty, offline, CloudKit quota/throttle, and error states.
- Preserve already loaded content when a secondary request fails.
- A missing creature image uses a branded silhouette placeholder without collapsing layout.
- A creature with no card matches shows an empty cards panel with retry.
- A creature with no evolution shows a stable no-evolution panel.
- A missing move or encounter catalog record affects only that section.
- Cancellation caused by leaving a screen does not display an error.
- Prevent repeated taps or gestures from opening duplicate layers.
- Rotation during a drag cancels the interactive gesture and settles into the correct orientation layout.

## 10. Verification and Acceptance Criteria

### 10.1 Visual Fidelity

Capture the running mockup as golden references at:

- 390×844 iPhone portrait.
- 844×390 iPhone landscape.
- 1024×1366 iPad portrait.
- 1366×1024 iPad landscape.
- Light and dark appearances.

Create deterministic app fixture data for Bulbasaur through Charizard and the four reference cards. Compare native output against the matching references for layout, spacing, proportions, typography, colors, borders, radii, blur, glow, shadows, and layer positions.

### 10.2 Gesture and Motion Tests

- Test carousel and panel gestures immediately below, at, and above every threshold.
- Verify fast-flick recognition and slow short-drag cancellation.
- Verify boundary bumps at the first and last carousel items.
- Verify carousel/vertical-panel gesture arbitration.
- Verify panel open, cancel, close, and interrupted-drag cleanup.
- Verify scrim, blur, brightness, and transforms always return to their correct resting values.
- Verify all reduced-motion alternatives.
- Profile the carousel, panels, shuffle, evolution entrance, and static card viewer on physical 60 Hz and ProMotion devices with no visible frame drops.

### 10.3 Unit and Integration Tests

- Loader endpoint construction and upstream query encoding.
- PokéAPI and TCG DTO fixture decoding, including missing/null fields.
- DTO-to-catalog and catalog-to-domain mapping, schema-version rejection, and measurement formatting.
- Species index ordering, generation/type filters, and search.
- Public CloudKit reads, cursor pagination, desired-key selection, request coalescing, caching, cancellation, retry bounds, throttling, and partial failures.
- Loader pagination, rate-limit compliance, content hashing, idempotent upserts, checkpoint resume, partial-batch recovery, manifest-last publication, validation, and dry-run behavior.
- Recursive and branching evolution mapping with unusual conditions.
- Move and encounter lazy loading from the shared catalog.
- Local SwiftData cache upserts, stale-record retention, batch rollback, manifest comparison, and rebuild after an empty install.
- Local persistence tests use an in-memory SwiftData container; direct CloudKit tests use a dedicated development-container test namespace.

### 10.4 UI and Accessibility Tests

- Launcher loading, filtering, Surprise Me, and focus restoration.
- Creature detail navigation and carousel behavior.
- Encyclopedia presentation and lazy sections.
- Cards panel pagination, static card viewer, and card details.
- Evolution panel presentation and node navigation.
- Loading, offline, empty, and retry states.
- VoiceOver order and labels, adjustable carousel actions, accessibility escape, Dynamic Type, increased contrast, Reduce Motion, light/dark appearance, and all four target layouts.

### 10.5 Public CloudKit and Loader Acceptance

- Run `seed --range 1...30` in the Development environment and verify a testing manifest, 30 creature profiles, all required complete evolution chains, all paginated related cards, deterministic record IDs, hashes, and referential integrity.
- Launch two clean devices, including one without an active iCloud account, and confirm both can read the same public catalog.
- Relaunch offline after one successful load and confirm the local SwiftData mirror supplies the available catalog.
- Delete and reinstall, reconnect, and confirm the cache reconstructs from public CloudKit without contacting either upstream API.
- Interrupt and resume the loader; confirm committed work is not refetched or duplicated.
- Rerun an unchanged seed; confirm the manifest and records are not rewritten unnecessarily.
- Change one fixture, rerun, and confirm only the changed record plus final manifest are updated.
- Confirm production app builds have no upstream API fallback and no permission to mutate public catalog records.
- Measure public CloudKit storage/transfer usage for the 30-creature seed and project the full-catalog cost before expansion.
- Run `validate`, complete a full Development load, deploy the public schema/indexes to Production, execute the production loader, validate again, and only then enable all National Pokédex IDs.

## 11. Version 2 Assumptions

- The app targets iPhone and iPad only, despite the starter project currently advertising additional Apple platforms.
- English is the only content language in Version 2.
- The first integration build exposes National Pokédex IDs 1–30 from public CloudKit. The complete National Pokédex is enabled only after the full loader succeeds and its manifest is validated.
- Alternate forms appear within species details rather than as duplicate launcher entries unless PokéAPI defines them as distinct species.
- Battle Card Dex remains a standalone iOS client; the developer-operated loader is a separate maintenance tool rather than an always-running backend.
- Public CloudKit is the shared structured-data cache. SwiftData is its disposable on-device mirror. Source images remain CDN-backed and use the device URL cache in the initial architecture.
- The initial build has no user-owned data, favorites, collection, or private CloudKit store.
- New screens extend the supplied Electric Burst system and require the same visual verification as directly mocked screens.
- The Personal Library is the next user-feature phase and will introduce private SwiftData/CloudKit models separately from the catalog cache.
- Native card tilt, glare, and holographic rendering are deferred and remain subject to the documented licensing boundary.
- Camera scanning remains a later release. Its eventual design should use on-device Vision OCR to extract card name and collector number, query likely matches, and require confirmation before adding to the collection.
