# App Shell and Design-System Specification

## Typed source

`InteractionConstants.standard`, `MotionConstants.standard`, and `DesignConstants.standard` translate the approved plan and mockup into platform-neutral value types. SwiftUI views should consume these values rather than restating literals.

## Interaction

- Carousel commit and panel-open thresholds are 22% of the relevant dimension.
- Panel close threshold is 12% of app height.
- Visual carousel travel is 82% of finger travel, with at most 6% scale reduction.
- A flick is under 280 ms and over 34 points.
- Panel progress reaches one over 42% of app height.
- Direction detection, click suppression, and horizontal-wheel thresholds are 6, 8, and 20 points respectively.

Every gesture must retain a visible-control and accessibility-action equivalent when its feature is implemented.

## Motion

The standard and panel timing curves preserve the reference control points. Canonical durations cover the 460 ms carousel, 420 ms panel/modal return, 480 ms shuffle, 180 ms scrim, 150 ms quick control, and 540 ms staggered entrance behaviors. Reduced Motion uses a 1 ms fade duration and later feature work must remove travel, parallax, repeating hints, and stagger.

## Visual tokens

`DesignConstants` groups palette, typography, spacing, shape, shadow, and responsive layout tokens. It preserves the 4/8/12/24/48/80-point scale, 16-point phone and 64-point large-layout margins, 8/24-point primary radii, tinted modal shadow, two-column phone portrait grid, and three-column large-layout grid.

The color type stores normalized RGBA channels rather than parsing strings at render sites. Font families and semantic sizes are centralized; platform font loading and fallbacks remain the responsibility of the later design-system implementation task.

## Current composition

`CatalogHomeView` is the root state machine and consumes the coordinator-backed `CatalogViewModel`. It renders loading, empty-install, offline, incompatible-schema, ready, and stale states. The ready path contains the responsive lazy launcher grid, region/filter layer, local search by name/number/generation/type, and a deterministic Surprise Me reorder. `CreatureDetailView` provides the artwork/metadata surface and three accessible actions: Field Guide, Evolution, and Related Cards. The latter layers use native sheets with scrim/material treatment, cancellable presentation, and a static card viewer; no prices, favorites, collection controls, tilt, glare, or foil simulation are present.

The app stores the appearance preference in `AppStorage("appearance")` (`dark`, `light`, or `system`). Tiles expose combined VoiceOver labels and large hit targets, while every gesture path has a visible button equivalent. Preview launch mode (`BATTLE_CARD_DEX_USE_PREVIEW=1`) gives UI tests deterministic six-entry content without contacting CloudKit.
