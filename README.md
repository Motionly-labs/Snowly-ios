# Snowly

iOS + watchOS ski tracking app. [snowly.app](https://snowly.app) · [Why Snowly](https://github.com/Snowly-app)

## Design Principles

These guide every contribution decision:

- **No external dependencies** — Pure Apple frameworks only (no CocoaPods, SPM packages, or third-party SDKs).
- **Privacy by default** — No accounts, no telemetry, no third-party analytics. Location data stays on-device (`NSFileProtectionComplete`). Never add data collection without an explicit user action.
- **Offline first** — Full tracking works without cell service. Ski maps are cached locally.
- **No MVVM** — Services are the model layer. No `ObservableObject`, no `@Published`, no ViewModels.

## Features

- **Live tracking** — GPS speed, altitude, distance, and vertical with real-time bezier speed curves
- **Automatic run detection** — Distinguishes ski runs from lift rides using speed, altitude trends, and CoreMotion data
- **Crew** — Create a group, invite friends via deep link, and see everyone's real-time location on the map. Drop pins with messages to coordinate meet-ups on the mountain
- **Apple Watch companion** — Independent watch tracking with HealthKit workout integration, haptic feedback, and complications
- **Gear locker + visual checklist** — Create gear once in your locker, attach reminder schedules, and pull it into body-zone checklists with an interactive skier figure
- **Session history** — Browse past ski days with detailed run-by-run breakdowns
- **Share cards** — Generate 1080×1920 cards with your route map and stats
- **Ski area maps** — Automatic resort detection with trail/lift data from OpenStreetMap
- **Music control** — In-app Now Playing controls via MusicKit
- **Weather** — On-mountain conditions via WeatherKit
- **Metric & Imperial** — Full unit system support

## Requirements

- iOS 26.2+
- watchOS (for companion app)
- Xcode 26+
- No external dependencies — pure Apple frameworks

## Getting Started

```bash
# Clone the repo
git clone https://github.com/Snowly-app/Snowly.git
cd Snowly

# Open in Xcode
open Snowly.xcodeproj
```

Select the **Snowly** scheme, pick an iPhone simulator, and hit Run. The app uses no CocoaPods, SPM packages, or external dependencies.

> **Note:** CloudKit sync requires a real device with an iCloud account. It is automatically disabled on simulators and during tests.

## Build & Test

```bash
# Build
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run a single test
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnowlyTests/RunDetectionTests test
```

## Project Structure

```
Snowly/
├── SnowlyApp.swift          # Entry point, service wiring, model container setup
├── Models/                  # SwiftData @Model classes (SkiSession, SkiRun, Resort, Gear, ...)
│   └── Crew/                # Server-managed crew DTOs (Crew, CrewPin, MemberLocation, ...)
├── Services/                # Business logic services with protocol-based testability
│   ├── Protocols/           # Service protocols for dependency injection
│   ├── CrewService          # Crew lifecycle and real-time location sharing
│   ├── CrewAPIClient        # Server communication for crew features
│   ├── CrewKeychainService  # Secure credential storage for crew auth
│   └── CrewPinNotification… # Local notifications for crew pins
├── Views/
│   ├── Home/                # Active tracking, speed curve, music controls
│   │   └── Crew/            # Crew map overlays, pin compose, member annotations
│   ├── Gear/                # Locker gear, reminder schedules, and visual checklists
│   ├── Activity/            # Session history and run details
│   ├── Profile/             # User settings and privacy
│   ├── Onboarding/          # First-launch flow
│   └── Shared/              # Reusable view components
├── Shared/                  # Types shared between iOS and watchOS (TrackPoint, WatchMessage, ...)
├── DesignSystem/            # Color tokens, typography, spacing, corner radii
├── Extensions/              # Swift extensions (Date, Array, TrackPoint)
├── Utilities/               # CircularBuffer, state persistence, DeepLinkHandler, ResortResolver
└── Resources/               # Localizable.xcstrings, assets

SnowlyWatch/
├── SnowlyWatchApp.swift     # Watch entry point
├── Services/                # Watch-specific services (connectivity, location, workout, haptics)
├── Views/                   # Watch UI (idle, active workout, summary, controls)
├── DesignSystem/            # Watch color tokens, spacing
└── Complications/           # Active session widget
```

## Architecture

Services are created once in `AppServices` and injected into the SwiftUI view hierarchy via `@Environment`. Views access services through `@Environment`, never `@State`. This keeps services alive across the entire app lifecycle.

SwiftData uses a dual-store configuration:
- **Synced store** — `SkiSession`, `SkiRun`, `Resort`, `GearSetup`, `GearAsset`, `GearMaintenanceEvent`, `UserProfile` → private iCloud CloudKit (when enabled)
- **Local store** — `DeviceSettings` → stays on-device, never synced

Product terminology is fixed as `gear`, `locker`, `checklist`, and `reminder schedule`. Internal model names remain `GearAsset` and `GearSetup`.

Track points are stored as binary `Data` (Codable `[TrackPoint]` array) rather than individual SwiftData objects to avoid performance issues with large collections.

Run detection combines GPS speed, altitude trends, and CoreMotion accelerometer data — not speed alone — to accurately distinguish skiing from riding a lift.

Crew is a real-time location-sharing feature backed by a remote server. Crew models (`Crew`, `CrewMember`, `CrewPin`, `MemberLocation`) are ephemeral DTOs — not SwiftData — managed entirely by the server. `CrewService` orchestrates the lifecycle, `CrewAPIClient` handles network requests, and `CrewKeychainService` stores auth credentials securely. Invite links use Universal Links and a custom `snowly://` scheme, routed by `DeepLinkHandler`.

## Contributing

Contributions are welcome — bug fixes, new features, translations, or design improvements. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before participating.

## License

BSD 3-Clause License
