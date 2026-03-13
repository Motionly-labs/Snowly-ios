# Contributing to Snowly

Snowly is built by skiers, for skiers. Keep changes focused, technically defensible, and documented when behavior changes.

## Before You Start

- Check existing issues or discussions before starting a larger change.
- Open an issue first for product direction changes, schema changes, new capabilities, or anything that affects privacy.
- Small fixes can go straight to a pull request.

## Development Setup

1. Clone the repository and open `Snowly.xcodeproj` in Xcode 26+.
2. Select the `Snowly` scheme and an installed iOS 26.2+ simulator.
3. Run the app. No CocoaPods or Swift packages are required.

Use this if you need to confirm the exact simulator names installed on your machine:

```bash
xcodebuild -project Snowly.xcodeproj -scheme Snowly -showdestinations
```

Local setup details, backend defaults, and simulator/device limits live in [Docs/HowTo/LocalDevelopment.md](Docs/HowTo/LocalDevelopment.md).

## Workflow Expectations

- Keep PRs focused. Avoid mixing unrelated refactors, product work, and formatting churn.
- Update docs in the same PR when you change architecture, setup, permissions, product language, or user-visible behavior.
- Do not add external dependencies without explicit maintainer approval.
- Preserve the project rules: no MVVM, no `ObservableObject`, no `@Published`, no platform-specific imports in `Snowly/Shared/`.
- Add or update tests for new logic. Pure algorithm changes should come with targeted test coverage.

## Validation

### Build And Test

```bash
# Unit + integration tests
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# UI tests
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnowlyUITests test
```

### Replay And Tracking Checks

For changes to the tracking pipeline, replay a known fixture through the production stack:

```text
In Xcode: Run -> Edit Scheme -> Arguments -> add -replay_recap zermatt_loop
```

For GPX-based live-session testing:

```text
-replay_gpx ZermattLoop
-replay_speed 4
```

More detail: [Docs/Testing/FixtureReplay.md](Docs/Testing/FixtureReplay.md)

### Device-Only Checks

These must be validated on real hardware when touched:

- CloudKit sync
- HealthKit authorization and workout write
- Apple Music playback
- Background location behavior
- Apple Watch pairing, independent workouts, and watch import
- Notifications for crew pins and gear reminders

## Backend Notes

- `DEBUG` builds default network clients to `http://localhost:4000/api/v1`
- `RELEASE` builds default network clients to `https://api.snowly.app/api/v1`
- `Settings -> Server Management` stores reusable server profiles in local SwiftData
- If you change the active server and need to validate ski-data upload, relaunch before testing that flow

If your work is fully offline or UI-only, you do not need a backend running.

## Pull Request Checklist

- [ ] Tests relevant to the change pass locally
- [ ] New logic has unit or integration coverage
- [ ] Docs were updated if setup, behavior, architecture, or product copy changed
- [ ] No external dependencies were introduced
- [ ] `Snowly/Shared/` remains platform-neutral
- [ ] Privacy implications were reviewed
- [ ] Permission strings / privacy manifest were updated if capabilities changed

## License

By contributing, you agree that your contributions will be licensed under the [BSD 3-Clause License](LICENSE).
