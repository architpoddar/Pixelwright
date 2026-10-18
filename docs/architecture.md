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
| Bilinear | Triangle |
| Lanczos | Lanczos, 3 lobes |
| Nearest Neighbor | Point sampling |

### Adding a resampling method

1. Add a case to `ResamplingMethod` with its `displayName`.
2. Return a `ResamplingKernel` from `kernel` (a `support` half-width and a `weight` function).
   If it needs a different pipeline, handle it in `Resampler.resize` like Nearest Neighbor.
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

## The app

- `AppModel` holds the current image, undo/redo, and busy state. Edits run on a background
  task through one helper (`edit`), then swap in the result as a single undo step.
- Undo stores whole-image snapshots (up to 20). That's simple and robust, but a large photo costs
  about 4 bytes per pixel per step, so a 12-megapixel image uses roughly 48 MB per step.
- `ResizeSheet` and `CanvasSizeSheet` are the dialogs. Both keep width and height as doubles and
  route edits through bindings that apply the aspect lock.
- `BackgroundRemoval` wraps Vision's `VNGenerateForegroundInstanceMaskRequest`.
- `scripts/make-app.sh` wraps the SwiftPM executable in an ad-hoc-signed `.app` bundle.

## Testing

Engine tests use Swift Testing and tiny synthetic images with exact expected values: kernel
values, weight normalization, gamma averages, alpha handling, anchor offsets, truncating
center math and size limits.
