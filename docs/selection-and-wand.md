# Selection and the Magic Wand

This is Pixelwright's own design. (Paint.NET's documented background workflow is also
Magic Wand plus the eraser; the details below are ours.)

## Using it

1. Turn on the wand: toolbar button, or **Select > Magic Wand** (⇧⌘W).
2. Click the image. Pixels similar to the one you clicked are tinted blue.
3. **Shift-click** adds to the selection, **Option-click** subtracts.
4. Press **Delete** (or use the Delete button) to make the selected pixels transparent.

Other commands live in the **Select** menu: Select All (⌘A), Deselect (⇧⌘A), Invert Selection
(⌘I), and Expand or Contract by 1 pixel (useful for trimming a thin halo).

Any edit that changes the image (resize, canvas size, background removal, delete) clears the
selection. Selection changes themselves aren't undo steps yet.

## Settings

- **Tolerance, 0 to 100%.** 0 matches only the exact color; 100 matches everything.
- **Mode.** *Flood fill* selects only pixels connected (up, down, left, right) to the click.
  *Global* selects every similar pixel in the image, connected or not.

## How "similar" is decided

Each pixel is converted to premultiplied RGBA (so all fully transparent pixels look the same),
and its distance from the clicked pixel is measured as an ordinary Euclidean distance over the
four channels (0 to 255 each). The largest possible distance, opaque white to transparent, is
510, so a pixel matches when `distance <= tolerance / 100 * 510`. The comparison is always with
the *clicked* pixel, not with a neighbor, so a gradient can't "creep" outward.

## When to use it instead of Remove Background

**Remove Background** uses Apple's on-device subject detection and is best for photos with a
clear subject (people, animals, products). It can fail on wispy, low-contrast or very busy
subjects, for example a dandelion. The wand is the manual fallback: click the background,
Shift-click the stragglers, press Delete.

The code is in `Sources/PixelwrightCore/Selection.swift` (`SelectionMask`, `MagicWand`) with
tests in `Tests/PixelwrightCoreTests/SelectionTests.swift`.
