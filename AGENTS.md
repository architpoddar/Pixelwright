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
| Build a launchable app | `./scripts/make-app.sh` (add `debug` for a debug build) |
| Launch it | `open build/Pixelwright.app` |
| Open a file in it | `open -a "$PWD/build/Pixelwright.app" "$PWD/Samples/disc.png"` |
| Quit it before rebuilding | `pkill -x Pixelwright` |
| Open in Xcode | `xed .` (Xcode opens `Package.swift` directly) |

Always run `swift test` before finishing a change. The suite takes about a second.

## Layout

- `Sources/PixelwrightCore/`: the image engine. Pure Swift, **no UI or system-framework imports**.
  Resampling, canvas size, size math, the `RasterImage` type.
- `Sources/Pixelwright/`: the SwiftUI app (windows, dialogs, file I/O, Vision background removal).
- `Tests/PixelwrightCoreTests/`: engine tests, written with Swift Testing (`import Testing`).
- `docs/resize-canvas-spec.md`: the behavior spec for Resize and Canvas Size. Treat it as the
  source of truth; the tests encode it.
- `docs/architecture.md`: how the pieces fit. `docs/roadmap.md`: what's next.
- `Samples/`: small test images. `scripts/`: build helpers.

## Rules that matter

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
- The `.app` is ad-hoc signed (`codesign --sign -`). It runs on the Mac that built it. Sharing it
  with others needs a Developer ID signature and notarization, which this repo doesn't set up yet.
- The app target builds in Swift 5 language mode (SwiftUI and AppKit ergonomics); the engine
  builds in Swift 6 with strict concurrency. Keep engine types `Sendable`.
- Debug builds are much slower than release for big images. For performance checks use
  `swift test -c release` or `./scripts/make-app.sh release`.
- Background removal needs macOS 14+ and a real foreground subject. Flat or synthetic images can
  return "No foreground subject was found", which is expected, not a bug.
- If a SwiftUI sheet field won't take typed input during UI automation, click it first; it has to
  hold keyboard focus.

## Testing notes

- Prefer small synthetic images in tests (a few pixels) with exact expected values.
- Colors are compared with a tolerance of 1 where resampling rounds. Gamma-correct averages
  of black and white should land near 188; without gamma correction near 128.
- To check the real app, build with `./scripts/make-app.sh debug`, open `Samples/disc.png`, and try
  Image menu items: Resize… (⌘R), Canvas Size… (⇧⌘R), Remove Background (⇧⌘B).

## Known gaps

Not implemented yet: Fant, Bilinear (Low Quality) and Adaptive (Sharp) resampling; DPI and print
size in the dialogs; Magic Wand; layers. Open questions are listed in section 5 of
`docs/resize-canvas-spec.md`.
