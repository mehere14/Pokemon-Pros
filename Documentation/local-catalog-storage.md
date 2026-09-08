# Local Catalog Storage Specification

## Purpose and ownership

The local catalog is a disposable, device-only mirror of normalized public catalog data. It supports immediate offline reads and efficient refreshes, but it is never a source of truth. `SwiftDataLocalCatalogStore` owns all persistence behavior and conforms to the data-layer `LocalCatalogStore` boundary.

The model configuration explicitly uses `cloudKitDatabase: .none`. No SwiftData history, relationship, or uniqueness behavior is allowed to create or mutate CloudKit records.

## Schema

- `CachedCatalogManifest` stores the manifest source ID, record identifier, revision, content hash, schema version, cache time, publication time, and encoded normalized manifest envelope.
- `CachedCreature` stores an integer source ID, stable record identifier, numeric sort index, normalized/display names, generation, an exact-match type index, content hash, schema version, cache time, and encoded normalized creature envelope.
- `CachedEvolutionChain` stores an integer chain source ID, stable record identifier, exact-match member-ID index, content hash, schema version, cache time, and encoded normalized evolution envelope.
- `CachedCard` stores a string source ID, stable record identifier, normalized name, collector number, set ID, exact-match related-creature-ID index, content hash, schema version, cache time, and encoded normalized card envelope.

Stable source IDs carry SwiftData uniqueness constraints. Array-valued search fields are encoded into delimiter-bounded, sorted, deduplicated scalar indexes so a lookup for ID `1` cannot match ID `10`. The normalized envelope remains the authoritative row body; projections are replaceable query accelerators.

## Writes and failure guarantees

`replace(_:)` first validates every identifier and hash, validates every persistence envelope, decodes the payload according to its declared kind, and rejects invalid stable IDs. No context mutation happens during this stage.

Within a batch, the last document for a payload kind and stable source ID wins. Prepared records are then applied in deterministic key order inside one SwiftData transaction. An existing row with the same content hash is left untouched, preserving its cache timestamp. Changed rows are updated in place and new IDs are inserted. Any transactional error triggers rollback, retaining every previously valid row.

`removeAll()` transactionally deletes all four model types. `LocalCatalogContainer.deleteStore(at:)` removes the store plus SQLite write-ahead-log sidecars after the active container has been released; a new container at that location starts empty without a migration dependency.

## Read behavior

- Protocol fetches return validated stored documents by record identifier in deterministic identifier order. An empty identifier list returns the full mirror.
- Creature queries sort by numeric source index, then normalized name. Search matches normalized name or source number; generation and type filters are exact.
- Evolution lookup uses exact chain-member IDs and chooses the lowest chain source ID if corrupt external data ever associates a creature with multiple chains.
- Related-card lookup uses exact related creature IDs, never name matching. Optional search matches normalized card name or collector number. Results sort by set ID, collector number, and card source ID.

All typed query results are decoded from stored normalized envelope bytes. Persistence models never escape as domain or view-state values.

## Verification contract

Unit coverage uses both in-memory and on-disk model containers. It proves insertion and retrieval of every model type, stable-ID update, unchanged-hash skipping, deterministic duplicate resolution, index/search/filter/evolution/related-card queries, batch rejection with last-valid retention, full deletion, disk persistence, store-file deletion, and empty recreation.
