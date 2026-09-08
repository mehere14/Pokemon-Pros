# Foil texture inspection

This folder contains externally hosted foil-map samples downloaded for technical and provenance inspection. These files are reference inputs and are not included in the application target.

Source URLs are recorded in `sources.tsv`. Recreated, original assets must live separately and document their generation method.

## Findings

The CDN samples are 366×512 RGBA images aligned to individual cards. They contain card borders, rules text, symbols, and character-shaped exclusion regions. They are therefore card-specific material maps, not generic seamless textures. No public reuse license was found during this inspection, so their status remains reference-only.

The reference implementation also has generic texture images in its own `public/img` folder. Those include glitter/grain noise, etched geometric patterns, interference patterns, and three aligned cosmos layers. They provide spatial frequency and breakup; CSS gradients provide most of the changing colour, and the per-card maps control placement.

## Original prototype

`original-prototypes/foil-microtexture-atlas-v1.png` was generated with the built-in image-generation tool as an exploratory 2×2 atlas of grayscale diffraction grain, glitter, etched lines, and cloudy interference. It is not approved for app use: the diffraction quadrant is mostly empty and seamless tiling has not been verified. The deterministic procedural functions in `BattleCardDex/Features/CardFinish.metal` are currently the safer original source for those signals.

Prompt used:

> Generate a seamless grayscale optical texture atlas divided into four equal quadrants: fine holographic diffraction grain, sparse multi-scale glitter, dense etched diagonal guilloche lines, and soft cloudy interference noise. Make it a material data map with no card artwork, characters, text, logos, borders, color, perspective, or watermark.
