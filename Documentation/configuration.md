# Application Configuration Specification

## Environment profiles

| Policy | Debug | Test | Release |
| --- | --- | --- | --- |
| Catalog service | Development public database | Fake | Production public database |
| Local persistence | Persistent | In memory | Persistent |
| Diagnostic logging | Enabled | Disabled | Disabled |
| Motion | Enabled | Disabled for deterministic tests | Enabled |
| Full catalog | Disabled | Disabled | Disabled until catalog promotion |

All profiles use public container `iCloud.com.askcruit.Battle-Card-Dex`, schema version `1`, manifest record ID `catalog-v1`, and record types `CatalogManifest`, `CreatureCatalogRecord`, `EvolutionCatalogRecord`, and `CardCatalogRecord`.

## Catalog and cache values

- Public read batch: 100 records.
- Local write batch: 100 records.
- Request timeout: 15 seconds; resource timeout: 60 seconds.
- Retry limit: 3.
- Creature page size: 60; card page size: 250.
- Memory cache: 32 MiB; disk cache: 256 MiB.
- Prefetch distance: 4 entries.
- Initial supported range: National index 1 through 30, inclusive.
- Stable formatting locale: `en_US_POSIX`.

No upstream provider base URL or loader credential has a field in app configuration.

## Validation contract

Construction fails for non-positive cache budgets, a memory budget larger than the disk budget, negative prefetch distance, non-positive page/batch sizes, negative retry limits or timeouts, empty identifiers, seed ranges starting below one, and schema versions outside `1...1`.

Cross-field validation also rejects a Test profile unless it uses both fake CloudKit and in-memory persistence, and rejects diagnostic logging in Release. This makes isolation and Release policy properties of the type construction path instead of call-site convention.

## Feature-flag lifecycle

The complete-catalog flag remains false in every environment during the first-seed milestone. It may be enabled for Release only after the production catalog task proves schema, manifest, counts, hashes, and permissions. No flag permits upstream network fallback in the shipping app.
