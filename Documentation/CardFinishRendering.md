# Card finish rendering experiment

The Debug lab now applies an original Metal colour shader to the artwork. The previous Canvas lines, circles, diamond outlines and full-surface colour overlays were removed: they resembled decoration over the image rather than a foil surface.

The local reference's useful visual principles are dense texture, independent movement of spectral bands and highlights, and spatially limited foil. The new implementation uses procedural grain, etched diffraction lines, opposing light lobes, angle-selected sparkles and family-specific finish functions. A bounded screen reflection preserves the underlying image; turning effects off returns the original pixels. No animation clock runs on inactive cards.

This is an approximation, not a pixel-matched port. The reference uses layered texture images and card-specific foil masks that are absent here. Generic masks cannot preserve exact character silhouettes or embossed printing. For that fidelity, the next asset step is original or appropriately licensed foil maps and per-card masks. CSS itself is not required for the effect; native pixel-level composition provides the necessary rendering control.

`CardFinish.metal` family numbers correspond to `DebugCardEffectFamily.allCases` in declaration order. Keep these synchronized when extending the lab. The shader source is excluded from Release builds. Xcode's optional Metal Toolchain component is required for Debug builds.

Visual acceptance must include artwork loaded from the image provider, effects off/on, center and corner touch positions, dark and light artwork, and iPhone/iPad scrolling. Compilation or a navigation smoke test alone does not establish visual equivalence or performance.
