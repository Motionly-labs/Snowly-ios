# Architecture Overview

Snowly's layer structure, service inventory, and three design principles that differ from conventional iOS patterns.

---

## Layer Diagram

```
┌─────────────────────────────────────────┐
│  Views (SwiftUI)                        │
│  @Environment injection                 │
│  @Query for SwiftData reads             │
└──────────────────┬──────────────────────┘
                   │ reads / calls
┌──────────────────▼──────────────────────┐
│  Services (@Observable @MainActor)      │
│  SessionTrackingService (orchestrator)  │
│  LocationTrackingService                │
│  MotionDetectionService                 │
│  HealthKitService / Coordinator         │
│  PhoneConnectivityService               │
│  WatchBridgeService                     │
│  SkiMapCacheService                     │
│  MusicPlayerService / SyncMonitorService│
└──────────────────┬──────────────────────┘
                   │ pure calls (no injection)
┌──────────────────▼──────────────────────┐
│  Algorithm layer (enum namespaces)      │
│  GPSKalmanFilter (mutating struct)      │
│  MotionEstimator (nonisolated static)   │
│  RunDetectionService (nonisolated static│
│  SegmentValidator (nonisolated static)  │
│  StatsService (static)                  │
└──────────────────┬──────────────────────┘
                   │ inserts / queries
┌──────────────────▼──────────────────────┐
│  Data Layer (SwiftData @Model)          │
│  SkiSession, SkiRun, Resort             │
│  GearSetup, GearItem, UserProfile       │
│  DeviceSettings (local only)            │
└──────────────────┬──────────────────────┘
                   │ compiles for both targets
┌──────────────────▼──────────────────────┐
│  Shared/ (platform-free)                │
│  TrackPoint, FilteredTrackPoint         │
│  WatchMessage, SharedConstants          │
│  UnitSystem, RunActivityType            │
└─────────────────────────────────────────┘
```

---

## Service Inventory

| Service | Role | Pure? | Protocol | Key Dependencies |
|---|---|---|---|---|
| `SessionTrackingService` | Orchestrator; owns `TrackingEngine` actor, dwell-time filter, live metrics | No | — | `LocationTrackingService`, `MotionDetectionService`, `BatteryMonitorService`, `HealthKitService` |
| `LocationTrackingService` | GPS via `CLLocationUpdate.liveUpdates` async stream | No | `LocationProviding` | CoreLocation |
| `MotionDetectionService` | CoreMotion accelerometer/gyroscope; emits `MotionHint` | No | — | CoreMotion |
| `BatteryMonitorService` | Device battery level observation | No | — | UIDevice |
| `HealthKitService` | HealthKit workout session write | No | `HealthKitProviding` | HealthKit |
| `HealthKitCoordinator` | Coordinates authorization and workout finalization | No | — | `HealthKitService` |
| `GPSKalmanFilter` | Three-axis constant-velocity Kalman filter | Yes (`nonisolated mutating struct`) | — | — |
| `MotionEstimator` | Feature extraction over rolling time windows | Yes (`nonisolated static`) | — | — |
| `RunDetectionService` | Activity classification from `MotionEstimate` | Yes (`nonisolated static`) | — | `MotionEstimator` |
| `SegmentFinalizationService` | Segment state machine; produces `CompletedRunData` | No | — | `SegmentValidator` |
| `SegmentValidator` | Quality gates for completed segments | Yes (`nonisolated static`) | — | — |
| `StatsService` | Season and session aggregate statistics | Yes (`static`) | — | — |
| `PhoneConnectivityService` | `WCSession` delegate; sends live updates to watch | No | — | WatchConnectivity |
| `WatchBridgeService` | Imports watch track points through production pipeline | No | — | `PhoneConnectivityService`, `SessionTrackingService` |
| `SkiMapCacheService` | OpenStreetMap ski area map data cache | No | — | `OverpassService` |
| `MusicPlayerService` | Music playback control | No | — | MediaPlayer |
| `SyncMonitorService` | CloudKit sync status observation | No | — | SwiftData |
| `LiveActivityService` | Live Activity / Dynamic Island updates | No | — | ActivityKit |

---

## `AppServices` Wiring

`AppServices` (`@Observable @MainActor final class`) in `Snowly/SnowlyApp.swift` creates all services once at app launch and stores them as `let` properties. Services are injected at the scene root via `.environment()` and remain alive for the entire app lifecycle.

```swift
@Observable
@MainActor
final class AppServices {
    let locationService: LocationTrackingService
    let motionService: MotionDetectionService
    let trackingService: SessionTrackingService
    // ...

    init() {
        let location = LocationTrackingService()
        let motion = MotionDetectionService()
        // ...
        self.trackingService = SessionTrackingService(
            locationService: location,
            motionService: motion,
            // ...
        )
    }
}
```

The `ModelContainer` uses a dual-store configuration: a CloudKit-synced store for ski data and a local-only store for device settings. See [Data Models](DataModels.md) for details.

---

## Three Design Principles

### 1. No MVVM

Views read directly from `@Observable` services and SwiftData `@Query` results. There are no ViewModels, no `ObservableObject`, and no `@Published` in the codebase. Services are the model layer; views are thin rendering functions.

### 2. Pure Static Functions for Algorithms

`RunDetectionService`, `MotionEstimator`, `SegmentValidator`, and `StatsService` are `enum` namespaces containing only `nonisolated static func` methods. They accept all inputs as parameters and return new values — no stored state, no threading concerns. This makes them trivially testable without mocks.

### 3. Actor–MainActor Split

`SessionTrackingService` runs on `@MainActor` for UI publishing. Heavy per-point computation (Kalman filtering, motion estimation, activity detection) executes in a private `actor` (`TrackingEngine`) off the main thread. Results are batched and sent back to the service via `await`. The UI receives updates approximately once per second, not once per GPS point.

---

## Cross-References

- State management details: [State Management](StateManagement.md)
- Data persistence: [Data Models](DataModels.md)
- Watch companion: [Watch App](WatchApp.md)
- Full GPS pipeline: [GPS Pipeline](../Pipelines/GPSPipeline.md)
