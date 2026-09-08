# Domain and Normalization Specification

## Scope

This module defines immutable, provider-independent values for creatures, forms, statistics, moves, encounters, recursive evolution families, and battle cards. It also owns the one-way translation from loader response shapes into versioned catalog payloads and from catalog payloads into domain values.

It does not implement local SwiftData storage, CloudKit codecs, repositories, or feature view models. Those modules consume this contract in later tasks without reusing its types as their own records or state.

## Type boundaries

The data path is intentionally one way:

`loader JSON → Loader…DTO → Catalog…Payload → CatalogPersistenceEnvelope → persistence record → domain value → feature view state`

- `LoaderDTOs.swift` contains `Decodable` provider-shaped DTOs. They tolerate missing, null, extra, and unknown fields. They are loader inputs only, are not `Encodable`, and never conform to the normalized-payload protocol.
- `NormalizedCatalogPayloads.swift` contains schema-versioned creature, evolution, and card payloads. These are the only values accepted by `CatalogPersistenceEnvelope`.
- `CatalogDocument` accepts an encoded `CatalogPersistenceEnvelope`, not arbitrary response bytes. Reading a document validates that the outer envelope exists and that its schema and payload kind match before decoding.
- CloudKit record fields and SwiftData `@Model` classes are separate persistence concerns. They store validated envelope bytes and query metadata; they must not become DTOs or domain values.
- `DomainModels.swift` contains immutable `let`-only values. Domain values have no CloudKit, SwiftData, provider-response, observation, loading, selection, or presentation dependencies.
- Feature view state is constructed from domain values and remains feature-owned. Views never decode DTOs or persistence envelopes.

This separation prevents a provider response from being accepted as a stored catalog document and prevents persistence or view concerns from changing the stable domain contract.

## Domain contracts

The creature contract comprises `CreatureSummary`, `CreatureProfile`, `CreatureForm`, and `CreatureStats`. Related lazy data uses `MoveSummary`, `MoveDetail`, and `Encounter`. Evolution is recursive through `EvolutionChain`, `EvolutionNode`, and `EvolutionRequirement`; it does not assume a fixed number of stages. Cards use `BattleCardSummary` and `BattleCardDetail`, and intentionally contain no pricing fields.

All domain values conform to `Codable`, `Equatable`, `Hashable`, and `Sendable`. Arrays represent deterministic normalized order rather than provider response order.

## Normalization rules

- Source integer identifiers must be positive. IDs embedded in resource URLs are parsed from the final numeric path component. Required string IDs are trimmed, nonempty, and limited to stable identifier punctuation.
- Names, types, version groups, learning methods, locations, items, and other machine-queryable labels become lowercase hyphen-separated values. Duplicate normalized values are removed and results are sorted.
- Display names are derived from normalized names by replacing separators with spaces and capitalizing components.
- Source height in decimetres becomes metres; source weight in hectograms becomes kilograms. Negative or missing measurements become unavailable rather than fabricated values.
- Missing and null optional values remain absent. Invalid optional URLs, numeric strings, and unsafe optional text are omitted. Missing or invalid required IDs and required text fail mapping.
- Evolution nodes are decoded recursively. Every supplied alternative detail remains a distinct requirement, while simultaneous fields within one detail remain together. Supported conditions include trigger, level, item, held item, trade species, happiness, affection, beauty, time, location, weather, relative physical statistics, gender, known move and move type, party species and type, and upside-down-device state.
- Branch order from the recursive source is retained; derived member IDs are unique and sorted.

## Text safety

`NeutralTextSanitizer` folds case and accents, removes punctuation for comparison, and detects restricted brand variants even when mixed case, accented, punctuated between letters, or embedded in a larger phrase. Unsafe optional prose is omitted. A caller explicitly requesting a neutral label receives `Creature`; required unsafe catalog text fails mapping.

The restricted comparison token is assembled from Unicode scalars, so scanner inputs and compiled string tables do not contain a literal restricted spelling. Sanitization happens before normalized payload construction. The Release source/product compliance gate remains an independent second line of defense.

## Verification

Task 6 was verified on September 4, 2026 with a synthetic, sanitized, provider-shaped fixture. Tests cover missing, null, extra, and unknown fields; DTO-to-catalog and catalog-to-domain mappings; canonical measurements, names, types, IDs, version groups, and optional values; recursive branches; no-evolution families; alternative and simultaneous evolution requirements; sanitizer case/accent/punctuation/embedding behavior; unsafe required and optional text; and rejection of raw response bytes at persistence.

Verification commands:

```sh
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Debug -destination "platform=iOS Simulator,id=A7480CE3-3EAD-404E-A302-9C8A78384C5E" -derivedDataPath /tmp/BattleCardDex-Task6-TestRun CODE_SIGNING_ALLOWED=NO -only-testing:BattleCardDexTests test
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Task6-Final-Debug CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Release -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Task6-Final-Release CODE_SIGNING_ALLOWED=NO clean build
python3 Scripts/terminology_compliance.py all --root . --product "/tmp/BattleCardDex-Task6-Final-Release/Build/Products/Release-iphonesimulator/Battle Card Dex.app"
```

The complete unit bundle passed 29 tests. Both clean builds and the combined source/Release-product terminology scan passed.
