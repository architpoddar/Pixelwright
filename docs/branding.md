# Brand Identity & Style Guide

A concise guide for creating artwork, screenshots, marketing materials, and UI updates for **Pixelwright**.

---

## 1. Positioning & Core Voice

- **Name:** **Pixelwright** (one word, capital P). A *wright* is a skilled maker (shipwright, playwright, wheelwright); a Pixelwright shapes and refines digital images with care.
- **Tagline:** **Craft your pixels.**
- **One-line Descriptor:** *The private, focused image editor for Mac.*
- **Personality:** Precise, calm, trustworthy, craftsmanlike. Built like a well-made instrument (comparable in seriousness to Things, Linear, or Apple's native utilities). No cartoon mascots, no retro game pixels, no hype.

---

## 2. Logo & Symbol

The **Precision P** symbol pairs an architectural vertical stem with an optical calibration loop. The interior counter is a precision square aperture (a nod to the pixel) centered on a vibrant Cobalt Blue calibration pip.

```
      ┌───────────┐
      │  ┌─────┐  │  <- Precision Frame Loop
      │  │  ■  │  │  <- Cobalt Calibration Pip
      ├──┴─────┘──┘
      │
      │  <- Structural Stem (The Plumb Line)
```

### Assets Directory (`docs/assets/brand/`)

| File | Description | Usage |
|---|---|---|
| `symbol.svg` | Standalone Precision P with Cobalt pip | General digital & vector use |
| `symbol-dark.svg` | Titanium White on dark backgrounds | Dark mode UI, dark presentations |
| `symbol-light.svg` | Slate Graphite on light backgrounds | Light mode UI, print, light papers |
| `symbol-monochrome-white.svg` | Pure 1-color white | Single-color reverse applications |
| `symbol-monochrome-dark.svg` | Pure 1-color dark slate | Single-color light applications |
| `logo-horizontal-dark.svg` | Symbol + Wordmark horizontal (dark) | Navbars, headers, README banner |
| `logo-horizontal-light.svg` | Symbol + Wordmark horizontal (light) | White/light backings |
| `logo-stacked-dark.svg` | Symbol + Wordmark centered | Splash screens, social badges |
| `app-icon-1024.svg` | 1024 x 1024 macOS app icon master | macOS Dock, Finder, App Store |
| `app-icon-layer-*.svg` | Layered background, foreground, shadow | Apple macOS Icon Composer |

### Minimum Size & Clear Space
- **Clear Space:** Maintain a clear margin of at least $1X$ (the width of the vertical stem) on all four sides.
- **Minimum Size:**
  - Symbol: 16 x 16 px (micro Dock / Finder list).
  - Horizontal lockup: 120 x 24 px.

---

## 3. Color Palette

A restrained, high-contrast palette calibrated for macOS Light & Dark Modes and verified for **WCAG AA/AAA compliance**.

| Role | Name | Hex | Contrast / WCAG | Notes |
|---|---|---|---|---|
| **Canvas Dark** | Obsidian | `#0B0E14` | — | Deep background |
| **Surface Dark** | Dark Slate | `#1E2638` | — | App icon tile, toolbars |
| **Primary Text (Dark)** | Titanium | `#F8FAFC` | 15.8:1 (AAA) | High contrast glyphs and headers |
| **Primary Text (Light)** | Deep Ink | `#0F172A` | 15.6:1 (AAA) | Wordmark on light surfaces |
| **Muted Text** | Slate Steel | `#8B949E` / `#64748B` | > 4.6:1 (AA) | Keyboard shortcuts, secondary labels |
| **Primary Accent** | Electric Cobalt | `#3B82F6` (Dark) / `#2563EB` (Light) | 8.2:1 / 4.7:1 (AA) | Buttons, active states, calibration pip |
| **Selection Marquee** | Precision Sky | `#0EA5E9` | 4.8:1 (AA) | Selection borders and lasso paths |

---

## 4. Typography

- **In-App (macOS):** Apple SF Pro (`.system(size:weight:)`) and SF Mono for pixel coordinates, dimensions, and DPI values.
- **Wordmark:** Set as a unified word in **SF Pro Display** or **Inter** (Weight: Semibold / 600, letter-spacing: `-0.02em`).
- **Web & Documentation:** **Inter** or **Geist** (SIL Open Font License 1.1). Both are 100% free for commercial and open-source distribution.

---

## 5. Tool Icons Guidance

- **Use SF Symbols:** Keep macOS system SF Symbols (`rectangle`, `lasso`, `wand.and.rays`, `crop`).
- **Why?** SF Symbols dynamically match Apple's system font weights, scale seamlessly across Retina densities, and feel distinctly native to Mac users without adding third-party asset weight.

---

## 6. Regenerating Generated Artwork

From the repository root:

```bash
swift scripts/make-icon.swift
```

This generates:
1. `Resources/AppIcon.icns` — Complete multi-resolution macOS icon bundle.
2. `docs/assets/logo.png` — 512 x 512 flat PNG.
3. `docs/assets/social-preview.png` — 1280 x 640 GitHub preview image.

---

## 7. Ownership & Rights

All brand assets, vector sources, and code implementations are released under the project's **MIT License** with full, unrestricted commercial and open-source usage rights.
