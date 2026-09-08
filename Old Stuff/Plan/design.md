---
name: Electric Burst
colors:
  surface: '#171021'
  surface-dim: '#171021'
  surface-bright: '#3e3648'
  surface-container-lowest: '#120b1c'
  surface-container-low: '#1f182a'
  surface-container: '#241c2e'
  surface-container-high: '#2e2739'
  surface-container-highest: '#393144'
  on-surface: '#ebdef6'
  on-surface-variant: '#ccc7ab'
  inverse-surface: '#ebdef6'
  inverse-on-surface: '#352d3f'
  outline: '#969178'
  outline-variant: '#4a4732'
  surface-tint: '#d9c900'
  primary: '#ffffff'
  on-primary: '#363100'
  primary-container: '#f7e61a'
  on-primary-container: '#6e6600'
  inverse-primary: '#686000'
  secondary: '#ffb595'
  on-secondary: '#581e00'
  secondary-container: '#ef671a'
  on-secondary-container: '#4d1900'
  tertiary: '#ffffff'
  on-tertiary: '#4f0b6d'
  tertiary-container: '#f7d8ff'
  on-tertiary-container: '#8849a6'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#f7e61a'
  primary-fixed-dim: '#d9c900'
  on-primary-fixed: '#1f1c00'
  on-primary-fixed-variant: '#4e4800'
  secondary-fixed: '#ffdbcd'
  secondary-fixed-dim: '#ffb595'
  on-secondary-fixed: '#360f00'
  on-secondary-fixed-variant: '#7c2e00'
  tertiary-fixed: '#f7d8ff'
  tertiary-fixed-dim: '#eab3ff'
  on-tertiary-fixed: '#310048'
  on-tertiary-fixed-variant: '#682986'
  background: '#171021'
  on-background: '#ebdef6'
  surface-variant: '#393144'
typography:
  display-lg:
    fontFamily: Sora
    fontSize: 48px
    fontWeight: '800'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Sora
    fontSize: 36px
    fontWeight: '800'
    lineHeight: '1.1'
  headline-md:
    fontFamily: Sora
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  body-lg:
    fontFamily: Hanken Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-caps:
    fontFamily: Space Grotesk
    fontSize: 12px
    fontWeight: '600'
    lineHeight: '1'
    letterSpacing: 0.1em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 48px
  xl: 80px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 64px
---

## Brand & Style

This design system is built on a foundation of high-energy contrast and tactile depth. It targets dynamic digital experiences—social media, entertainment, or creative tech—where motion and vibrancy are central to the user journey.

The aesthetic direction is **Modern Tactile with an Electric Pulse**. It leverages the "Electric Burst" primary yellow against deep, atmospheric backgrounds to create a sense of glowing interface elements. The style combines the cleanliness of modern SaaS with the expressive energy of vaporwave-adjacent color palettes. Expect a sense of physical weight through soft gradients and subtle inner glows, making digital controls feel touchable and responsive.

## Colors

The palette is anchored by a high-visibility primary yellow (`#f8e71c`), designed to "pop" against a dark, multi-tonal neutral background. 

- **Primary:** Use for high-intent actions and critical highlights.
- **Secondary & Tertiary:** Drawn from the reference image, these warm oranges and deep purples create a sunset-to-midnight gradient spectrum. Use these for secondary buttons, data visualization, and decorative glows.
- **Dark Mode (Default):** Surfaces should utilize deep indigos and plums rather than pure black to maintain a rich, saturated feel.
- **Light Mode:** When in light mode, the vibrant oranges and purples shift to pastel tints, while the primary yellow gains a subtle dark stroke for legibility.

## Typography

The typography system uses a mix of geometric and technical fonts to reinforce the "Electric" brand.

- **Headlines:** Sora provides a futuristic, bold foundation. It should be set with tight letter spacing for large display text to create a high-impact, editorial look.
- **Body:** Hanken Grotesk offers exceptional readability with a contemporary edge, balancing the expressive nature of the headlines.
- **Labels:** Space Grotesk is used for small UI metadata and labels, providing a slight technical/industrial flair that complements the tactile UI elements.

## Layout & Spacing

The design system utilizes a **Fluid Grid** with a strict 8px baseline rhythm. 

- **Desktop:** 12-column grid with generous 64px outer margins to allow the vibrant background gradients to breathe.
- **Mobile:** 4-column grid with 16px margins. 
- **Rhythm:** Spacing between related components (like a card's title and its body) should use the `sm` (12px) unit, while section breaks should use `lg` (48px) or `xl` (80px) to maintain a clean, airy feel despite the heavy color saturation.

## Elevation & Depth

This system moves away from traditional flat design in favor of **Tonal Layers and Atmospheric Glows**.

- **Depth:** Instead of drop shadows, use "Inner Glows" (1px-2px spread) on the top edge of components to simulate a light source from above.
- **Surfaces:** Use semi-transparent background blurs (Glassmorphism) for overlays and navigation bars, allowing the "Electric Burst" gradients to peek through.
- **Shadows:** When shadows are necessary for high-elevation components (like modals), use a tinted shadow based on the Indigo Night color (`#3c1a87`) with a 20% opacity and 40px blur to create a soft, neon-like diffusion.

## Shapes

The shape language is consistently **Rounded**, promoting an approachable and tactile feel. 

- **Standard Elements:** Buttons, inputs, and small cards use a 0.5rem (8px) radius.
- **Large Containers:** Section containers and hero cards use a 1.5rem (24px) radius.
- **Interactive States:** When hovered, interactive elements should subtly "swell" using a transform scale (e.g., scale 1.02) rather than just changing color, emphasizing the tactile nature of the UI.

## Components

### Buttons
- **Primary:** Solid Electric Yellow background with black text. Use a subtle 1px inner highlight on the top edge.
- **Secondary:** Gradient background (Sunset Orange to Deep Plum) with white text.
- **Tertiary/Ghost:** Outline style using the Indigo Night color, shifting to a solid fill on hover.

### Cards
Cards should feature a 1px border with 10% opacity white to define edges against dark backgrounds. Use a background gradient that transitions from a darker Indigo to a lighter Plum to create internal depth.

### Input Fields
Inputs are dark-filled (Void Black) with a 2px bottom-only border in Sunset Orange that glows (box-shadow) when focused.

### Chips & Tags
Pill-shaped with high-contrast fills. For "active" states, use the primary yellow; for "neutral" states, use a semi-transparent purple.

### Additional Elements
- **Glow Traces:** Use long, soft radial gradients behind key call-to-action areas to draw the eye.
- **Progress Bars:** Utilize a linear gradient (Yellow to Orange) to signify "energy" or "completion."