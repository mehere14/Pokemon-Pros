# Architecture Specification

## Configuration composition root

`AppConfiguration` is the application composition root for static runtime policy. Feature code receives typed configuration values and does not read build configuration names, environment variables, process arguments, or compiler conditions.

The one build-selection conditional lives in `AppConfiguration.current`: Debug builds select `.debug`; optimized Release builds select `.release`. Automated tests construct `.test` explicitly, so a test cannot accidentally inherit a live catalog service.

## Boundary map

- `AppConfiguration` composes environment, public catalog, cache, interaction, motion, design, pagination, locale, timeout, retry, seed-range, persistence, and feature-flag policy.
- `CloudCatalogConfiguration` contains only the public CloudKit container and public record identifiers used by the app's read path.
- `CacheConfiguration` owns memory/disk budgets, prefetch distance, and local transaction batch size.
- `InteractionConstants`, `MotionConstants`, and `DesignConstants` are reference-derived value types consumed by UI modules.
- The SwiftData container reads `LocalPersistenceMode` at the app boundary. `.test` is structurally restricted to an in-memory store.
- The test catalog mode is `.fake`. Validation rejects either live CloudKit mode in a Test profile.

## Trust and deployment boundaries

The iOS target contains no provider URL, endpoint path, API key, CloudKit server key, signing-key path, checkpoint path, or loader concurrency/rate-limit policy. Those values belong to the separate loader target introduced by its own implementation task. Public CloudKit access in the app is entitlement-backed and read-only by architecture; mutation roles and the concrete client arrive in later catalog tasks.

The loader is a separate Swift Package Manager product under `Loader/`. Its command parser, local/CI secret resolver, report encoder, and network/write adapters are not linked into the Xcode project. CI supplies secrets through the process environment; local runs use the gitignored, owner-only `.env.local` configuration. Private signing keys remain external to the repository, and loader reports/logs are structured and redacted.

Provider transport is injected behind pagination/rate-limit/retry seams. Normalized batches are referentially validated and content-hashed before a resumable publisher upserts deterministic records. The publisher commits data batches and checkpoints first, then publishes a manifest as the final visibility gate.

On-device reads use `PublicCloudKitCatalogStore` over `CKContainer.publicCloudDatabase`, then `CatalogCoordinator` resolves memory → SwiftData → CloudKit and retains successful documents locally. `URLSessionImageRepository` provides a separate cancellable, coalescing memory/URLCache path for artwork; card grids pass small URLs and the static viewer requests large URLs only after presentation.

Provider transport is injected behind pagination/rate-limit/retry seams. Normalized batches are referentially validated and content-hashed before a resumable publisher upserts deterministic records. The publisher commits data batches and checkpoints first, then publishes a manifest as the final visibility gate.

Debug uses the Development public database, Release uses the Production public database, and Test uses neither. Automated tests must never resolve or mutate Production CloudKit.

The CloudKit container ID is expressed in typed runtime configuration and is necessarily mirrored in the app entitlement because code signing requires a declarative container identifier. No feature module owns another copy.

## Data-flow direction

Future feature modules depend inward on these configuration values. Configuration does not depend on feature views, repositories, persistence models, CloudKit implementations, or loader code. This preserves deterministic construction for tests and keeps build-environment policy out of feature logic.

Catalog data crosses explicit, one-way type boundaries: loader response DTOs map to schema-versioned normalized payloads; normalized payloads are wrapped in validated persistence envelopes; persistence codecs map those envelopes to separate CloudKit records or SwiftData models; repositories decode domain values; feature modules create their own view state. Provider DTOs are never persistence models, domain values, or view state. Domain values import only Foundation and contain immutable data, never observation or persistence behavior.

`CatalogPersistenceEnvelope` is the shared trust boundary. Its generic initializer accepts only `NormalizedCatalogPayload` conformers, while persisted bytes must decode as a supported envelope before use. Payload-kind checks prevent a valid record body from being decoded as the wrong module. CloudKit record structures and SwiftData `@Model` classes remain owned by their respective implementation tasks and store the envelope rather than inheriting from or aliasing its catalog payload.

## Deterministic test seams

The data layer exposes protocol boundaries for the public catalog, local catalog, image repository, clock, and retry scheduler. These boundaries exchange `CatalogDocument` values containing validated normalized envelopes plus freshness and partial-failure metadata. Catalog-to-domain mapping depends on these contracts; the contracts do not depend on provider DTOs, CloudKit records, SwiftData models, or feature state.

Actor-backed protocol fakes and normalized JSON fixtures compile only into the unit-test target. Unit tests use fresh in-memory SwiftData containers. Development CloudKit integration tests must use an isolated run namespace whose type rejects Production construction; ordinary unit tests use the fake catalog and resolve no CloudKit environment.

## Device catalog mirror

`SwiftDataLocalCatalogStore` is an actor-owned persistence adapter behind `LocalCatalogStore`. Its schema contains only `CachedCatalogManifest`, `CachedCreature`, `CachedEvolutionChain`, and `CachedCard`; the starter sample model is not part of the application. `BattleCardDexApp` creates this schema at the composition root with `cloudKitDatabase: .none`, making the database a disposable device mirror rather than a second synchronized catalog authority.

Each row stores its stable source ID, record identifier, content hash, schema version, cache timestamp, validated normalized envelope bytes, and the minimum scalar projection needed by local queries. Those projections support creature index ordering, normalized name or number search, generation and type filters, evolution membership, and card-to-creature relationships without collapsing persistence models into domain values.

A replacement batch is completely decoded and validated before SwiftData mutation begins. Duplicate source IDs resolve deterministically with the last input winning. The subsequent upserts execute in one model-context transaction; an error rolls the context back, leaving the last valid rows available. Matching content hashes skip all writes, including cache-timestamp changes. The store file and its SQLite sidecars can be deleted as a unit and reconstructed empty from the same schema; later repository work repopulates it from the public catalog.

## Public catalog record boundary

Four versioned codecs map normalized payloads through a value-only snapshot that can bridge to `CKRecord`. Domain models, SwiftData entities, and feature state never depend on raw CloudKit field dictionaries. Deterministic record IDs and payload hashes are shared by the future loader and read-only client; write capability is deliberately absent from application-facing contracts.
