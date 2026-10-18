# Pixelwright

A small, fast image editor for macOS, inspired by the everyday tools in Paint.NET.
v1 focuses on three things: **Resize**, **Canvas Size** and **Background removal**.

## Run it

```bash
./scripts/make-app.sh          # builds build/Pixelwright.app (add "debug" for a debug build)
open build/Pixelwright.app
```

Or `swift run Pixelwright` for a quick dev launch. Requires macOS 14+ and Xcode 16+ (Swift 6).

## Test

```bash
swift test
```

## Layout

- `Sources/PixelwrightCore`: the image engine (resampling, canvas size, size math). No UI imports.
- `Sources/Pixelwright`: the SwiftUI app.
- `Tests/PixelwrightCoreTests`: engine tests.
- `docs/resize-canvas-spec.md`: behavior spec for Resize and Canvas Size, derived from
  observing Paint.NET 5.1.12 and its public docs. This is a clean-room project: no Paint.NET
  code or assets are used.
- `Samples/`: a test image.

## v1 status

- Resize: percentage or absolute size, aspect lock, Bicubic (Catmull-Rom), Bicubic (Smooth),
  Bilinear, Lanczos, Nearest Neighbor, linear-light "gamma correction".
- Canvas Size: 3x3 anchor, fill (transparent, white, black, custom color).
- Remove Background: one click, using Apple's on-device Vision framework.
- Open/save PNG, JPEG, TIFF, HEIC; undo/redo; zoom.

Not yet: Fant, Bilinear (Low Quality) and Adaptive (Sharp) resampling; DPI and print size;
a Magic Wand; layers.
