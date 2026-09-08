# Test Harness and Deterministic Fixtures Specification

## Scope

This module provides deterministic seams for catalog, persistence, image, time, retry, and CloudKit-isolation tests. It deliberately does not define the domain types, provider DTOs, record codecs, or production store implementations owned by later tasks.

## Service contracts

`CatalogServiceContracts.swift` defines the concurrency-safe boundaries used by repositories:

- `PublicCatalogStore` fetches normalized `CatalogDocument` values from the shared public catalog.
- `LocalCatalogStore` fetches, atomically replaces, and removes normalized local documents.
- `ImageRepository` returns image bytes without exposing transport or cache details.
- `CatalogClock` and `RetryScheduler` make time and retry delays substitutable.

The boundary uses `CatalogDocument` rather than feature models. Task 6 owns domain models and mapping; Task 8 owns record codecs. `ServiceResponse` carries freshness and per-identifier failures independently from its value, while `CatalogServiceError` represents offline and throttled failures. Cancellation remains Swift structured cancellation (`CancellationError`).

## Scripted fakes

The unit-test target contains actor-backed fakes for every protocol. The reusable `ScriptedServiceState` supports:

- success;
- empty success;
- stale success;
- offline failure;
- throttle failure with a deterministic retry delay;
- partial success with failed identifiers; and
- cancellation.

Every fake consumes a declared script in order and records received calls. An exhausted script fails immediately, preventing an accidental live dependency or an underspecified test. The fake clock advances logical time without sleeping, and the retry scheduler records attempts and can cancel a selected attempt.

## Fixture policy

The normalized JSON fixtures are under `BattleCardDexTests/Fixtures`, which Xcode includes only in `BattleCardDexTests.xctest`:

- `creature-index-1-6.json` contains a stable, sorted index for IDs 1 through 6.
- `evolution-cases.json` contains a three-edge branching chain and an explicit no-evolution chain.
- `battle-cards.json` contains standard, illustrated, and promotional card examples.

The first three fixtures are small authored normalized payloads, not captured provider responses. Task 6 adds `normalization-cases.json`, a synthetic, sanitized provider-shaped test input that exercises optional and unknown-field decoding without copying a raw upstream response. Fixtures contain no provider envelopes, headers, legal copy, or prohibited branding. Captured upstream responses must remain outside the repository and all shipping target memberships. Fixture decoding uses explicit `Codable` shapes and is tested for repeatable equality and sorted-key re-encoding.

## Persistence and CloudKit isolation

`InMemoryTestStore.makeContainer()` creates a new `ModelContainer` with `isStoredInMemoryOnly: true` for each invocation. Tests must create a fresh container rather than share a static container.

`DevelopmentCloudRecordNamespace` accepts only `.developmentPublicDatabase`. It rejects `.productionPublicDatabase` with `productionAccessDenied` and rejects `.fake` because a fake service does not name a CloudKit deployment environment. A caller-provided run/worker identifier is sanitized into a deterministic record prefix so concurrent Development integration runs cannot collide. Unit tests use fake services and do not contact CloudKit.

## Verification

Task 5 was verified on September 4, 2026 with:

```sh
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/BattleCardDex-Task5-Tests CODE_SIGNING_ALLOWED=NO test -only-testing:BattleCardDexTests
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Task5-Debug CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Release -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Task5-Release CODE_SIGNING_ALLOWED=NO clean build
python3 Scripts/terminology_compliance.py all --root . --product "/tmp/BattleCardDex-Task5-Release/Build/Products/Release-iphonesimulator/Battle Card Dex.app"
```

The unit suite and both builds passed. The terminology gate passed. Bundle inspection found all three JSON fixtures in `BattleCardDexTests.xctest` and none in the standalone Debug or Release application bundle.
