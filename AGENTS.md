# AGENTS.md

Instructions for anyone, human or coding agent, working in this repo on a Mac.
Pixelwright is a native macOS image editor (Swift 6, SwiftUI, Swift Package Manager).

## Prerequisites

- macOS 14 or later
- Xcode 16 or later (provides Swift 6). Check with `swift --version` and `xcodebuild -version`.
- Nothing else. There are no third-party dependencies and no Xcode project file.

## Commands

| Task | Command |
|---|---|
| Build everything | `swift build` |
| Run all tests | `swift test` |
| Run one suite | `swift test --filter CanvasSizeTests` (use the Swift type name; display names don't match) |
| Format a file | `swift format format --in-place --configuration '{"version":1,"indentation":{"spaces":4},"lineLength":130}' <file>` |
| Build a launchable app | `./scripts/make-app.sh` (add `debug` for a debug build) |
| Launch it | `open build/Pixelwright.app` |
| Open a file in it | `open -a "$PWD/build/Pixelwright.app" "$PWD/Samples/disc.png"` |
| Quit it before rebuilding | `pkill -x Pixelwright` |
| Regenerate the icon and artwork | `swift scripts/make-icon.swift` |
| Open in Xcode | `xed .` (Xcode opens `Package.swift` directly) |

Always run `swift test` before finishing a change. The suite takes about a second.

## Layout

- `Sources/PixelwrightCore/`: the image engine. Pure Swift, **no UI or system-framework imports**.
  Resampling, canvas size, size math, the `RasterImage` type.
- `Sources/Pixelwright/`: the SwiftUI app (windows, dialogs, file I/O, Vision background removal).
- `Tests/PixelwrightCoreTests/`: engine tests, written with Swift Testing (`import Testing`).
- `Tests/PixelwrightAppTests/`: tests for the app's file reading and writing and the batch resize
  pipeline, run against real files in a temp folder.
- `Resources/AppIcon.icns` and `docs/assets/`: the generated brand artwork (see `docs/branding.md`).
- `docs/resize-canvas-spec.md`: the behavior spec for Resize and Canvas Size. Treat it as the
  source of truth; the tests encode it.
- `docs/architecture.md`: how the pieces fit. `docs/roadmap.md`: what's next.
  `docs/selection-and-wand.md`: the Magic Wand and selection design.
- `Samples/`: small test images. `scripts/`: build helpers.

## Rules that matter

0. **Nothing leaves the Mac.** This is a core promise of the product (see the README). Do not add
   networking, analytics, telemetry, crash reporting, auto-update checks, web views or third-party
   dependencies. The only web address in the code is the GitHub link, opened by the user's click.
   The README tells people how to verify this, so keep those three checks true.

1. **Clean-room.** Never copy code, assets, strings or decompiler output from Paint.NET or any other
   proprietary program into this repo, issues or PRs. Describe behavior in your own words and pin
   it with a test. See [CONTRIBUTING.md](CONTRIBUTING.md).
2. **Keep `PixelwrightCore` UI-free.** Anything using SwiftUI, AppKit, ImageIO, CoreGraphics or
   Vision goes in `Sources/Pixelwright`. The engine works on `RasterImage` (8-bit straight-alpha
   sRGB RGBA) so it stays testable from the command line.
3. **Behavior changes need a spec and a test.** If you change how Resize or Canvas Size behaves,
   update `docs/resize-canvas-spec.md` and add or adjust a test in the same change.
4. **Don't commit build output**: `.build/`, `build/`, `*.xcodeproj`.

## Gotchas on macOS

- `swift run Pixelwright` launches a bare executable with no bundle identifier. It works for a quick
  look, but use `./scripts/make-app.sh` for anything real: Finder file-open, UI automation and
  accurate app behavior all need the `.app` bundle.
- `open -a` needs an **absolute** path to the `.app`, or it reports that it can't find the application.
- The `.app` is ad-hoc signed (`codesign --sign -`), so it runs on the Mac that built it. Pixelwright is
  shared as source for now: everyone builds their own copy with `./scripts/make-app.sh`. Don't add
  App Store or notarization steps.
- The app target builds in Swift 5 language mode (SwiftUI and AppKit ergonomics); the engine
  builds in Swift 6 with strict concurrency. Keep engine types `Sendable`.
- Debug builds are much slower than release for big images. For performance checks use
  `swift test -c release` or `./scripts/make-app.sh release`.
- Background removal needs macOS 14+ and a real foreground subject. Flat, synthetic or very wispy
  images (a dandelion, say) can return "No foreground subject was found", which is expected, not a
  bug. The Magic Wand is the fallback.
- If a SwiftUI sheet field won't take typed input during UI automation, click it first; it has to
  hold keyboard focus. Fields inside the scrolling part of a dialog can be stubborn; the engine
  logic behind them is covered by unit tests (`SizeEditorStateTests`).
- A SwiftUI sheet can't be taller than its window. The Resize and Canvas Size dialogs scroll with
  pinned buttons for this reason; keep new dialogs the same way.

## Testing notes

- Prefer small synthetic images in tests (a few pixels) with exact expected values.
- Colors are compared with a tolerance of 1 where resampling rounds. Gamma-correct averages
  of black and white should land near 188; without gamma correction near 128.
- To check the real app, build with `./scripts/make-app.sh debug`, open `Samples/disc.png`, and try
  Image menu items: Resize… (⌘R), Canvas Size… (⇧⌘R), Remove Background (⇧⌘B). Tools are in the
  Select menu (Rectangle ⇧⌘M, Lasso ⇧⌘L, Magic Wand ⇧⌘W, Pointer ⇧⌘P). Adjustments and Effects have
  their own menus; File has Export… (⇧⌘E) and Batch Resize… (⌥⌘B).
- Use your own photos for testing background removal. Don't commit third-party photos to `Samples/`.

## Originals are never overwritten

Saving always makes a copy. `AppModel.chooseDestination` opens the save panel in the original's folder
with a name that can't collide ("photo edited.png"), and if the chosen file is the original it stops to
ask (`AppModel.isSameFile`). Do not add an in-place "Save" or any path that writes to `sourceURL`
without that warning. `isEdited` drives the title-bar dot and the confirmation before closing,
quitting or opening another image (`confirmDiscardIfNeeded`).

## Developer tools

- **Window snapshots without screen-recording permission.** Launch through `open` (running the binary
  directly doesn't create a window) and pass settings with `--env`:
  ```bash
  open -n -a "$PWD/build/Pixelwright.app" \
    --env PIXELWRIGHT_DEBUG_OPEN=Samples/sunset.png --env PIXELWRIGHT_DEBUG_TOOL=wand \
    --env PIXELWRIGHT_DEBUG_SELECT_ALL=1 --env PIXELWRIGHT_DEBUG_SIZE=700x600 \
    --env PIXELWRIGHT_SNAPSHOT=/tmp/window.png
  ```
  It writes the PNG and quits. Handy for checking layouts at different window sizes. Options are in
  `Sources/Pixelwright/DebugHooks.swift`. Native toolbar items show as white shapes in the snapshot.
- **Real-image test.** Point the corpus test at a folder of your own images to run every operation
  (all resize methods, canvas, rotate, effects, every export format, batch, background removal) on
  them: `PIXELWRIGHT_CORPUS=/path/to/images swift test -c release --filter CorpusTests`. It skips
  itself when the variable isn't set, so it never runs in CI. Never commit the images.

## Branding

Pixelwright's name, colors and logo are part of the product. Use `Brand` (`Sources/Pixelwright/Brand.swift`)
for colors and the mark rather than hard-coding them, keep the pixel "P" in sync with
`scripts/make-icon.swift`, and see `docs/branding.md`.

## File opens

Files opened from Finder or `open -a` are handled by `AppDelegate.application(_:open:)`, not
`.onOpenURL`. With an app delegate installed, SwiftUI stops delivering URLs to `.onOpenURL` while the app
is already running (a test in `ModelStateTests` guards this).

## Menu commands and text fields

Cut, Copy, Paste, Select All and Undo are replaced by image versions in `PixelwrightApp.swift`. They go
through `AppModel.cutCommand()` and friends, which hand the command to the text field when one is being
edited. Keep using those helpers for any new command that shares a standard shortcut.

## Known gaps

Not implemented yet: drawing tools, layers, free-angle rotate, a Levels / Curves adjustment.
Open questions about Paint.NET behavior are in section 5 of `docs/resize-canvas-spec.md`.
Fant follows the published area-averaging algorithm; Windows' own scaler isn't readable, so
enlargements may differ slightly from Paint.NET.
