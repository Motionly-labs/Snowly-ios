# Testing Overview

Test framework conventions, coverage targets, and what to test vs what to skip.

---

## Frameworks

| Target | Framework | Location |
|---|---|---|
| Unit + integration tests | Swift Testing (`@Test`, `#expect`, `#require`) | `SnowlyTests/` |
| UI tests | XCTest | `SnowlyUITests/` |

All unit and integration tests use Apple's Swift Testing framework introduced in Xcode 15. There is no XCTest in `SnowlyTests/`. Do not mix frameworks — a file that imports both `Testing` and `XCTest` will produce confusing results.

---

## Test Struct Conventions

Every test struct in `SnowlyTests/` must be `@MainActor`:

```swift
@MainActor
struct MyServiceTests {
    // ...
}
```

This is required because most services are `@MainActor final class`. Accessing them from a non-isolated context produces data race warnings.

---

## Coverage Targets

| Layer | Target |
|---|---|
| Pure-function services (`MotionEstimator`, `RunDetectionService`, `SegmentValidator`, `StatsService`) | ≥ 90% |
| `GPSKalmanFilter` | ≥ 90% |
| `SegmentFinalizationService` | ≥ 80% |
| Integration (full pipeline via fixture replay) | ≥ 70% |

Coverage is not measured automatically in CI today. The targets are design goals, verified by manual review when touching these files.

---

## What to Test

- All pure-function services: every branch of the decision tree, every boundary condition
- `GPSKalmanFilter`: initialization, predict-update cycle, velocity estimation, reset
- `SegmentFinalizationService`: type transitions, idle timeout, finalization with validator interaction
- `SegmentValidator`: each validation gate (duration, altitude, speed), demotion, discard
- `SessionTrackingService.applyDwellTime(...)`: all seven transition types, accelerated dwell path
- Fixture-based integration: full pipeline on known GPS data produces expected run count / metrics

---

## What Not to Test

- View rendering (no snapshot tests; the design system tokens are the contract)
- `CLLocationManager` behavior (not mockable; covered by field testing)
- CloudKit sync (requires entitlements; tested manually on device)
- HealthKit writes (mocked at the `HealthKitProviding` protocol level)
- `AppServices` init (no behavior; it's wiring only)

---

## Running Tests

```bash
# All unit tests
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           test

# Single test by name
xcodebuild -project Snowly.xcodeproj \
           -scheme Snowly \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -only-testing:SnowlyTests/MotionEstimatorTests/estimate_emptyHistory_usesInstantaneousSpeed \
           test
```

---

## Test Isolation

Tests that write to `TrackingStatePersistence` (crash-recovery `UserDefaults`) should be grouped in a `@Suite(.serialized)` to prevent data races:

```swift
@Suite(.serialized)
@MainActor
struct TrackingStatePersistenceTests {
    // ...
}
```

Tests for pure functions have no shared state and can run in parallel (the default).

---

## Related Documents

- [Writing Tests](WritingTests.md) — code patterns for unit and integration tests
- [Fixture Replay](FixtureReplay.md) — using GPS fixtures for integration testing
