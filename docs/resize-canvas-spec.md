# Resize and Canvas Size: behavior spec

This is the behavior Pixelwright's Resize and Canvas Size commands implement. It is
informed by how familiar image editors such as Paint.NET behave, using only public
material (listed in [Sources](#6-sources)): the Paint.NET manual and release notes, the
MIT-licensed PhotoSauce MagicScaler source, and published filter definitions.

Pixelwright is a clean-room project. This spec describes observable behavior and
Pixelwright's own choices, not anyone else's code. Do not copy code or assets from other
editors into this repository.

Basis key, used in the tables below:

- **Documented**: stated in the public Paint.NET manual or release notes.
- **Public source**: matches MagicScaler's public MIT-licensed source.
- **Standard**: a published, textbook algorithm.
- **Ours**: a Pixelwright decision. Not derived from another program.

## 1. Resize

### 1.1 Dialog fields and rules

| Item | Behavior | Basis |
|---|---|---|
| Mode | "By percentage" or "By absolute size" (radio buttons) | Documented |
| Maintain aspect ratio | Checkbox. Default **on** for Resize; remembered between uses | Documented |
| Pixel width/height | Valid range **1 to 262,144** inclusive per side; OK is disabled outside it | Ours |
| Print size | Width and height in the chosen unit; must be greater than 0 | Documented |
| Resolution (DPI) | Valid range **0.01 up to, not including, 2,000,000** | Ours |
| Units | Pixels, inches, centimeters. Last non-pixel unit is remembered; default **inches** | Ours |
| Print size relation | print size = pixels / resolution (2 in at 96 DPI = 192 px) | Documented |
| Resampling dropdown | 8 choices, order below. Last choice remembered; default **Bicubic** | Documented |
| "Use gamma correction" | Checkbox, default **on**. **Disabled when Nearest Neighbor is selected** | Ours |
| Size labels | "Current size" and "New size" text, both shown | Ours |

Resampling dropdown order (top to bottom), which follows the Paint.NET manual:

1. Bicubic (default)
2. Bicubic (Smooth)
3. Bilinear
4. Bilinear (Low Quality)
5. Adaptive (Sharp)
6. Lanczos
7. Fant
8. Nearest Neighbor

### 1.2 Size arithmetic

All of this section is **Ours**.

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
- Percentage field limits: the same as the pixel limits above, applied to the result.

### 1.3 Resampling engine

Pixelwright's engine works on **premultiplied RGBA, 32-bit float per channel**, as a
separable two-pass convolution (horizontal, then vertical).

| Choice | Kernel | Basis |
|---|---|---|
| Bicubic | **Catmull-Rom** cubic (B=0, C=0.5). The Paint.NET 5.0.4 release notes describe this as the default bicubic | Documented, Standard |
| Bicubic (Smooth) | Cubic with **B=1, C=0** (cubic B-spline): smooth, no overshoot or sharpening. The 5.0.4 notes describe a bicubic option without sharpening | Documented, Standard |
| Bilinear | Triangle (linear) kernel, widened by the shrink factor when shrinking | Standard |
| Lanczos | Lanczos with **3 lobes** | Standard |
| Adaptive (Sharp) | **Chosen from the scale factor** by the rule below. The 5.0.4 notes renamed "Adaptive (Best Quality)" to "Adaptive (Sharp)" | Public source |
| Bilinear (Low Quality) | Plain **2-tap bilinear**: source position = (x + 0.5) / scale - 0.5, clamped at the edges, with no widening when shrinking (so it skips pixels on big reductions) | Ours |
| Fant | **Exact area averaging**: each output pixel is the area-weighted mean of the source pixels its footprint covers (Fant, 1986) | Standard |
| Nearest Neighbor | Point sampling, no gamma step | Standard |

**Adaptive (Sharp) rule.** With `ratio` = the smaller of (new width / old width) and
(new height / old height), Pixelwright picks the kernel the way MagicScaler's
public `GetDefaultInterpolation` does:

| ratio | Kernel |
|---|---|
| exactly 1 | Bilinear (triangle) |
| below 0.5 (shrinking by more than half) | Lanczos, 3 lobes |
| 0.5 to 4 | Spline36 |
| above 4, up to 16 | Catmull-Rom |
| above 16 | Interpolating quadratic (1 at 0, 0 at integers, 1/2 at half steps) |

Spline36 is the standard three-piece cubic over |x| < 3 (also used in Panorama Tools and
ImageMagick; MagicScaler's `Spline36Interpolator` lists the same coefficients).
`Sources/PixelwrightCore/ResamplingKernel.swift` has the formula, and the tests check
that it passes through zero at integers and sums to 1.

Notes:

- Downscaling widens the kernel by the shrink factor (standard "scaled support"), so
  large reductions average many source pixels instead of aliasing. Needed for quality.
  (**Standard**)
- **Gamma correction on** means resampling is done in **linear light**; **off** means
  it runs directly on sRGB-encoded values. (**Ours**)
- **Edges replicate:** kernel weights that fall outside the image are added to the nearest
  edge pixel, so every output pixel's weights still sum to 1. (Not "drop and renormalize".)
  (**Ours**)
- Alpha is handled by premultiplying before filtering and un-premultiplying after.
  (**Standard**)
- Pixelwright treats images as sRGB. See open question 5.

### 1.4 Print size and resolution

All of this section is **Ours**, consistent with the print-size behavior in the Paint.NET
manual.

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

All of this section is **Ours**. Pixelwright has a single flat image today; the layer
notes apply when layers are added.

- Resizes the whole image with the chosen settings. When layers exist, every layer is
  resized with the same settings and keeps its properties (name, opacity, blend mode,
  visibility).
- Heavy work runs off the main thread so the window stays responsive.
- One undo step. The selection is reset by a resize.
- Failures (such as running out of memory) are reported in plain words and leave the
  original image untouched.

## 2. Canvas Size

### 2.1 Dialog

Same dialog as Resize minus the resampling section, plus **Anchor** and **Fill**.

- Anchor: 3x3 grid. Values in order: Top Left, Top, Top Right, Left, Middle, Right,
  Bottom Left, Bottom, Bottom Right. (**Documented**)
- Fill choices: **Transparent, White, Black, Color** (any color, with opacity). Fill only
  applies when the canvas gets bigger. (**Ours**)
- Maintain aspect ratio has its **own remembered setting, default off**. (**Ours**)
- Same size, unit and DPI limits as Resize (section 1.1).
- Default anchor: **Middle**. (**Ours**)

### 2.2 Placement math

All of this section is **Ours** (a standard centered or edge-anchored placement).

New canvas size is (newW, newH); old size is (oldW, oldH).
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

Algorithm: create a new surface of the new size, fill the whole thing with the fill
color, then copy the old pixels onto it at (x, y). Pixels that land outside the new
bounds are cropped (negative offsets crop the old image's top/left; a smaller canvas
crops the bottom/right).

Examples: grow 100 to 105 wide, Middle: offset 2 (2 px left, 3 px right).
Shrink 100 to 95 wide, Middle: offset -2 (crops 2 left, 3 right).

### 2.3 Fill colors

All **Ours**.

- Transparent = fully clear pixel (all channels 0).
- Color = the color chosen in the dialog, including its opacity.
- White and Black = opaque white / black.

### 2.4 Document effects

All **Ours**.

- Applies to the whole image (and to every layer, once layers exist). Layer properties are kept.
- Image metadata, including resolution, is carried over. The selection is reset.
- One undo step.
- If size, unit and DPI are all unchanged, nothing happens.

## 3. Background removal (not in Paint.NET)

Paint.NET has **no built-in background remover**. Its documented workflow is Magic Wand
(tolerance 0 to 100%) plus the Eraser. Third-party plugins call online services.
So there is nothing to mirror; this is our own design for the Mac:

- One-click subject cut-out using Apple's Vision foreground-mask request (macOS 14+).
- Magic Wand with tolerance and flood vs. global mode, plus feathered edge, as the
  manual fallback and refinement tool.

Everything runs on the Mac. No image data is sent anywhere.

## 4. Implementation notes

- Do the resampling ourselves: two-pass separable convolution on premultiplied float
  pixels, kernel support scaled by `max(1, 1/scale)`, with a linear-light option.
- Core Image's bicubic scale filter takes B and C parameters, so (0, 0.5) gives
  Catmull-Rom and (1, 0) gives Bicubic (Smooth). Useful as a quick prototype or
  cross-check, but it does not do area-aware downscaling, so keep our own engine.
- MagicScaler is a public MIT-licensed library. Running it locally can serve as a
  **test oracle**: generate reference outputs for Catmull-Rom, linear-light and Lanczos
  resizes, and compare Pixelwright's results.

## 5. Open questions

1. Fant on enlargement: we implement the published area-averaging algorithm; other
   implementations may differ slightly when enlarging.
2. Whether a resize should preserve a selection instead of resetting it (Pixelwright resets it).
3. Whether the Canvas Size dialog should remember its last anchor between uses.
4. Whether to add the ability to fill with the primary or secondary tool color once
   drawing tools exist.
5. Color-management details: how non-sRGB profiles convert in and out of the sRGB working space.

## 6. Sources

- Paint.NET manual, Image menu: <https://paint.net/doc/latest/ImageMenu.html>
- Paint.NET 5.0.4 release notes (default Bicubic is Catmull-Rom; "Bicubic (Smooth)";
  "Adaptive (Best Quality)" renamed "Adaptive (Sharp)"): <https://www.getpaint.net/roadmap.html>
- PhotoSauce MagicScaler, MIT license: <https://github.com/saucecontrol/PhotoSauce>
  (`src/MagicScaler/Utilities/SettingUtil.cs` for the automatic interpolation rule,
  `src/MagicScaler/Core/Interpolators.cs` for the quadratic and Spline36 kernels)
- Mitchell and Netravali, "Reconstruction Filters in Computer Graphics" (SIGGRAPH 1988):
  the B and C cubic family used for Bicubic and Bicubic (Smooth)
- Fant, "A Nonaliasing, Real-Time Spatial Transform Technique" (IEEE CG&A, 1986): area-averaged resampling
- Lanczos resampling and Spline36: standard published filters (Panorama Tools and ImageMagick document Spline36)
