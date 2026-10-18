# Contributing to Pixelwright

Thanks for helping out. This is a small project, so the process is light.

## The clean-room rule (please read)

Pixelwright is an original implementation. Its behavior was specified by observing how
everyday image-editing tools work, and the result is written down in
[docs/resize-canvas-spec.md](docs/resize-canvas-spec.md).

- **Do not** submit code, assets, icons, strings or decompiled output copied from Paint.NET,
  or from any other proprietary or incompatibly licensed program.
- **Do not** paste output from decompilers or disassemblers into issues or pull requests.
- **Do** describe behavior in your own words, with a test that pins it down.
- Open-source libraries and published algorithms (for example the Mitchell-Netravali cubic
  filters or Lanczos) are fine to implement. Say where an algorithm comes from in a comment.

If you're unsure whether something is OK to include, ask in the issue before writing it.

## Set up

You need macOS 14+ and Xcode 16+.

```bash
git clone https://github.com/architpoddar/Pixelwright.git
cd Pixelwright
swift build
swift test
./scripts/make-app.sh && open build/Pixelwright.app
```

## Making a change

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Create a branch from `main`.
3. Keep the change focused. One feature or fix per pull request.
4. Add or update tests. Engine changes (`Sources/PixelwrightCore`) need tests; they run in
   under a second.
5. Run `swift test` and make sure the app still builds with `./scripts/make-app.sh`.
6. If you change user-visible behavior, update the docs (README, `docs/`).
7. Open a pull request and fill in the template.

## Code guidelines

- `PixelwrightCore` must stay free of UI imports (no SwiftUI, AppKit or Vision). Anything
  that touches the screen or system frameworks belongs in `Sources/Pixelwright`.
- Prefer small, plain Swift. Match the style of the surrounding code.
- Tests use [Swift Testing](https://developer.apple.com/documentation/testing) (`import Testing`,
  `@Test`, `#expect`).
- Don't commit build output (`.build/`, `build/`) or Xcode user data.

## Reporting bugs

Please include your macOS version, what you did, what you expected, and what happened.
For image problems, attach a small sample image if you can (only one you have the right to share).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
