# Build, Configuration, and Compliance Specification

## Baseline

Baseline captured on September 4, 2026 before implementation changes.

- Source snapshot: commit `38bc8e93c691ceb16d0a12d366229ab16e3b80d4` from the existing local Battle Card Dex repository. The selected workspace has read-only Git metadata, so the restored project files appear as untracked and must be treated as user-owned source material.
- Xcode: 26.6 (`17F113`).
- Swift: 6.3.3 (`swiftlang-6.3.3.1.3`), arm64 macOS toolchain.
- Project: `Pokemon Pros.xcodeproj`; Debug and Release configurations.
- Scheme: `Pokemon Pros`.
- Targets: app, unit tests, and UI tests under the original `Pokemon Pros` names.
- App bundle ID: `com.askcruit.Pokemon-Pros`; automatic signing; development team `PMF38PJVT3`.
- Deployment: iOS 26.5; iPhone and iPad device families. The starter project also advertises macOS and visionOS and must be narrowed during the rename task.
- Entitlements: development push notifications and CloudKit service are enabled, but the CloudKit container identifier list is empty.
- Build warning: App Intents metadata extraction is skipped because the starter app has no App Intents dependency.

`Plan/`, `Design Mockup/`, and `Reference/` are reference-only. The Xcode project has synchronized root groups only for the three app/test source directories, its explicit Resources phases are empty, and the baseline app bundle contains none of the reference directories.

The baseline results below describe the untouched starter and early rename checkpoints. For the current implementation and host-level verification limits, see `Documentation/verification-status.md`; that record supersedes historical simulator results when the current CoreSimulator service is unavailable.

## Non-interactive verification commands

All generated build data stays outside the repository. Replace `iPhone 17 Pro` only when the project adopts another documented CI simulator.

```sh
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Build CODE_SIGNING_ALLOWED=NO clean build

xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/BattleCardDex-Tests CODE_SIGNING_ALLOWED=NO test -only-testing:BattleCardDexTests

xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/BattleCardDex-UITests CODE_SIGNING_ALLOWED=NO test -only-testing:BattleCardDexUITests

xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Release -destination "generic/platform=iOS" -archivePath /tmp/BattleCardDex.xcarchive CODE_SIGNING_ALLOWED=NO archive

python3 Scripts/terminology_compliance.py source --root .

python3 Scripts/terminology_compliance.py product --path "/tmp/BattleCardDex.xcarchive"

python3 Scripts/terminology_compliance.py all --root . --product "/path/to/Battle Card Dex.app"

python3 -m unittest discover -s Scripts -p "test_*.py" -v
```

## Renamed shipping configuration

- Project and shared scheme: `Battle Card Dex.xcodeproj` and `Battle Card Dex`.
- Targets and products: `Battle Card Dex.app`, `BattleCardDexTests.xctest`, and `BattleCardDexUITests.xctest`.
- Swift entry point: `BattleCardDexApp` in `BattleCardDex/BattleCardDexApp.swift`.
- Display name, bundle name, executable, and process product name: `Battle Card Dex`.
- Bundle identifiers: `com.askcruit.Battle-Card-Dex`, `com.askcruit.Battle-Card-DexTests`, and `com.askcruit.Battle-Card-DexUITests`.
- CloudKit container: `iCloud.com.askcruit.Battle-Card-Dex`.
- Supported platforms: iOS device and iOS Simulator; iPhone and iPad device families.

## Baseline results

- Clean generic iOS Simulator SDK build: passed.
- Built bundle inspection: passed. It contains only the generated application files and no `Plan/`, `Design Mockup/`, or `Reference/` content.
- Unit suite on iPhone 17 Pro (iOS 26.5): passed (`Pokemon_ProsTests/example()`).
- UI suite on iPhone 17 Pro (iOS 26.5): passed (four launch-orientation cases, the starter interaction test, and launch-performance test). Xcode emitted transient LLDB version-store and two simulator-clone process-launch warnings, but the primary clone completed every selected UI test and `xcodebuild` returned `TEST SUCCEEDED`.

## Task 2 verification results

- Renamed shared-scheme clean simulator build: passed.
- Renamed unit suite: passed (`BattleCardDexTests/example()`).
- Renamed UI suite: passed six tests with zero failures. Its launch logs identify the tested application as `com.askcruit.Battle-Card-Dex`.
- Built metadata: `CFBundleDisplayName`, `CFBundleName`, and `CFBundleExecutable` are `Battle Card Dex`; `CFBundleIdentifier` is `com.askcruit.Battle-Card-Dex`.
- Shipping Swift, plist, entitlement, asset metadata, project metadata, and scheme scans contain neither prohibited spelling.
- `strings` scans of the main Mach-O executable and every file in the complete `.app` bundle contain neither prohibited spelling.
- Unsigned Release iOS archive: passed. The built app and archive contain no `Plan/`, `Design Mockup/`, or `Reference/` directory or file.

## Compliance boundaries

- Development and automated tests must never mutate Production CloudKit.
- The loader and its credentials must never be linked into or copied into the shipping application.
- Release validation must scan shipping source, metadata, bundle resources, and executable strings for prohibited terminology and secrets.
- Planning documents and immutable design references are inputs to implementation, never shipping resources.

## Terminology compliance gate

`Scripts/terminology_compliance.py` is the permanent release validator. It constructs both prohibited spellings from Unicode scalar values, so neither spelling is authored literally in the validator or its tests. Comparisons use NFC normalization plus Unicode case folding.

The source mode scans filenames and UTF-8 content for Swift, Objective-C/C/C++, JavaScript/TypeScript, plist, entitlement, Xcode project, scheme, localization, asset-catalog, JSON, interface, configuration, and shell inputs. Asset and localization paths are also validated. Repository traversal excludes exactly the two checklist-approved non-shipping roots: `Plan/` and `Design Mockup/`. `Reference/` is not exempt and is scanned when it contains a supported source or metadata input.

The product mode recursively checks a generated `.app`, `.xcarchive`, or executable. It checks product paths and readable UTF-8 files directly, and uses the platform `strings` utility for binary inputs, including the Mach-O executable. Missing requested product paths are failures rather than silent skips. The `all` command combines a source scan with any number of `--product` inputs.

The application target has two always-run phases that activate for the Release configuration:

1. `Validate Neutral Terminology` runs before compilation and blocks the build when source or metadata is noncompliant.
2. `Validate Built Product Terminology` runs after Sources, Frameworks, and Resources and checks the generated application plus executable strings.

Because Archive uses Release, both phases run for command-line and Xcode archives as well as ordinary Release builds. Release disables Xcode user-script sandboxing for this target so the first phase can inspect every in-scope repository input; Debug retains the project default.

## Task 3 verification results

- Six deterministic scanner tests passed. They cover exact relative file and line diagnostics, mixed-case accented and unaccented variants, unrelated partial-sequence false positives, prohibited source and asset names, exclusion boundaries, and fail-then-pass behavior after fixture removal.
- A disposable root JSON fixture containing a prohibited uppercase value on line 2 caused the actual Release build phase to fail with `ComplianceBlockFixture.json:2: prohibited terminology`; Xcode returned exit status 65. The fixture was then removed.
- The clean standalone source scan passed after fixture removal.
- A clean unsigned Release iOS Simulator build passed and logged successful execution of both terminology phases.
- The standalone combined source and completed `.app` scan passed.
- The unsigned generic-device Archive succeeded and logged successful execution of both terminology phases.
- A standalone recursive scan of the completed `/tmp/BattleCardDex-Task3.xcarchive`, including archive metadata, its application bundle, Mach-O executable, and dSYM contents, passed.

## Task 4 configuration verification

The shipping target now has one typed configuration composition root. Its Debug and Release selection is centralized in `AppConfiguration.current`; tests request `.test` directly. No feature source performs build-environment checks.

The app configuration intentionally exposes only public CloudKit identifiers. It has no upstream host, provider endpoint, API-key, server-key, private-key-path, checkpoint, or loader throttling field. Test configuration is enforced as both in-memory and fake-CloudKit, while Release rejects diagnostic logging.

Verification commands use independent derived-data directories and inspect the final optimized simulator application:

```sh
xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath /tmp/BattleCardDex-Task4-Tests CODE_SIGNING_ALLOWED=NO test -only-testing:BattleCardDexTests

xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Task4-Debug CODE_SIGNING_ALLOWED=NO clean build

xcodebuild -project "Battle Card Dex.xcodeproj" -scheme "Battle Card Dex" -configuration Release -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/BattleCardDex-Task4-Release CODE_SIGNING_ALLOWED=NO clean build

python3 Scripts/terminology_compliance.py all --root . --product "/tmp/BattleCardDex-Task4-Release/Build/Products/Release-iphonesimulator/Battle Card Dex.app"
```

In addition to terminology validation, inspect readable strings from every regular Release bundle file for both known loader provider host fragments and generic credential/private-key-path markers. Any match fails Task 4 release validation.

### Task 4 results

- The targeted Swift Testing suite passed 12 tests with zero failures. It exercised each environment's complete expected profile, shared catalog/cache values, interaction/motion/design reference values, and profile construction across all declared environments.
- Invalid zero/negative cache budgets, a memory budget exceeding disk, negative request/resource timeouts, and unsupported schema versions `0`, `2`, and `99` were rejected with their typed validation errors.
- Test construction rejected Development CloudKit and persistent storage; Release construction rejected diagnostic logging.
- Clean generic iOS Simulator builds passed independently for Debug and Release.
- The combined source and optimized Release `.app` terminology scan passed.
- Recursive readable-string inspection of every regular file in the Release `.app` found no known upstream provider host, API-key, CloudKit server-key, private-key, private-key-path, or loader-checkpoint marker.
- The same upstream/credential scan passed across shipping Swift, plist, and entitlement source.
- A shipping Swift scan found exactly one environment compiler condition: the `AppConfiguration.current` composition-root selector. Feature source contains no Debug/Test/Release compiler selection.
