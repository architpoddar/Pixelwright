# Pixelwright

A small, fast image editor for macOS, built around the everyday tools people reach for in
classic Windows editors like Paint.NET: **Resize**, **Canvas Size** and **Background removal**.

Native Swift and SwiftUI. No cloud, no account: your images never leave your Mac.

> **Status: early (v0.1).** The three core tools work and are tested, but many features
> are still missing. See the [roadmap](docs/roadmap.md).

## Features

- **Resize** by percentage or exact pixels, with an aspect-ratio lock.
  Resampling: Bicubic (Catmull-Rom), Bicubic (Smooth), Bilinear, Lanczos, Nearest Neighbor.
  Optional gamma-correct (linear-light) resizing, which keeps brightness right when shrinking.
- **Canvas Size** with a 3x3 anchor grid and a fill of Transparent, White, Black or any color.
  Growing adds space; shrinking crops.
- **Remove Background** in one click, using Apple's on-device Vision framework.
- Open and save PNG, JPEG, TIFF and HEIC. Undo and redo. Zoom, fit-to-window and drag-and-drop.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later (Swift 6) to build from source

## Build and run

```bash
git clone https://github.com/<your-account>/Pixelwright.git
cd Pixelwright

./scripts/make-app.sh      # builds build/Pixelwright.app
open build/Pixelwright.app
```

The build is ad-hoc signed, so it runs on the Mac that built it. For a quick developer
launch you can also use `swift run Pixelwright`.

Run the tests with:

```bash
swift test
```

## How it works

The image engine lives in its own library, `PixelwrightCore`, with no UI code. It resizes
using separable two-pass filtering on premultiplied float pixels, so transparent edges don't
bleed color, and it can work in linear light. The SwiftUI app is a thin layer on top.
See [docs/architecture.md](docs/architecture.md).

The exact behavior of Resize and Canvas Size (dialog rules, size limits, anchor math, kernels)
is written down in [docs/resize-canvas-spec.md](docs/resize-canvas-spec.md), and the tests check it.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first, especially the
clean-room rule: **do not submit code or assets copied from Paint.NET or any other
proprietary program.** Developers and coding agents should also read [AGENTS.md](AGENTS.md).

## Not affiliated

Pixelwright is an independent project. It is not affiliated with, endorsed by, or derived from
the source code of Paint.NET or dotPDN LLC. "Paint.NET" is a trademark of its owner and is
mentioned only to describe which everyday behaviors this app aims to feel familiar with.

## License

[MIT](LICENSE)
