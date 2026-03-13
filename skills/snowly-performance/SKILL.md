---
name: snowly-performance
description: Use when writing or reviewing performance-sensitive code in Snowly. Covers SwiftData batch sizing, @Observable granularity, GPS pipeline hot-path rules, SwiftUI render budget, and profiling checkpoints. Read snowly-architecture first for structural context.
user-invocable: true
---

# Snowly Performance

## When Invoked

Operate in one of two modes:

- **Audit mode** (default): Review the specified file(s) or feature for performance violations. Produce a findings report with severity and fix for each issue.
- **Profile guidance mode**: If the user says "profile", "slow", or asks what to measure, provide the profiling checklist for the relevant subsystem (GPS pipeline, SwiftData, SwiftUI, memory, battery).

If no target is specified, ask: _"Which file or subsystem should I audit or profile?"_

---

## Execution Steps

### Audit Mode

1. Read the target files.
2. Check each file against the **Architectural Rules** and **Runtime Rules** below.
3. Output a findings table (see **Output**).
4. List any pre-ship checklist items that are at risk.

### Profile Guidance Mode

1. Identify the subsystem (GPS pipeline / SwiftData / SwiftUI / memory / battery).
2. Output the relevant profiling checkpoints from **Section 3** below.
3. State the pass/fail thresholds.

---

## Domain Reference

### 1. Architectural Rules (Performance-Motivated)

These structural decisions exist because of performance constraints. Violating them restores the problem they solved.

**1.1 `TrackPoint` is never a SwiftData `@Model`**
Serialize `[TrackPoint]` as binary `Data` with `@Attribute(.externalStorage)` on `SkiRun.trackData`. A full season produces 100k+ GPS points — `@Model` children at that scale cause fetch latency, change-tracking overhead, and CloudKit batch explosion.
- Rule: Any new high-frequency time-series data (sensor samples, heart rate, accelerometer) follows the same pattern: serialize as `Data`, store with `.externalStorage`, decode lazily.

**1.2 `Shared/` constants are `nonisolated`**
`SharedConstants` values are `nonisolated static let`. This provides zero-overhead access from any actor without a context switch.
- Rule: Frequently-accessed constants must be `nonisolated static let`. Never add actor isolation to a pure constant.

**1.3 Pure-function services are `static enum`, not `@Observable`**
`RunDetectionService` and `StatsService` are called in the GPS hot path at ~1 Hz. Making them `@Observable` adds change-tracking overhead on every call.
- Rule: Stateless computation services are `enum` with `static func`. Promote to a class only when persistent state or side effects are genuinely required.

**1.4 Dual `ModelContainer` separates CloudKit sync from local reads**
`DeviceSettings` lives in a local-only store. Reads never contend with CloudKit's network sync queue.
- Rule: New local-only settings go into `DeviceSettings`. Do not add them to a synced model.

**1.5 `@Attribute(.externalStorage)` for binary blobs**
Large binary `Data` fields (>~1 KB) on `@Model` classes use `.externalStorage` to prevent bloating the SQLite WAL and slowing batch fetches.
- Rule: Any `Data` field on a `@Model` that can exceed ~1 KB must use `@Attribute(.externalStorage)`: encoded point arrays, images, map snapshots, sensor buffers.

---

### 2. Runtime Performance Rules

**2.1 `@Observable` dependency granularity**
`@Observable` instruments individual property accesses. A view re-renders only when accessed properties change.
- Do not read service properties you don't need in `body`.
- Do not pass an entire service to a child view when only one property is needed — pass the scalar value.
- Do not compute expensive derived values inline in `body` — assign to a `let` first.

```swift
// GOOD — child only re-renders when speed changes
SpeedLabel(speed: trackingService.currentSpeed)

// BAD — child re-renders on any change to trackingService
SpeedLabel(service: trackingService)
```

**2.2 Speed curve render budget**
`SpeedCurveView` must maintain a capped, frozen point array, not render directly from the live buffer.
- Max **300 points** in the rendered buffer (~10 min at 2-second cadence). Drop oldest-first beyond this cap.
- Apply **one-sided EMA** (α = 0.35) in the data pipeline before appending — not inside `body`.
- `FrozenPoint` structs must be `Identifiable` and `Equatable` for diffing. Never use `UUID()` generated inside `body` as an id.

**2.3 Haversine over `CLLocation` in hot paths**
Use `TrackPoint.distance(to:)` (pure-Swift Haversine) in GPS-frequency code. Reserve `CLLocation` allocation for HealthKit route building and map rendering only.

**2.4 `CircularBuffer` for fixed-capacity windows**
`Utilities/CircularBuffer.swift` provides O(1) append with no reallocation. Use it for any sliding window over GPS points, speed samples, or motion readings that can exceed ~100 elements in normal use. Never use `Array.removeFirst()` for this purpose.

**2.5 Passive location off the tracking pipeline**
`LocationTrackingService` has passive (map display) and active (tracking stream) modes. The Kalman filter, dwell-time logic, and segment finalizer run only during active tracking.
- Do not route passive reads through the tracking pipeline.
- For display-only location (e.g., map centering), use `locationService.recentTrackPointsSnapshot()`.

**2.6 No `DispatchQueue.main.async` in services**
All services are `@MainActor`. State mutations are already on the main thread — extra dispatch adds latency.
- Rule: Never use `DispatchQueue.main.async` or `Task { @MainActor in }` inside a service to post back to the main thread. The service is already there.

**2.7 State persistence on a 30-second interval**
`TrackingStatePersistence` writes crash-recovery state every 30 s (`SharedConstants.statePersistenceInterval`), not per GPS update.
- Rule: Any new crash-recovery or heartbeat persistence must use a timer-based interval. Per-update disk writes drain battery and saturate I/O.

**2.8 Battery-aware GPS interval**
GPS update cadence is controlled by `DeviceSettings.trackingUpdateIntervalSeconds`. Cold weather degrades battery by `SharedConstants.coldWeatherBatteryPenalty` (30%).
- Rule: Never hardcode a GPS rate. Reuse `LocationTrackingService` stream; do not add a separate location subscription.

---

### 3. Profiling Guidance

#### GPS Pipeline Checkpoints

Hot path per GPS update:
```
CLLocationUpdate → TrackPoint → GPSKalmanFilter → RunDetectionService.detect() → SegmentFinalizationService → state mutation → @Observable notification
```

Profile in order when CPU is high during tracking:

| Step | Tool | Target |
|------|------|--------|
| Kalman filter | Time Profiler | < 0.1 ms per point |
| `detect()` | Time Profiler | < 0.05 ms, zero allocations |
| `@Observable` notification rate | SwiftUI Instrument | ≈ GPS update rate (not higher) |

#### SwiftData Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| N+1 fetches | `COREDATA_VERBOSE_SQL=1` shows per-run queries | Add `relationshipKeyPathsForPrefetching` |
| `trackData` decoded at list render | Memory grows on scroll | Decode only in session detail view |
| Blob in SQLite WAL | Slow batch fetch | Add `@Attribute(.externalStorage)` |

#### SwiftUI Checkpoints

| View | Expected Body Rate | Failure Signal |
|------|--------------------|----------------|
| `ActiveTrackingView` | ~1 Hz (matches GPS) | Higher than GPS rate |
| `SpeedCurveView` | On new point only | Full redraw every frame → `FrozenPoint.Equatable` broken |
| Static rows (Gear, Activity list) | Zero during tracking | Reading a tracking service property it shouldn't |

#### Memory Checkpoints (after 60-min simulated session)

| Check | Pass Condition |
|-------|---------------|
| `TrackPoint` allocation count | Bounded by `CircularBuffer` capacity |
| `FrozenPoint` count | ≤ 300 |
| `SkiRun.trackData` decoded | Only when detail view is open |

---

## Output

### Audit Report

```
## Performance Audit: <FileName or Feature>

### Findings
| # | File | Line | Rule | Severity | Fix |
|---|------|------|------|----------|-----|
| 1 | ...  | ...  | ...  | Critical / High / Low | ... |

### Pre-Ship Checklist
- [ ] Main thread max hang < 16 ms
- [ ] processTrackPoint() average < 2 ms
- [ ] Memory footprint does not grow linearly with session duration
- [ ] Battery drain rate comparable to baseline (< 10% increase)
```

### Profile Guidance Output

List the applicable profiling checkpoints as a numbered checklist with the Xcode instrument to use and the pass/fail threshold for each.
