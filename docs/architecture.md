# Architecture

Pixelwright is two Swift targets plus tests:

```
Sources/
  PixelwrightCore/   engine library: no UI, no system frameworks
  Pixelwright/       SwiftUI app
Tests/PixelwrightCoreTests/
```

The split is deliberate. The engine can be built, tested and benchmarked from the command
line in about a second, and the app stays a thin shell around it.

## The exchange type: `RasterImage`

`RasterImage` is width, height and a flat `[UInt8]` of **straight-alpha sRGB RGBA**, row-major,
4 bytes per pixel. Every engine operation takes one and returns one. The app converts to and
from `CGImage` at the edges (`ImageConversion.swift`), including EXIF orientation on load.

## Resize: `Resampler`

`Resampler.resize(_:width:height:method:gammaCorrect:)`:

1. If the size is unchanged, return the input. For Nearest Neighbor, copy bytes directly (no color math).
2. Convert to **premultiplied float** RGBA. With gamma correction on, color is first converted from
   sRGB to linear light through a lookup table. Premultiplying means a transparent pixel's color
   can't bleed into its neighbors.
3. Build per-axis weights (`AxisWeights`). For each output pixel it picks the source pixels in the
   kernel's reach and their weights. When shrinking, the kernel is stretched by the shrink factor so
   many source pixels are averaged instead of skipped. Weights outside the image are dropped and the
   rest renormalized so they sum to 1.
4. Filter horizontally, then vertically (separable, so cost is linear in each dimension). Rows are
   processed in parallel with `DispatchQueue.concurrentPerform`.
5. Clamp (cubic and Lanczos can overshoot), un-premultiply, convert back to sRGB if needed, round to bytes.

Kernels live in `ResamplingKernel.swift`:

| Method | Kernel |
|---|---|
| Bicubic | Mitchell-Netravali with B=0, C=1/2 (Catmull-Rom) |
| Bicubic (Smooth) | Mitchell-Netravali with B=1, C=0 (cubic B-spline) |
| Bilinear | Triangle, widened when shrinking |
| Bilinear (Low Quality) | Triangle, never widened (two taps) |
| Adaptive (Sharp) | Picks Lanczos, Spline36, Catmull-Rom or a quadratic from the scale factor |
| Lanczos | Lanczos, 3 lobes |
| Fant | Exact area averaging (a separate weight builder, not a kernel) |
| Nearest Neighbor | Point sampling |

Each method maps to a `WeightStrategy` (a kernel, or area averaging). Weights that fall off the
edge of the image are folded into the edge pixel.

### Adding a resampling method

1. Add a case to `ResamplingMethod` with its `displayName`. The Resize dialog lists the cases in
   declaration order, so place it where it should appear.
2. Return a `WeightStrategy` from `weightStrategy(scaleX:scaleY:)`: a `ResamplingKernel` (a
   `support` half-width and a `weight` function) or area averaging. If it needs a different
   pipeline, handle it in `Resampler.resize` like Nearest Neighbor.
3. Add tests: kernel values at known points, normalized weights (the existing
   "Axis weights are normalized" test covers every case automatically), and a solid-color test.
4. Document it in `docs/resize-canvas-spec.md`.

## Canvas Size: `CanvasSize`

`CanvasSize.resize(_:newWidth:newHeight:anchor:fill:)` allocates the new canvas filled with the
chosen color, then **copies** (not blends) the old pixels at an offset set by the anchor, cropping
whatever falls outside. Offsets use integer division that truncates toward zero, so centering a
smaller canvas crops slightly more from one side. The full table is in the spec.

## Size math: `SizeMath`

Pure functions for the dialogs: percent to pixels, aspect-locked partner values, rounding (half
away from zero), and limits (1 to 262,144 px per side). Width and height are kept as doubles and
rounded only when read as pixels, which keeps the aspect lock from drifting.

## Transforms, effects and batch sizing

- `ImageTransform` does pixel-exact rotate, flip, crop and auto-crop (no resampling, so nothing is
  lost). `RasterImage.croppedToSelection` cuts out a non-rectangular selection on transparency.
- `Effect` is one value type for every adjustment and filter (brightness/contrast, hue/saturation,
  black and white, sepia, invert, blur, sharpen, pixelate). `applying(_:within:)` limits it to a
  selection, and `previewCopy` plus `Effect.scaled(by:)` let the dialogs preview on a smaller copy.
  `EffectKind` describes each dialog's sliders so the UI is generated from data.
- `BatchResizeMode` decides each image's new size (longest side, fit in a box, or percentage) and
  `BatchNaming` picks collision-free output names.
- `SelectionMask` also has shapes (rectangle, polygon for the lasso), `bounds`, `softCoverage` for
  feathering, and `resized` for previews.

## Dialog state: `SizeEditorState`

The Resize and Canvas Size dialogs share one value type that keeps pixel size, print size,
resolution, unit and percentage consistent (editing one updates the others, with the aspect
lock and Paint.NET's rules). It lives in the engine so the rules are unit-tested; the SwiftUI
dialogs only bind fields to it (`SizeFields.swift`).

## Selection: `SelectionMask` and `MagicWand`

A selection is one flag per pixel. `MagicWand.select` does a flood fill (4-way) or a global
match against the clicked pixel, using premultiplied RGBA distance scaled by a 0 to 100%
tolerance. See [selection-and-wand.md](selection-and-wand.md).

## The app

- `AppModel` holds the current image, its resolution, the selection and wand settings, undo/redo,
  and busy state. Edits run on a background
  task through one helper (`edit`), then swap in the result as a single undo step.
- Undo stores whole-image snapshots, with their resolution (up to 20). That's simple and robust, but a large photo costs
  about 4 bytes per pixel per step, so a 12-megapixel image uses roughly 48 MB per step.
- `ResizeSheet` and `CanvasSizeSheet` are the dialogs. Both keep width and height as doubles and
  route edits through bindings that apply the aspect lock.
- `BackgroundRemoval` wraps Vision's `VNGenerateForegroundInstanceMaskRequest`.
- The canvas keeps a ready-made `CGImage` of the picture (and of any live effect preview) so repaints
  don't convert the pixels again. One drag gesture serves the Rectangle, Lasso and Magic Wand tools.
- `ExportSheet` encodes in memory to show a file-size estimate; `BatchResizeSheet` runs a `BatchJob`
  that loads, resizes and writes one file at a time, off the main thread.
- `Brand.swift` holds the colors, the pixel-P mark, the wordmark, the welcome screen and the About window.
- `scripts/make-app.sh` wraps the SwiftPM executable in an ad-hoc-signed `.app` bundle.

## Testing

Engine tests use Swift Testing and tiny synthetic images with exact expected values: kernel
values, weight normalization, gamma averages, alpha handling, anchor offsets, truncating
center math, size limits, selection shapes, effects and batch sizing. `PixelwrightAppTests`
checks real file round trips (PNG, JPEG, HEIC, TIFF, resolution, transparency) and the batch pipeline.
