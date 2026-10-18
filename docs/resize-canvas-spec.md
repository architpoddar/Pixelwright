# Paint.NET Resize and Canvas Size: behavior spec for the Mac port

Source: Paint.NET 5.1.12 x64 portable build, plus the public Paint.NET docs.
This is a behavioral spec for a clean-room reimplementation. It describes what the
program does, not how its code is written. Do not copy Paint.NET code or assets.

Confidence key: **High** = read directly from the binaries or docs and cross-checked.
**Medium** = inferred from call structure. **Open** = not determined yet.

## 1. Resize

### 1.1 Dialog fields and rules

| Item | Behavior | Confidence |
|---|---|---|
| Mode | "By percentage" or "By absolute size" (radio buttons) | High |
| Maintain aspect ratio | Checkbox. Default **on** for Resize; remembered between uses | High |
| Pixel width/height | Valid range **1 to 262,144** inclusive per side; OK is disabled outside it | High |
| Print size | width and height in the chosen unit; must be greater than 0 | High |
| Resolution (DPI) | Valid range **0.01 up to, not including, 2,000,000** | High |
| Units | Pixels, inches, centimeters. Last non-pixel unit is remembered; default **inches** | High |
| Print size relation | print size = pixels / resolution (docs example: 2 in at 96 DPI = 192 px) | High |
| Resampling dropdown | 8 choices, order below. Last choice remembered; default **Bicubic** | High |
| "Use gamma correction" | Checkbox, default **on**. **Disabled when Nearest Neighbor is selected** | High |
| Original size label | "Current image size" and "New size" text, both shown | High |

Resampling dropdown order (top to bottom), with internal id:

1. Bicubic (4), default
2. Bicubic (Smooth) (7)
3. Bilinear (5)
4. Bilinear (Low Quality) (1)
5. Adaptive (Sharp) (8)
6. Lanczos (6)
7. Fant (3)
8. Nearest Neighbor (0)

### 1.2 Size arithmetic

- Width and height are held as doubles in the chosen unit. They are only rounded when
  read back as pixels: round to nearest, **ties away from zero**, then clamp.
- **Maintain aspect ratio on:** changing width sets height = width / (origW / origH).
  Changing height sets width = height * (origW / origH). No rounding happens in between.
- **By percentage:** both sides are set independently to orig * (p / 100), each
  rounded on its own. Aspect locking is switched off while this is applied, so the
  result can differ by a pixel from the aspect-locked answer.
- **No-op rules:** if width, height, DPI and unit are all unchanged, nothing happens.
  If only DPI or unit changed, the pixels are untouched and only metadata changes
  (still recorded as one "Resize" history step).
- Percentage field's own min/max: **Open** (set in the dialog, not yet read).

### 1.3 Resampling engine

Paint.NET delegates image resizing to the open-source **PhotoSauce MagicScaler**
library (`PhotoSauce.MagicScaler.dll` ships with the app). Pixels are processed as
**premultiplied RGBA, 32-bit float per channel**, in a separable, tile-parallel pipeline.

| Choice | Kernel | Confidence |
|---|---|---|
| Bicubic | **Catmull-Rom** cubic (B=0, C=0.5). Matches the 5.0.4 changelog | High |
| Bicubic (Smooth) | Cubic with **B=1, C=0** (cubic B-spline): smooth, no overshoot or sharpening | High |
| Bilinear | Triangle (linear) kernel, area-aware when shrinking | High |
| Lanczos | Lanczos with **3 lobes** | High |
| Adaptive (Sharp) | **Chosen from the scale factor** by MagicScaler's automatic rule (below). Not a Magic Kernel variant, despite those classes existing in the app | High |
| Bilinear (Low Quality) | Plain **2-tap bilinear**: source position = (x + 0.5) / scale - 0.5, clamped at the edges, with no widening when shrinking (so it skips pixels on big reductions) | High |
| Fant | **Exact area averaging**: each output pixel is the area-weighted mean of the source pixels its footprint covers. Windows' native Fant scaler has no readable code, so this follows the published algorithm; enlargements may differ slightly | Medium |
| Nearest Neighbor | Point sampling, no gamma step | High |

**Adaptive (Sharp) rule.** With `ratio` = the smaller of (new width / old width) and
(new height / old height):

| ratio | Kernel |
|---|---|
| exactly 1 | Bilinear (triangle) |
| below 0.5 (shrinking by more than half) | Lanczos, 3 lobes |
| 0.5 to 4 | Spline36 |
| above 4, up to 16 | Catmull-Rom |
| above 16 | Interpolating quadratic (1 at 0, 0 at integers, 1/2 at half steps) |

Spline36 is the standard three-piece cubic over |x| < 3 (used in Panorama Tools and
ImageMagick); `Sources/PixelwrightCore/ResamplingKernel.swift` has the formula, and the
tests check that it passes through zero at integers and sums to 1.

Notes:

- Downscaling widens the kernel by the shrink factor (standard "scaled support"), so
  large reductions average many source pixels instead of aliasing. Needed for quality.
- **Gamma correction on** means resampling is done in **linear light**; **off** means
  it runs directly on sRGB-encoded values. (Confirmed: the two modes are named Linear
  and Companded, and the checkbox maps to Linear when ticked.)
- **Edges replicate:** kernel weights that fall outside the image are added to the nearest
  edge pixel, so every output pixel's weights still sum to 1. (Not "drop and renormalize".)
- Alpha is handled by premultiplying before filtering and un-premultiplying after.
- The document's color profile is passed into the scaler, so the work is color managed.
- Removed from earlier versions: Super Sampling (still present as a dead enum value).

### 1.4 Print size and resolution

Print size and resolution are part of the Resize and Canvas Size dialogs and are saved with
the image (pixels per inch or per centimeter).

- The dialog keeps **print size** (in the chosen unit) as the stored value and derives
  pixels = print size x resolution, rounded only when read as pixels.
- Editing a pixel size updates the print size; editing a print size updates the pixel size.
- **Changing the resolution keeps the print size**, so the pixel size changes (96 to 192 DPI
  doubles the pixels).
- Switching units keeps both the pixel size and the physical size.
- Images that don't store a resolution are treated as 96 pixels per inch.
- If only the resolution or unit changes, the pixels are untouched and only the metadata changes.

### 1.5 What the action does to the document

- Resizes **every layer** with the same settings, producing new layers with the
  original layer properties (name, opacity, blend mode, visibility) copied over.
- Runs on a background task with a cancelable progress dialog (shown if it takes
  longer than about 1 second). Cancel leaves the original document unchanged.
- One undo step. A selection history entry is recorded, so the selection is reset
  or restored by undo (Medium).
- Errors: out of memory and generic failure each have their own message.

## 2. Canvas Size

### 2.1 Dialog

Same dialog as Resize minus the resampling section, plus **Anchor** and **Fill**.

- Anchor: 3x3 grid. Values in order: Top Left, Top, Top Right, Left, Middle, Right,
  Bottom Left, Bottom, Bottom Right. High.
- Fill choices: **Transparent, Primary Color, Secondary Color, White, Black**. High.
- Maintain aspect ratio has its **own remembered setting, default off**. High.
- Same size, unit and DPI limits as Resize (section 1.1).
- Default anchor: the stored setting default is the first value (Top Left), but the
  docs only show center examples and the UI default is **not verified**. For the Mac
  port we recommend **Middle** as the default.

### 2.2 Placement math

New canvas size is (newW, newH); old layer size is (oldW, oldH).
Let `dx = newW - oldW`, `dy = newH - oldH`, and `hx = dx / 2`, `hy = dy / 2` using
**integer division that truncates toward zero** (matters when shrinking by an odd amount).

| Anchor | x offset | y offset |
|---|---|---|
| Top Left | 0 | 0 |
| Top | hx | 0 |
| Top Right | dx | 0 |
| Left | 0 | hy |
| Middle | hx | hy |
| Right | dx | hy |
| Bottom Left | 0 | dy |
| Bottom | hx | dy |
| Bottom Right | dx | dy |

Algorithm per layer: create a new transparent-capable surface of the new size, fill the
whole thing with the fill color, then copy the old pixels onto it at (x, y).
Pixels that land outside the new bounds are cropped (negative offsets crop the old
image's top/left; a smaller canvas crops the bottom/right).

Examples: grow 100 to 105 wide, Middle: offset 2 (2 px left, 3 px right).
Shrink 100 to 95 wide, Middle: offset -2 (crops 2 left, 3 right).

### 2.3 Fill colors

- Transparent = fully clear pixel (all channels 0).
- Primary and Secondary = the current tool colors at the time of the operation.
- White and Black = opaque white / black.

### 2.4 Document effects

- Applies to every layer (all must be bitmap layers). Layer properties are kept.
- Document metadata is carried over. Selection is saved before and restored after (Medium).
- One undo step (the old document is swapped back).
- If size, unit and DPI are all unchanged, nothing happens.

## 3. Background removal (not in Paint.NET)

Paint.NET has **no built-in background remover**. Its documented workflow is Magic Wand
(tolerance 0 to 100%) plus the Eraser. Third-party plugins call online services.
So there is nothing to port; this is our own design for the Mac:

- One-click subject cut-out using Apple's Vision foreground-mask request (macOS 14+).
- Magic Wand with tolerance and flood vs. global mode, plus feathered edge, as the
  manual fallback and refinement tool.

## 4. Mac implementation notes

- Do the resampling ourselves: two-pass separable convolution on premultiplied float
  pixels, kernel support scaled by `max(1, 1/scale)`, with a linear-light option.
  This reproduces the behavior above without needing Paint.NET code.
- Core Image's bicubic scale filter takes B and C parameters, so (0, 0.5) gives
  Catmull-Rom and (1, 0) gives Bicubic (Smooth). Useful as a quick prototype or
  cross-check, but it does not do area-aware downscaling, so keep our own engine.
- MagicScaler is a public MIT-licensed library that runs on .NET 10, which is already
  installed on this Mac. It can serve as a **test oracle**: generate reference
  outputs for Catmull-Rom, Linear and Lanczos, and compare our results.

## 5. Open questions

Resolved since the first draft: the kernel behind Adaptive (Sharp), the definition of
Bilinear (Low Quality), edge handling, and print size and resolution. Still open:

1. Windows' native Fant scaler, which has no readable code. We implement the published
   area-averaging algorithm; compare results if a Windows reference becomes available.
2. Percentage field limits.
3. Real default anchor in the Canvas Size dialog.
4. Whether Resize preserves the selection or resets it (only the history entry was seen;
   Pixelwright resets it).
5. Color-management details (how non-sRGB profiles convert in and out).

## 6. Provenance

- Download: `paint.net.5.1.12.portable.x64.zip` from the official `paintdotnet/release`
  GitHub releases. SHA-256 `d5ae7043f2fb9d365b48dfe243a2aca1c74924de99b04b6445916c95354aefa3`.
- REA 6.5.0 static .NET analysis read `PaintDotNet.Core.dll` and
  `PaintDotNet.Windows.Core.dll` (resampling modes, scaler plumbing, kernel setup).
- MagicScaler's own library code (`PhotoSauce.MagicScaler.dll`, shipped with the app) was read
  the same way for its default-interpolation rule, the Spline36 and Quadratic kernels, and its
  edge handling.
- The main app assembly `paintdotnet.dll` (about 19 MB of metadata) exceeds REA's
  64 MiB metadata budget, so the dialog and action logic was read with a small local
  tool built on .NET's `System.Reflection.Metadata`. Labels came from the app's English
  string resources.
- Public docs: <https://paint.net/doc/latest/ImageMenu.html>
