# Changelog

## 0.1.0 (unreleased)

First version.

**Resize and reshape**
- Resize: by percentage or absolute pixels, aspect-ratio lock, print size and resolution (inches or
  centimeters, saved with the file), gamma-correct option, and eight resampling methods: Bicubic,
  Bicubic (Smooth), Bilinear, Bilinear (Low Quality), Adaptive (Sharp), Lanczos, Fant and
  Nearest Neighbor.
- Canvas Size: 3x3 anchor, fill with transparent, white, black or a custom color.
- Crop to selection (cuts out irregular shapes), Auto-Crop transparent edges, Rotate 90 / 180,
  Flip horizontal and vertical.

**Cut things out**
- Remove Background: one click, using Apple's on-device Vision framework.
- Selection tools: Rectangle, Lasso and Magic Wand (tolerance, flood or global mode); add and
  subtract; Select All, Invert, Expand, Contract; Delete with an optional feather.

**Adjust**
- Brightness / Contrast, Hue / Saturation, Black and White, Sepia, Invert Colors, Blur, Sharpen,
  Pixelate. Live preview, and they apply to the selection when there is one.

**Save and share**
- Export to PNG, JPEG, HEIC or TIFF with quality, optional size limit and a file-size estimate.
- Batch Resize: many images to a size you choose, saved as copies in a folder.
- Copy and paste as a new image; open and save; undo and redo; zoom; drag-and-drop.

**Undo and redo**
- Up to 20 steps, with Undo and Redo buttons at the bottom of the tool palette and menu items that name
  the action ("Undo Resize", "Redo Blur"). Hovering a button shows the same.

**Install**
- `./scripts/install.sh` builds the app and installs it into Applications in one command, with
  `--open`, `--to` and `--uninstall`, and safeguards so it can't replace another app or lose work.

**Private by design**
- Fully local: no server, no account, no analytics, no network access, no third-party code.
  The README shows three quick checks to verify it.

**Safe by design**
- Saving always writes a copy; the original file is never changed unless you confirm a warning.
  "Save a Copy…" opens in the original's folder with a name like "photo edited.png".
- The window shows "Edited · original untouched", the standard unsaved-changes dot, and the file's
  icon; closing, quitting or opening another image asks first.
- Tooltips on every button and control, plain-language descriptions of each resize method, a tool
  palette on the left, and Help > Keyboard Shortcuts.

**Look**
- Pixelwright branding: app icon, welcome screen, About window and a violet accent color.
