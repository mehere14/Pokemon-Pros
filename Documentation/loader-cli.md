# Loader CLI Specification

## Boundary and invocation

The catalog loader is a standalone Swift Package Manager product in `Loader/`. Its executable product is `battle-card-dex-loader`; the iOS Xcode project does not reference the package or its module. This boundary keeps server-to-server credentials, provider adapters, checkpoints, and rate-limit policy out of the shipping dependency graph.

Build and test it from the repository root with:

```sh
cd Loader
swift test
swift run battle-card-dex-loader validate
swift run battle-card-dex-loader dry-run
```

The scaffold accepts these commands:

```text
seed --range LOWER...UPPER
sync --range LOWER...UPPER
sync --all
validate
dry-run
```

Ranges are inclusive, positive, and must be ascending. Parsing errors are reported as JSON with exit code `2` (usage). Preflight failures use `3`, catalog validation failures use `4`, runtime failures use `5`, and success is `0`. Range-based `seed` and `sync` use the concrete provider pipeline and Development CloudKit adapter; `sync --all` remains gated until the full-catalog phase. `validate` is a Development/public, signed read-only CloudKit audit; it never invokes provider endpoints, the loader cache, or `records/modify`.

## Secret resolution

`LoaderSecretResolver` applies values in this order:

1. Process environment (the CI override path; CI should inject values from its encrypted secret store).
2. The owner-only, gitignored `.env.local` file used by the local invocation.

The local configuration keys are:

- `BATTLE_CARD_DEX_CARD_SOURCE_API_KEY` (optional; the upstream card source may not require it).
- `BATTLE_CARD_DEX_CLOUDKIT_KEY_ID` (required for `seed`, `sync`, and live `validate`).
- `BATTLE_CARD_DEX_CLOUDKIT_PRIVATE_KEY_PATH` (required for `seed`, `sync`, and live `validate`).

Environment values take precedence over the local file and are held in memory only. The runtime does not query Keychain. `.env.local` must be mode `0600` (or otherwise owner-only) and is excluded by `.gitignore`; the checked-in `.env.example` contains placeholders only. The CloudKit private key must be an existing regular file outside the repository. It is never copied into source, plist, xcconfig, UserDefaults, SwiftData, CloudKit records, fixtures, logs, checkpoints, reports, or an app bundle.

## Reports and redaction

Every invocation emits one sorted JSON `LoaderRunReport` containing the command, status, numeric exit code, ISO-8601 timestamps, optional range, record-count map, and a non-secret error code. Secret-bearing diagnostics must pass through `SecretRedactor`; values and private-key paths are replaced with `[REDACTED]`/`[REDACTED_PATH]`. Reports intentionally contain no credentials or payloads.

## Provider transport and publication

`LoaderHTTPClient` is transport-injected for deterministic tests and uses `URLSessionLoaderTransport` in production. It enforces a minimum request interval, a concurrency ceiling, cancellation checks, pagination-cursor deduplication, bounded exponential backoff with jitter, and `Retry-After` handling. Permanent 4xx responses and malformed JSON are surfaced without retries.

`CatalogPublisher` receives normalized `LoaderRecord` values, fetches existing content hashes, skips unchanged IDs, commits bounded batches, saves a checkpoint after each commit, and writes the manifest last. A failed data batch leaves the active manifest untouched; a subsequent run resumes from the checkpoint without duplicate records. Its service and checkpoint protocols are fakeable, while server credentials are validated as an external key ID plus an existing file outside the repository.

`sync --all` discovers the current species count from the provider rather than baking a release-specific upper bound into the job. It builds and reconciles one National Dex entry at a time. Only after all records for that entry have been confirmed in CloudKit does it atomically add the entry to `.loader-state/sync-all.json`; therefore a crash between the CloudKit write and local checkpoint is recovered by a content-hash lookup and skip. Shared evolution/card records use deterministic IDs and are reconciled safely. After each complete creature bundle, a compact rolling manifest publishes the contiguous available creature count; card IDs are deliberately excluded from that manifest and are discovered by the app through paged `CardCatalogRecord` queries, avoiding a single-record size ceiling. If a later release increases the species count, the existing checkpoint is extended rather than discarded.

The card client sends at most one request at a time. Authenticated runs are paced at five requests/second and receive the provider's default 20,000-request daily allowance; anonymous runs are paced below the provider's 30-request/minute ceiling and are subject to its 1,000-request daily allowance. Both provider clients honor `Retry-After`, use bounded exponential retries for transient failures, and persist every successful GET in `.loader-cache`, so restarts do not spend upstream quota on completed requests. The card client tolerates extended provider outages with twelve attempts and a capped five-minute backoff (roughly twenty-three minutes before a single entry is abandoned), preventing tight restart loops during upstream 5xx incidents.

The current CloudKit schema stores normalized structured records and source image URLs, not `CKAsset` image copies. Consequently, `sync --all` caches all upstream JSON needed to reproduce a record but does not mirror artwork bytes into CloudKit. Mirroring every creature and trading-card image requires a separately budgeted schema/client migration (asset fields, storage/egress sizing, licensing review, and asset-upload receipts); it must not be enabled implicitly by this command.

`CloudKitWebService` implements the concrete Development/public adapter for `records/lookup`, `records/query`, and `records/modify`. `CloudKitRequestSigner` follows Apple's server-to-server request format: SHA-256 of the JSON body, an ISO-8601 timestamp, the operation subpath, and a P-256 ECDSA signature read from the external PEM key. Configuration structurally rejects Production and non-public mutation targets. Live Development authentication, batched publication, manifest gating, and unchanged-record skipping have been verified. The `validate` command uses paginated `records/query` requests to independently count all four record types, verify the deterministic first-30 primary IDs, decode the manifest, verify every returned payload hash, compare manifest hashes/counts to live records, and ensure every primary ID has an evolution membership and related card reference. Its JSON report includes exact catalog payload bytes and exact CloudKit query-response bytes observed during that validation run. Those figures are payload and transfer measurements; CloudKit does not expose its internal index/storage allocation through this API.

## Isolation verification

`LoaderTests` asserts that the Xcode project file has no loader target or path. After an iOS build, verify the product independently:

```sh
rg -n "BattleCardDexLoader|Loader/" "Battle Card Dex.xcodeproj/project.pbxproj" # expected: no matches
find /path/to/Battle\ Card\ Dex.app -iname '*Loader*' -print # expected: no matches
```
