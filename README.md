# Snowly

Snowly is a privacy-first ski tracking app for iPhone and Apple Watch, built entirely with Apple frameworks. It records GPS tracks, classifies skiing vs lift vs walking, caches resort data for offline use, and turns a ski day into history, share cards, crew coordination, and gear preparation.

[snowly.app](https://snowly.app) · [Docs](Docs/README.md) · [Backend API](https://github.com/Snowly-app/Snowly-Server)

## Core Principles

- **No external dependencies**: pure Apple frameworks only. No CocoaPods, no Swift Package Manager packages, no third-party SDKs.
- **Privacy by default**: no analytics SDKs, no ad tech, no silent data resale. Location and health data exist to power the app itself.
- **Offline first**: tracking, history, and cached resort data continue to work without cell service.
- **No MVVM**: services are the model layer. Views read from `@Environment` and `@Query`.

## What Lives In This Repo

| Target | Purpose |
|---|---|
| `Snowly` | Main iOS app built with SwiftUI + SwiftData |
| `Snowly Watch App` | watchOS companion and independent tracking app |
| `SnowlyWidgetExtension` | Live Activity widget plus Control Center start control |
| `SnowlyTests` | Unit and integration tests using Swift Testing |
| `SnowlyUITests` | UI smoke tests using XCTest |

## Feature Highlights

- Live ski tracking with GPS speed, altitude, distance, vertical, and a real-time speed curve
- Automatic activity detection for skiing, lift rides, walking, and idle periods
- Apple Watch companion with independent workout capture and phone import
- Resort map caching from OpenStreetMap plus WeatherKit conditions
- Crew location sharing, pins, and invite links backed by the Snowly server
- Gear locker, reminder schedules, and a visual packing checklist
- Session history with run-by-run detail and 1920x1080 landscape share cards
- Data export, local-first persistence, and private CloudKit sync when available

## Requirements

- Xcode 26+
- iOS 26.2+ deployment target
- watchOS 26.2+ deployment target
- No package installation step; the project opens directly in Xcode

## Run Locally

```bash
git clone https://github.com/Snowly-app/Snowly-ios.git
cd Snowly-ios
open Snowly.xcodeproj
```

Then:

1. Select the `Snowly` scheme.
2. Pick an installed iOS simulator such as `iPhone 17 Pro`.
3. Build and run.

To see which destinations exist on your machine:

```bash
xcodebuild -project Snowly.xcodeproj -scheme Snowly -showdestinations
```

## What Works On Simulator vs Device

| Capability | Simulator | Real device |
|---|---|---|
| Core UI, onboarding, history, gear flows | Yes | Yes |
| Fixture replay (`-replay_recap`) | Yes | Yes |
| GPX replay (`-replay_gpx`) | Yes | Yes |
| CloudKit sync | No | Yes |
| HealthKit workout write/read | No | Yes |
| Apple Music playback controls | No | Yes |
| Background location validation | Limited | Yes |
| Apple Watch pairing / workout import | No | Yes |
| Live GPS quality validation | Limited | Yes |

CloudKit is intentionally disabled on simulators and during tests. The app falls back to a local-only store in those environments.

## Backend And Server Profiles

Snowly has two network clients in the iOS app: `CrewAPIClient` and `SkiDataAPIClient`.

- `DEBUG` builds default both clients to `http://localhost:4000/api/v1`
- `RELEASE` builds default both clients to `https://api.snowly.app/api/v1`
- `Settings -> Server Management` lets you store production or self-hosted servers in `ServerProfile`
- Opening the server management screen seeds the default production profile if none exists yet
- If you change the active server and want both upload paths to use it consistently, relaunch the app before validating ski-data upload

If you are only working on offline tracking, UI, history, or design, you do not need a backend running.

## Build And Test

```bash
# Build the iOS app
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all unit + integration tests
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run UI tests only
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnowlyUITests test
```

Replace `iPhone 17 Pro` if your installed simulator differs.

## Debug Replay Flows

Use these when working on tracking, segmentation, or summary screens:

```text
-replay_recap zermatt_loop
```

Loads a JSON fixture through the production pipeline at launch.

```text
-replay_gpx ZermattLoop
-replay_speed 4
```

Replays `Debug/Locations/ZermattLoop.gpx` as a synthetic live session. GPX filenames are case-sensitive.

More detail: [Local Development](Docs/HowTo/LocalDevelopment.md), [Fixture Replay](Docs/Testing/FixtureReplay.md)

## Project Map

```text
Snowly/
  Models/          SwiftData models for sessions, runs, gear, user data, and local settings
  Services/        App services, algorithms, networking, replay, and integrations
  Views/           SwiftUI screens for tracking, history, gear, profile, and onboarding
  Shared/          Platform-neutral types shared by iOS, watchOS, and widgets
  DesignSystem/    Tokens for color, type, spacing, charts, corners, and animation

SnowlyWatch/
  Services/        Watch connectivity, GPS, workout lifecycle, haptics
  Views/           Idle, active workout, controls, and summary screens
  Complications/   Watch complication widgets

SnowlyWidgetExtension/
  Live Activity and Control Center widgets
```

## Documentation Map

- [Docs/README.md](Docs/README.md): developer doc index
- [Docs/HowTo/LocalDevelopment.md](Docs/HowTo/LocalDevelopment.md): local setup, backend behavior, simulator/device matrix
- [Docs/Architecture/Overview.md](Docs/Architecture/Overview.md): service graph and architectural rules
- [Docs/Testing/Overview.md](Docs/Testing/Overview.md): testing conventions and coverage goals
- [Docs/Operations/MainBranchMergeChecklist.md](Docs/Operations/MainBranchMergeChecklist.md): pre-merge checklist for `main`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow expectations. Community participation is covered by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Security issues should go through [SECURITY.md](SECURITY.md).

## License

Snowly is released under the [BSD 3-Clause License](LICENSE).
