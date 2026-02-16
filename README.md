# Montr - Control Your Displays

Montr is a macOS menu bar app that lets you control display brightness and color temperature across built-in and external monitors.

## Highlights

- Per-display brightness control with DDC/CI where available
- Software brightness fallback for non-DDC displays
- Night Shift-style color temperature control
- Display profiles for quick switching
- Menu bar popover UI with quick actions

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (Swift 5.9) if building with Xcode

## Build and Run

### Xcode

1. Open `Montr — Control Your Displays.xcodeproj`.
2. Select the `Montr` scheme.
3. Build and run.

### Swift Package Manager

```bash
swift build
swift run
```

## Tests

```bash
swift test
```

## Project Docs

- Product spec: `docs/SPEC.md`

## Configuration

To enable Sentry crash reporting, provide `SENTRY_DSN` using one of these options:
1. Create `Montr — Control Your Displays/Resources/Secrets.plist` from `Montr — Control Your Displays/Resources/Secrets.example.plist`.
2. Set the `SENTRY_DSN` environment variable when launching the app.

## Notes

- External monitor brightness uses DDC/CI when supported.
- The app is intended for direct download (non-sandboxed) to enable DDC/CI access.

## Dependencies

- Sparkle (auto-updates)
- Sentry (crash reporting)

## License

MIT. See `LICENSE`.
