# Watch App

How the Apple Watch companion app works in both companion and independent modes, the phone–watch communication protocol, and the `Shared/` platform constraint.

---

## Two Operating Modes

### Companion Mode

The default mode when the paired iPhone is reachable and actively tracking.

```
iPhone                            Apple Watch
──────────────────────────────────────────────
SessionTrackingService            WatchConnectivityService
  │                                 │
  └─ PhoneConnectivityService ──►  receives WatchMessage
       (WCSession sendMessage)         │
                                       └─ updates WorkoutActiveView
```

The watch receives `WatchMessage.liveUpdate(LiveTrackingData)` messages containing `currentSpeed`, `maxSpeed`, `totalDistance`, `totalVertical`, `runCount`, `elapsedTime`, and `batteryLevel`. It displays these values in `WorkoutActiveView` and `StatsPageView`. The watch does not run GPS or activity detection in this mode.

### Independent Mode

Activated when the iPhone is unreachable (left in a ski locker, out of Bluetooth range, etc.).

```
Apple Watch
──────────────────────────────────────────────
WatchWorkoutManager (HealthKit workout session)
  │
  ├─ WatchLocationService (watch GPS)
  │    └─ TrackPoint stream
  │
  └─ RunDetectionService (shared pure functions)
       └─ batched TrackPoints
            │
            (on phone reconnect)
            ▼
iPhone: WatchBridgeService
  └─ GPSKalmanFilter → RunDetectionService → SegmentFinalizationService → SwiftData
```

Track points accumulate on the watch during the workout. When phone connectivity is restored, `WatchConnectivityService` sends `WatchMessage.watchTrackPoints([TrackPoint])` and `WatchMessage.watchWorkoutSummary(IndependentWorkoutSummary)` to the phone. `WatchBridgeService` receives them and runs the full production pipeline (Kalman filter → detection → dwell time → segment validation → SwiftData insert).

---

## `WatchMessage` Protocol

All phone–watch communication uses the typed `WatchMessage` enum serialized over `WCSession`.

**Phone → Watch**

| Message | Payload | Purpose |
|---|---|---|
| `trackingStarted` | `sessionId: UUID` | Notify watch of new session |
| `trackingPaused` | — | Pause watch display |
| `trackingResumed` | — | Resume watch display |
| `trackingStopped` | — | End session on watch |
| `liveUpdate` | `LiveTrackingData` | Push speed, distance, vertical, run count, battery |
| `newPersonalBest` | `metric: String, value: Double` | Trigger haptic + display on watch |
| `unitPreference` | `UnitSystem` | Sync metric/imperial setting |
| `sessionHistory` | `SeasonBestData` | Best-of-season stats for idle screen |

**Watch → Phone**

| Message | Payload | Purpose |
|---|---|---|
| `requestStart` | — | User taps Start on watch |
| `requestPause` | — | User pauses via watch |
| `requestResume` | — | User resumes via watch |
| `requestStop` | — | User stops via watch |
| `requestStatus` | — | Watch requests current state (on reconnect) |
| `watchWorkoutStarted` | `sessionId: UUID` | Begins independent mode session |
| `watchWorkoutSummary` | `IndependentWorkoutSummary` | Summary after independent workout |
| `watchWorkoutEnded` | — | Independent workout finished |
| `watchTrackPoints` | `[TrackPoint]` | GPS points from independent session |

---

## `Snowly/Shared/` Platform Constraint

All files in `Snowly/Shared/` compile for both the iOS target and the watchOS target. This constraint is enforced by membership in both targets' compile sources.

**Prohibited in `Shared/`:**

- `import CoreLocation` class types (e.g., `CLLocation` as a stored property)
- `import UIKit` or `import AppKit`
- `import HealthKit`
- Any type that is unavailable on watchOS

**Permitted in `Shared/`:**

- `import Foundation`
- Plain Swift structs and enums
- `Codable`, `Sendable`, `Equatable` conformances
- `nonisolated static func` algorithms

`TrackPoint`, `FilteredTrackPoint`, `WatchMessage`, `SharedConstants`, `UnitSystem`, and `RunActivityType` all satisfy this constraint. Adding a `CLLocation` extension to `TrackPoint` would break the watchOS build — place such extensions in `Snowly/Extensions/` (iOS-only).

---

## Watch Import Pipeline

When `WatchBridgeService` receives a `watchTrackPoints` message, it calls `SnowlyApp.buildCompletedRuns(from:)` which runs:

1. `GPSKalmanFilter.update(point:)` — smooth watch GPS points
2. `RunDetectionService.detect(...)` — classify each point
3. `SessionTrackingService.applyDwellTime(...)` — apply hysteresis
4. Segment accumulation + `SegmentFinalizationService`-equivalent logic
5. `SegmentValidator.effectiveType(...)` — quality gates
6. `SkiSession` + `[SkiRun]` inserted into SwiftData

The imported session appears in the Activity tab alongside phone-tracked sessions with no special treatment.

---

## Watch View Hierarchy

```
WatchRootView
  ├─ IdleView         (when not tracking)
  └─ WorkoutActiveView (when tracking)
       ├─ StatsPageView    (swipe page)
       ├─ WorkoutControlsView (pause / stop)
       └─ WorkoutSummaryView (after stop)
```

The active session complication (`ActiveSessionWidget`) shows current speed from `LiveTrackingData`.
