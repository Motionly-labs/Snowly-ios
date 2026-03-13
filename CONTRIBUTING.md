# Contributing to Snowly

Thanks for taking the time. Snowly is built by skiers, for skiers — every contribution matters.

## Before You Start

- **Check existing issues** — someone may already be working on it.
- **For significant changes**, open an issue first to align on direction before writing code.
- **Small fixes** (typos, documentation, obvious bugs) can go straight to a PR.

## Development Setup

1. Clone the repo and open `Snowly.xcodeproj` in Xcode 26+.
2. Select the **Snowly** scheme and an iPhone 17 Pro simulator.
3. Hit Run — no additional setup required. Zero external dependencies.

> CloudKit sync requires a real device with an active iCloud account. It is automatically disabled on simulators and during tests.

## Workflow

### Run Tests

```bash
# All unit tests
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Single test suite
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnowlyTests/RunDetectionTests test
```

### GPS Fixture Replay

For changes to the tracking pipeline, replay a GPS fixture through the full production stack:

```
In Xcode: Run → Edit Scheme → Arguments → add -replay_recap zermatt_loop
```

Fixtures are registered in `Snowly/Resources/ReplayFixtures.manifest.json`.

## Code Guidelines

- **No external dependencies** — pure Apple frameworks only. Do not add Swift packages or CocoaPods.
- **No MVVM** — services are the model layer. No `ObservableObject`, no `@Published`, no ViewModels.
- **`Snowly/Shared/`** compiles for both iOS and watchOS. Do not add any platform-specific imports there.
- **Immutability** — return new values; avoid mutating shared state in-place.
- **Test new logic** — use Swift Testing (`@Test`, `#expect`). All test structs must be `@MainActor`.
- **DesignSystem first** — use existing color tokens and spacing constants before introducing new values.

## Pull Request Checklist

- [ ] Tests pass locally (`xcodebuild test`)
- [ ] New logic has unit tests
- [ ] No new external dependencies introduced
- [ ] `Snowly/Shared/` has no platform-specific imports
- [ ] Privacy implications considered (no new data collection without explicit user action)

## License

By contributing, you agree that your contributions will be licensed under the [BSD 3-Clause License](LICENSE).
