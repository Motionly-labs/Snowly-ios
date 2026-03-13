# Snowly Developer Documentation

Snowly is an iOS + watchOS ski tracking app built with SwiftUI and SwiftData. It tracks GPS position, classifies activity (skiing vs lift vs walk), and produces per-session and season statistics.

This documentation covers architecture, the GPS/detection pipeline, how to extend the app, design system tokens, testing patterns, and a full reference section.

---

## Navigation

| Document | Purpose |
|---|---|
| [Architecture Overview](Architecture/Overview.md) | Layer diagram, service inventory, three core design principles |
| [Data Models](Architecture/DataModels.md) | SwiftData dual store, `TrackPoint` binary blob design, denormalization |
| [State Management](Architecture/StateManagement.md) | `@Observable` + `@Environment`, no MVVM, `@Query` in views |
| [Watch App](Architecture/WatchApp.md) | Companion vs independent mode, `WatchMessage` protocol, `Shared/` constraint |
| [Product Roadmap](Product/Roadmap.md) | Product priorities, phase ordering, and execution guidance for upcoming features |
| [Gear Locker + Checklist Requirements](Product/GearUsageMaintenanceRequirements.md) | Product spec for the locker-first gear flow: gear, reminder schedules, checklists, and the visual checklist |
| [GPS Pipeline](Pipelines/GPSPipeline.md) | End-to-end data flow from `CLLocationManager` to SwiftData |
| [Kalman Filter](Pipelines/KalmanFilter.md) | Three-axis constant-velocity filter, ENU frame, tuning constants |
| [Activity Detection](Pipelines/ActivityDetection.md) | Two-window feature extraction, decision tree, dwell-time hysteresis |
| [Segment Lifecycle](Pipelines/SegmentLifecycle.md) | Segment state machine, validator quality gates, persistence |
| [Add a New Metric](HowTo/AddNewMetric.md) | Step-by-step: `CompletedRunData` → `SkiRun` → UI (example: `avgTurnRate`) |
| [Add a New Service](HowTo/AddNewService.md) | Protocol, `@Observable` class, `AppServices` wiring, mock pattern |
| [Add a SwiftData Migration](HowTo/AddSwiftDataMigration.md) | Next-schema versioning, lightweight vs custom stages, CloudKit constraints |
| [Design System Tokens](DesignSystem/Tokens.md) | Full tables: colors, typography, spacing, corner radius, animations |
| [Design System Usage](DesignSystem/Usage.md) | Correct patterns, dark background convention, metric display |
| [Testing Overview](Testing/Overview.md) | Frameworks, coverage targets, what to test vs skip |
| [Writing Tests](Testing/WritingTests.md) | Unit, stateful-service, and integration test patterns |
| [Fixture Replay](Testing/FixtureReplay.md) | GPS fixture format, `-replay_recap` launch argument, pipeline internals |
| [Constants Reference](Reference/Constants.md) | All `SharedConstants.swift` values with rationale |
| [File Index](Reference/FileIndex.md) | Every significant source file and its one-line role |
| [Glossary](Reference/Glossary.md) | Domain terms: track point, segment, dwell time, ENU frame, etc. |

---

## Quick Links

**Add a metric** → [HowTo/AddNewMetric.md](HowTo/AddNewMetric.md)

**See upcoming product priorities** → [Product/Roadmap.md](Product/Roadmap.md)

**See Gear product requirements** → [Product/GearUsageMaintenanceRequirements.md](Product/GearUsageMaintenanceRequirements.md)

**Understand why a run was misclassified** → [Pipelines/ActivityDetection.md](Pipelines/ActivityDetection.md), then [Reference/Constants.md](Reference/Constants.md)

**Write a test** → [Testing/WritingTests.md](Testing/WritingTests.md)

**Understand why `[TrackPoint]` is a Data blob** → [Architecture/DataModels.md](Architecture/DataModels.md#trackpoint-storage-design)

**Understand `hasReliableAltitudeTrend`** → [Pipelines/ActivityDetection.md](Pipelines/ActivityDetection.md#hasreliablealtitudetrend)

---

## Build and Test Commands

```bash
# Build
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build

# Run all unit tests
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           test

# Run a single test (replace path with actual test name)
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -only-testing:SnowlyTests/MotionEstimatorTests/estimate_emptyHistory_usesInstantaneousSpeed \
           test

# Run UI tests only
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -only-testing:SnowlyUITests \
           test

# Load a GPS fixture at app launch (DEBUG builds)
# In Xcode scheme: Run → Arguments → -replay_recap zermatt_loop
```

---

## Key Technical Facts

- **No MVVM** — services are the model layer; views use `@Environment` and `@Query`
- **`TrackPoint` is not `@Model`** — stored as `JSON Data` in `SkiRun.trackData` to handle 100k+ objects per season
- **Only `.skiing` activity accumulates session metrics** — lift and walk are recorded but excluded from totals
- **`hasReliableAltitudeTrend = false`** is correct behaviour at session start and in GPS-degraded environments
- **Deployment target: iOS 26.2+, watchOS** (Swift 5.0, SwiftUI, SwiftData)
- **No external dependencies** — no CocoaPods, no SPM packages
