# Public CloudKit Catalog Specification

## Purpose and boundary

The public CloudKit database distributes a versioned, read-only catalog to application clients. Normalized payloads are encoded by `CloudCatalogRecordCodecs.swift`; feature/domain models and the device-only SwiftData mirror remain separate representations. Artwork is stored as source URLs, and the initial schema creates no `CKAsset` artwork records.

Application code receives a read-only store in Task 15. Public mutation belongs exclusively to the separately distributed loader introduced in Tasks 10–14. Automated tests use value snapshots or Development-only namespaces and never resolve Production for writes.

## Record contracts

All records contain `schemaVersion`, `sourceIdentifier`, `contentHash`, `loaderTimestamp`, and normalized envelope bytes in `payload`. `sourceTimestamp` is included when a source exposes one. Payloads are capped at 900 KiB, leaving headroom under CloudKit's 1 MB record limit.

| Record type | Deterministic record name | Projected fields |
| --- | --- | --- |
| `CatalogManifest` | `catalog-manifest-v{schemaVersion}` | revision, publishedAt, creatureCount, evolutionCount, cardCount |
| `CreatureCatalogRecord` | `catalog-creature-{positiveID}` | normalizedName, displayName, generation when present, types |
| `EvolutionCatalogRecord` | `catalog-evolution-{positiveID}` | memberIdentifiers |
| `CardCatalogRecord` | `catalog-card-{SHA256(sourceID)}` | normalizedName, displayName, setIdentifier, collectorNumber, types, relatedCreatureIdentifiers |

The content hash is SHA-256 over the sorted-key normalized persistence envelope. Decode rejects record-type or deterministic-name mismatches, malformed envelopes, unsupported schemas, missing or incorrectly typed fields, hash mismatches, negative timestamps, invalid IDs, and oversized payloads.

## CloudKit Console indexes

The following indexes are present and audited in the Development environment. None have been deployed to Production.

- `CatalogManifest`: queryable and sortable `schemaVersion`, `revision`, and `publishedAt`; queryable `sourceIdentifier`.
- `CreatureCatalogRecord`: queryable `sourceIdentifier`, `schemaVersion`, `generation`, and `types`; queryable and sortable `normalizedName`; sortable `loaderTimestamp`.
- `EvolutionCatalogRecord`: queryable `sourceIdentifier`, `schemaVersion`, and `memberIdentifiers`; sortable `loaderTimestamp`.
- `CardCatalogRecord`: queryable `sourceIdentifier`, `schemaVersion`, `setIdentifier`, `types`, and `relatedCreatureIdentifiers`; queryable and sortable `normalizedName` and `collectorNumber`; sortable `loaderTimestamp`.
- Every record type: deterministic record-name lookup; queryable `contentHash` for loader reconciliation.

Configure the Development console with these catalog permissions, then verify them with the probes below:

- `_world`: `Read` is enabled for `CatalogManifest`, `CreatureCatalogRecord`, `EvolutionCatalogRecord`, and `CardCatalogRecord`; `Create` and `Write` are disabled. CloudKit applies `_world` to both signed-out and authenticated application clients.
- `_icloud`: Create and Write are intentionally enabled for all four catalog record types in the Development environment. This temporary operational role permits later authenticated Development loader runs; it does not add an application mutation API, but it means a signed Development app client is not currently expected to be write-denied.
- `_creator`: only the system `Users` record type is assigned; no catalog record types are assigned.
- Team developers retain console authority for Development maintenance. The loader introduced in Tasks 10–14 authenticates through its separate server-to-server identity; no loader credential or mutation API belongs in the app. Do not change this Development role while the catalog expansion workflow relies on it, and never copy it to Production as part of the initial build.

CloudKit uses `Write` for both record changes and deletes. The operational probe therefore verifies create, change, and delete separately instead of inferring all three from the console checkboxes.

## Development container and signing

The intended Development container is `iCloud.com.askcruit.Battle-Card-Dex` and must contain exactly the four catalog record types above. The project is configured for Apple Developer App ID `com.askcruit.Battle-Card-Dex`, CloudKit, Push Notifications, and development team `PMF38PJVT3`; live container association and provisioning must be confirmed during the signed-device probe.

`BattleCardDex.entitlements` declares the container and CloudKit service. Its environment values are build-setting driven:

- Debug: `aps-environment = development` and `com.apple.developer.icloud-container-environment = Development`.
- Release: `aps-environment = production` and `com.apple.developer.icloud-container-environment = Production`.

This explicit split prevents a Debug integration probe from silently resolving Production. No Task 9 action deployed the Development schema or wrote records to Production.

## Environment policy

- Debug reads the Development public database.
- Release reads the Production public database.
- Test uses a fake catalog and in-memory persistence; `DevelopmentCloudRecordNamespace` rejects both Production and fake-service construction.
- Automated tests and development scripts must never create, modify, or delete Production records.
- The application-side public catalog protocol exposes reads only. Loader mutation is a separate executable boundary and must require an explicit Development or Production selection; Production operations are outside the initial-build task list.

The shipping entitlement declares `iCloud.com.askcruit.Battle-Card-Dex` and the CloudKit service. `Info.plist` retains `remote-notification` background mode for the selected update mechanism.

## Verification

Codec tests cover all four snapshot round trips, concrete `CKRecord` bridging, absence of `CKAsset`, deterministic names/hashes, neutral vocabulary, field/type validation, schema rejection, invalid IDs/names, and the size ceiling.

Task 9 added a Debug-only launch probe and opt-in UI integration tests. Ordinary test runs skip these live tests unless `BATTLE_CARD_DEX_RUN_LIVE_CLOUDKIT_TESTS=1` is present in the `xcodebuild` process environment. The read probe uses the configured Development public database, fetches `CatalogManifest/catalog-manifest-v1`, decodes it with the production record codec, and checks its record type, deterministic name, and schema version.

Pending live verification:

- Fetch and decode the public probe from a Development-signed physical device.
- Fetch and decode the same probe while signed out, once a usable simulator or device environment is available.
- The client mutation-denial probe cannot pass while the intentional Development `_icloud` Create/Write role remains enabled. Re-run it only after the role model is changed under an approved later security plan; do not use this as a reason to alter Development permissions now.
- Exercise the loader's server-to-server authentication against Development only.

To repeat the mutation test, a team developer must first create an empty Development/public `CatalogManifest` record named `security-probe-existing-v1`, run only `testDevelopmentAppCannotMutatePublicCatalogRecords` with the live-test opt-in, and delete the disposable record through the console afterward. Never use a production record or deploy the Development schema as part of this procedure.
