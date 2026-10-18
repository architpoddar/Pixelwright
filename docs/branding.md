# Branding

> **Interim.** The current logo, colors and wordmark are a first pass and are expected to be replaced
> by a professional identity. The structure below (where the brand appears, how to regenerate
> artwork) will still apply.

Short guide for anyone making screenshots, posts or changes that show Pixelwright.

## Name

**Pixelwright**, one word, capital P. A *wright* is a maker (wheelwright, playwright), so a
Pixelwright is someone who builds with pixels.

Tagline: **Craft your pixels.**

One-line description: *A free, open-source image editor for Mac.*

In text, "Pixel" can be set light and "wright" heavy (as in the wordmark), but in running text just
write "Pixelwright".

## Logo

A pixel-art letter **P** on a rounded square, built from white pixels, with one **yellow spark
pixel** in the bowl. The spark is the part people remember: keep it.

- `docs/assets/logo.png`: the app icon at 512 px, for READMEs and posts.
- `docs/assets/social-preview.png`: 1280 x 640, the size GitHub uses for link previews. Upload it
  under *Settings > Social preview* on the repository.
- `Resources/AppIcon.icns`: the macOS app icon, copied into the app by `scripts/make-app.sh`.

Don't stretch, recolor or add effects to the mark.

## Colors

| Name | Hex | Used for |
|---|---|---|
| Indigo | `#4338FF` | Gradient start |
| Violet | `#7B3FF2` | Gradient middle, and the app's accent color (buttons, sliders, highlights) |
| Coral | `#FF6B57` | Gradient end, the "wright" in the wordmark, selection outlines |
| Spark | `#FFD23F` | The single yellow pixel, small highlights |

The signature gradient runs indigo, violet, coral from top-left to bottom-right.

## Where the brand lives in the app

- App icon (Dock, Finder, About).
- Toolbar: a small mark and wordmark at the top left of every window.
- Welcome screen: large mark, wordmark, tagline and the Open and Clipboard buttons.
- About window (Pixelwright > About Pixelwright).
- Accent color across the interface.

The in-app artwork is drawn in SwiftUI (`Sources/Pixelwright/Brand.swift`), and the icon is generated
by `scripts/make-icon.swift`. Both draw the same pixel pattern; if you change one, change the other.

## Regenerating the artwork

From the repository root:

```bash
swift scripts/make-icon.swift
```

This rewrites the `.icns`, `logo.png` and `social-preview.png`. Take a new `screenshot.jpg` when the
interface changes noticeably: run the app, open `Samples/sunset.png`, and capture the window (see
"Developer tools" in `AGENTS.md` for a way to snapshot the window from a script).

## Samples

`Samples/` holds artwork made for this project (`sunset.png`, `disc.png`), safe to use in
screenshots. Don't commit photos you don't own the rights to.
