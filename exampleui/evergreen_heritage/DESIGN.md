---
name: Evergreen Heritage
colors:
  surface: '#faf9f7'
  surface-dim: '#dadad7'
  surface-bright: '#faf9f7'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f4f1'
  surface-container: '#eeeeeb'
  surface-container-high: '#e8e8e6'
  surface-container-highest: '#e3e2e0'
  on-surface: '#1a1c1b'
  on-surface-variant: '#424843'
  inverse-surface: '#2f312f'
  inverse-on-surface: '#f1f1ee'
  outline: '#727972'
  outline-variant: '#c2c8c1'
  surface-tint: '#476551'
  primary: '#092717'
  on-primary: '#ffffff'
  primary-container: '#203d2b'
  on-primary-container: '#87a891'
  inverse-primary: '#adcfb6'
  secondary: '#556158'
  on-secondary: '#ffffff'
  secondary-container: '#d8e6da'
  on-secondary-container: '#5b675e'
  tertiary: '#38181b'
  on-tertiary: '#ffffff'
  tertiary-container: '#512d30'
  on-tertiary-container: '#c69497'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#c9ebd2'
  primary-fixed-dim: '#adcfb6'
  on-primary-fixed: '#032111'
  on-primary-fixed-variant: '#304d3b'
  secondary-fixed: '#d8e6da'
  secondary-fixed-dim: '#bccabe'
  on-secondary-fixed: '#131e17'
  on-secondary-fixed-variant: '#3d4a41'
  tertiary-fixed: '#ffdadb'
  tertiary-fixed-dim: '#efb9bc'
  on-tertiary-fixed: '#301215'
  on-tertiary-fixed-variant: '#633c3f'
  background: '#faf9f7'
  on-background: '#1a1c1b'
  surface-variant: '#e3e2e0'
typography:
  headline-lg:
    fontFamily: Domine
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Domine
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-md:
    fontFamily: Noto Serif
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  label-md:
    fontFamily: Source Serif 4
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.4'
    letterSpacing: 0.02em
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
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin: 24px
---

# Evergreen Heritage Design System

## Brand & Style
Evergreen Heritage evokes a sense of timeless reliability, organic growth, and scholarly refinement. The brand identity is grounded in the natural world, targeting an audience that values depth, stability, and high-quality craftsmanship. 

The design style is **Modern Academic**, blending the structural clarity of a professional system with the warmth of traditional editorial design. It utilizes a palette of forest greens and earthy tones to create a calm, focused environment that feels both established and approachable.

## Colors
The color palette is inspired by natural landscapes and heritage materials.

- **Primary (#5f7e69):** A muted sage green used for primary actions and key brand moments, providing a soft but clear focal point.
- **Secondary (#6d7a70):** A desaturated slate green for supporting UI elements and accents.
- **Tertiary (#512d30):** A deep black-cherry red used sparingly for contrast, critical alerts, or meaningful highlights.
- **Neutral (#767775):** A balanced stone grey used for surfaces, borders, and secondary text to maintain a grounded, professional atmosphere.

The system uses a **Light Mode** default, emphasizing clean, parchment-like backgrounds with high legibility.

## Typography
The typography is entirely serif-based to reinforce the scholarly and traditional brand personality.

- **Headlines (Domine):** Chosen for its friendly but commanding presence, Domine provides excellent readability and a classic editorial feel.
- **Body (Noto Serif):** A highly legible serif font designed for long-form reading, ensuring comfort during extended interaction.
- **Labels (Source Serif 4):** Used for functional elements and UI metadata, offering a refined and distinct appearance even at small sizes.

The type hierarchy relies on generous line heights and traditional weight distributions to guide the reader through complex information.

## Layout & Spacing
The system employs a **Fluid Grid** model with a focus on generous white space and rhythmic verticality.

- **Rhythm:** Based on an 8px (multiplier of 2) spacing unit, ensuring consistent alignment across all components.
- **Margins & Gutters:** Mobile layouts use a 16px margin, while desktop layouts expand to 24px or 32px to allow the content to "breathe."
- **Philosophy:** Layouts should prioritize a single-column reading experience where possible, mimicking the layout of a well-typeset book or academic journal.

## Elevation & Depth
Depth is conveyed through **Tonal Layers** and subtle, organic shadows.

- **Surfaces:** We use light, stone-tinted containers to separate content modules rather than heavy shadows.
- **Shadows:** When necessary, shadows are extremely soft and diffused, using a slight green-grey tint (#767775 at low opacity) to feel integrated with the background rather than floating above it.
- **Outlines:** Low-contrast borders in neutral tones are preferred for defining input fields and card boundaries.

## Shapes
The shape language is **Rounded**, moving away from the harshness of sharp corners to feel more organic and inviting.

- **Standard Elements:** Components like buttons and input fields use a 0.5rem (8px) corner radius.
- **Large Elements:** Cards and modals use a 1rem (16px) or 1.5rem (24px) radius to emphasize their role as distinct containers.
- **Philosophy:** The curves are purposeful—not quite pill-shaped, but soft enough to contrast the structured serif typography.

## Components
Consistent styling across the component library:

- **Buttons:** Features a 0.5rem rounded corner. Primary buttons use the Sage Green (#5f7e69) with white serif text. Secondary buttons use an outline style.
- **Cards:** Defined by soft 1rem rounded corners and subtle neutral borders. Padding is generous (24px) to maintain the "Modern Academic" feel.
- **Input Fields:** Use Source Serif 4 for labels and Noto Serif for user input. Borders are muted stone-grey, softening on focus to a primary sage green.
- **Chips & Tags:** Use a semi-rounded shape (0.5rem) with low-saturation background tints to indicate categories without distracting from the main text.
- **Lists:** Separated by thin, light-grey rules with generous vertical padding to ensure high legibility.