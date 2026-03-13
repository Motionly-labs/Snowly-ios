# Snowly Developer Documentation

Reference docs for architecture, setup, testing, product constraints, and release readiness.

---

## Start Here

| Document | Why start here |
|---|---|
| [Project README](../README.md) | Public-facing overview, platform requirements, and local run commands |
| [Local Development](HowTo/LocalDevelopment.md) | Simulator vs device behavior, backend defaults, replay tooling, and common setup gotchas |
| [Main Branch Merge Checklist](Operations/MainBranchMergeChecklist.md) | Pre-merge checklist for docs, privacy, tests, and manual validation |

---

## Architecture

| Document | Purpose |
|---|---|
| [Architecture Overview](Architecture/Overview.md) | Layer diagram, service inventory, and core design principles |
| [Data Models](Architecture/DataModels.md) | SwiftData dual store, `TrackPoint` blob storage, denormalization |
| [State Management](Architecture/StateManagement.md) | `@Observable` + `@Environment`, no MVVM, `@Query` in views |
| [Watch App](Architecture/WatchApp.md) | Watch companion vs independent mode, `WatchMessage`, shared-code constraints |

---

## Product And Pipelines

| Document | Purpose |
|---|---|
| [Product Roadmap](Product/Roadmap.md) | Product priorities and sequencing |
| [Gear Locker + Checklist Requirements](Product/GearUsageMaintenanceRequirements.md) | Product spec for locker gear, reminder schedules, and the visual checklist |
| [GPS Pipeline](Pipelines/GPSPipeline.md) | End-to-end data flow from Core Location to SwiftData |
| [Kalman Filter](Pipelines/KalmanFilter.md) | Constant-velocity filter design and tuning |
| [Activity Detection](Pipelines/ActivityDetection.md) | Feature extraction, classification rules, hysteresis |
| [Segment Lifecycle](Pipelines/SegmentLifecycle.md) | Segment state machine, validation, persistence |

---

## How-To Guides

| Document | Purpose |
|---|---|
| [Local Development](HowTo/LocalDevelopment.md) | Run the app locally and choose the right environment for each feature |
| [Add a New Metric](HowTo/AddNewMetric.md) | Extend `CompletedRunData`, persistence, and UI |
| [Add a New Service](HowTo/AddNewService.md) | Protocol, `@Observable` service, `AppServices` wiring, mocks |
| [Add a SwiftData Migration](HowTo/AddSwiftDataMigration.md) | Versioning, lightweight migrations, CloudKit-safe schema work |

---

## Design, Testing, And Reference

| Document | Purpose |
|---|---|
| [Design System Tokens](DesignSystem/Tokens.md) | Color, typography, spacing, corner radius, animation tokens |
| [Design System Usage](DesignSystem/Usage.md) | Patterns and constraints for using the design system correctly |
| [Testing Overview](Testing/Overview.md) | Frameworks, coverage targets, and what to test vs skip |
| [Writing Tests](Testing/WritingTests.md) | Unit, stateful-service, and integration test patterns |
| [Fixture Replay](Testing/FixtureReplay.md) | JSON fixtures, launch arguments, replay pipeline internals |
| [Constants Reference](Reference/Constants.md) | `SharedConstants.swift` values and rationale |
| [File Index](Reference/FileIndex.md) | Significant source files and their roles |
| [Glossary](Reference/Glossary.md) | Product and pipeline terminology |

---

## Build And Test Commands

Use `xcodebuild -project Snowly.xcodeproj -scheme Snowly -showdestinations` first if you are unsure which simulator names are installed.

```bash
# Build
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build

# All unit + integration tests
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           test

# UI tests only
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -only-testing:SnowlyUITests \
           test
```

---

## Fast Answers

**How do I run the app without a backend?**  
[Local Development](HowTo/LocalDevelopment.md#backend-defaults-and-server-management)

**How do I replay a known ski day?**  
[Fixture Replay](Testing/FixtureReplay.md)

**Why is CloudKit not active in the simulator?**  
[Local Development](HowTo/LocalDevelopment.md#simulator-vs-device)

**Where should I document behavior changes before merging to `main`?**  
[Main Branch Merge Checklist](Operations/MainBranchMergeChecklist.md)

**Why is `TrackPoint` stored as a blob instead of `@Model` rows?**  
[Data Models](Architecture/DataModels.md#trackpoint-storage-design)

---

## Key Technical Facts

- No MVVM: services are the model layer; views use `@Environment` and `@Query`
- `TrackPoint` is not `@Model`: runs store serialized track data to stay performant with large histories
- Only `.skiing` segments contribute to session totals; lift and walk are still recorded for context
- CloudKit is disabled on simulators and during tests, then falls back to local-only persistence
- `DEBUG` network clients default to `http://localhost:4000/api/v1` unless a persisted active server overrides them at launch
- There are no third-party dependencies in this repository
