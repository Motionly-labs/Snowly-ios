# GPS Pipeline

The end-to-end data flow from raw GPS observation to persisted `SkiRun` objects.

This document is the entry point for understanding the tracking pipeline. Each stage links to its own detailed document.

---

## End-to-End Diagram

```
CLLocationManager
  │  (delegate callbacks)
  ▼
LocationTrackingService
  │  emits TrackPoint (timestamp, lat, lon, alt, speed,
  │                    horizontalAccuracy, verticalAccuracy, course)
  ▼
TrackingEngine  (Swift actor — off MainActor)
  │
  ├─1─ GPSKalmanFilter.update(point:)
  │      → FilteredTrackPoint (smoothed position + estimated speed)
  │
  ├─2─ RunDetectionService.analyze(point:recentPoints:previousActivity:motion:)
  │      ├─ MotionEstimator.transitionEstimate(...)  (4 s window)
  │      ├─ MotionEstimator.steadyEstimate(...)      (12 s window)
  │      └─ → DetectionDecision (raw activity + shouldAccelerateDwell)
  │
  ├─3─ SessionTrackingService.applyDwellTime(...)
  │      → stable DetectedActivity (hysteresis applied)
  │
  ├─4─ SegmentFinalizationService.processPoint(_:activity:)
  │      → accumulates TrackPoints per activity type
  │      → (on type change or idle timeout) finalizeCurrentSegment()
  │           ├─ SegmentValidator.effectiveType(...)
  │           │    → nil (discard) | .walk (demote) | unchanged
  │           └─ CompletedRunData (immutable, in-memory)
  │                (trackData encoded off-MainActor via Task.detached)
  │
  └─ (batched back to @MainActor ~1 Hz)
       SessionTrackingService publishes:
         currentSpeed, currentAltitude, maxSpeed, totalDistance, totalVertical, runCount

  ▼
(session end — stopTracking() called)
SessionTrackingService.saveSession(to:resort:)
  │
  ├─ SkiSession @Model   (denormalized aggregates from .skiing runs only)
  └─ [SkiRun] @Model     (one per CompletedRunData with non-nil effectiveType)
       └─ trackData: Data?  (JSON-encoded [TrackPoint])
  │
  ▼
SwiftData ModelContext.save()
  └─ CloudKit sync (when enabled)
```

---

## Stage 1: GPS Acquisition

`LocationTrackingService` uses `CLLocationManagerDelegate` and converts each `didUpdateLocations` callback into a `TrackPoint`. Configuration:

- `distanceFilter = 5`
- Accuracy: `.best`
- Activity type: `.fitness`
- Background modes enabled only during active tracking

Each update is converted to a `TrackPoint` value type and emitted on the stream.

---

## Stage 2: Kalman Filtering

`GPSKalmanFilter.update(point:)` processes each `TrackPoint` through three independent constant-velocity filters (East, North, Altitude) in an ENU local coordinate frame. The output `FilteredTrackPoint` carries a smoothed position and a filter-derived `estimatedSpeed`.

See [Kalman Filter](KalmanFilter.md) for the full algorithm.

---

## Stage 3: Activity Detection

`RunDetectionService.analyze(...)` computes two `MotionEstimate` values (transition window and steady window) via `MotionEstimator`, classifies each independently, resolves any conflict, and returns a `DetectionDecision` with a raw activity and a `shouldAccelerateDwell` flag.

See [Activity Detection](ActivityDetection.md) for the decision tree, confidence formula, and conflict resolution rules.

---

## Stage 4: Dwell-Time Hysteresis

`SessionTrackingService.applyDwellTime(...)` applies minimum-duration hysteresis before promoting a raw activity to the stable tracked state. This is a pure function:

```swift
static func applyDwellTime(
    rawActivity: DetectedActivity,
    currentActivity: DetectedActivity,
    candidateActivity: DetectedActivity?,
    candidateStartTime: Date?,
    timestamp: Date
) -> DwellResult
```

The function returns a `DwellResult` containing the stable activity, the current candidate, and the candidate start time. The caller owns all state — the function does not mutate anything.

---

## Stage 5: Segment Accumulation

`SegmentFinalizationService.processPoint(_:activity:)` appends the current `TrackPoint` to the active segment, or finalizes the current segment and starts a new one when the stable activity changes.

Finalization produces a `CompletedRunData` struct. Track data is encoded to JSON in a `Task.detached` to avoid blocking the main thread.

See [Segment Lifecycle](SegmentLifecycle.md) for the state machine, validator gates, and persistence details.

---

## Metric Accumulation Rules

Session metrics are computed exclusively from segments with `activityType == .skiing`:

| Metric | Source |
|---|---|
| `totalDistance` | Sum of `SkiRun.distance` where `activityType == .skiing` |
| `totalVertical` | Sum of `SkiRun.verticalDrop` where `activityType == .skiing` |
| `maxSpeed` | Max of `SkiRun.maxSpeed` where `activityType == .skiing` |
| `runCount` | Count of `SkiRun` where `activityType == .skiing` |

Lift and walk segments are recorded in `SkiRun` for map visualization and session detail views, but they do not contribute to session totals.

---

## Data Flow Invariant

**All downstream consumers must read GPS-derived values exclusively from `SessionTrackingService`, never directly from `LocationTrackingService`.**

| Property | Source | DO NOT use |
|----------|--------|-----------|
| `currentSpeed` | `SessionTrackingService.currentSpeed` (Kalman-filtered) | `LocationTrackingService.currentSpeed` (raw GPS) |
| `currentAltitude` | `SessionTrackingService.currentAltitude` (Kalman-filtered) | `LocationTrackingService.currentAltitude` (raw GPS) |

`LocationTrackingService` is a GPS hardware adapter. Its raw values bypass the Kalman filter and must not be consumed by views, other services, or analytics. The only consumers of raw `TrackPoint` data are:

1. `TrackingEngine.ingest()` — feeds them into the Kalman filter
2. `TrackingEngine.primeRecentWindow()` — seeds the detection history buffer
3. `CrewService.buildLocationUpload()` — location-sharing (different domain; raw GPS position is correct here)

The `LocationProviding` protocol deliberately exposes **no raw GPS sensor values** — only stream and authorization APIs.

---

## GPS Quality

The filter and detection pipeline is designed for "good outdoor GPS" — open sky, low multipath. On ski slopes, GPS quality is generally good. Known degraded conditions:

| Condition | Effect | Recovery |
|---|---|---|
| Gondola tunnel | GPS dropout → horizontal/vertical accuracy spikes → `hasReliableAltitudeTrend = false` | Dwell timer preserves current activity until exit |
| Dense forest | Multipath noise → position jitter | Kalman filter smooths; confidence drops; steady window dominates |
| Lift station (stationary) | Speed near zero → may classify as idle | Dwell timer prevents rapid state changes |
| Session start | Insufficient history → `confidence` low | Transition window falls back to speed-only rules |

---

## Watch Import Path

When a watch independent session is imported, `WatchBridgeService` calls the same production pipeline stages (Kalman filter → detection → dwell → segmentation) on the batch of watch track points. The result is persisted identically to a phone-tracked session. See [Watch App](../Architecture/WatchApp.md) for details.
