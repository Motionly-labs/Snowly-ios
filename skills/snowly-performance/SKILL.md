---
name: snowly-performance
description: Use when writing or reviewing performance-sensitive code in Snowly. Covers GPS pipeline, SwiftData, SwiftUI rendering, concurrency, Watch connectivity, HealthKit batching, motion estimation, Canvas/Path rendering, and memory management. Read snowly-architecture first for structural context.
user-invocable: true
---

# Snowly Performance

## When Invoked

Operate in one of two modes:

- **Audit mode** (default): Review the specified file(s) or feature for performance violations. Produce a findings report with severity and fix for each issue.
- **Profile guidance mode**: If the user says "profile", "slow", or asks what to measure, provide the profiling checklist for the relevant subsystem (GPS pipeline, SwiftData, SwiftUI, concurrency, Watch, HealthKit, motion, Canvas, memory, battery).

If no target is specified, ask: _"Which file or subsystem should I audit or profile?"_

---

## Execution Steps

### Audit Mode

1. Read the target files.
2. Check each file against **all** sections of the Domain Reference below — Architectural Rules, Runtime Rules, Concurrency Rules, Watch & HealthKit Rules, Rendering Rules, and Memory Rules.
3. Output a findings table (see **Output**).
4. List any pre-ship checklist items that are at risk.

### Profile Guidance Mode

1. Identify the subsystem (GPS pipeline / SwiftData / SwiftUI / concurrency / Watch / HealthKit / motion / Canvas / memory / battery).
2. Output the relevant profiling checkpoints from **Section 7** below.
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

### 3. Concurrency Rules

**3.1 `@MainActor` services — no redundant dispatch**
All `@Observable` services (`LocationTrackingService`, `SessionTrackingService`, `HealthKitCoordinator`, `PhoneConnectivityService`, `WatchBridgeService`) are `@MainActor`-isolated.
- Rule: Never wrap state mutations in `DispatchQueue.main.async` or `Task { @MainActor in }` from within these services — the code is already on the main actor.
- Violation signal: `DispatchQueue.main` or `@MainActor in` appearing inside a `@MainActor` class body.

**3.2 `nonisolated` delegate callbacks must dispatch to MainActor**
`CLLocationManagerDelegate`, `WCSessionDelegate`, and other system callbacks are called on arbitrary threads. These methods must be marked `nonisolated` and dispatch to the main actor via `Task { await self.handleX(...) }`.
- Rule: Never access `@Observable` state directly inside a `nonisolated` delegate method. Always dispatch first.
- Rule: Keep the `nonisolated` method body minimal — parse, validate, then dispatch.

```swift
// GOOD — delegate body dispatches immediately
nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
    let filtered = locs.filter { $0.horizontalAccuracy <= threshold }
    Task { await self.processLocations(filtered) }
}

// BAD — accessing @Observable state in nonisolated context
nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
    self.lastLocation = locs.last  // data race
}
```

**3.3 `weak self` in long-lived closures and AsyncStream continuations**
`Task` closures and `AsyncStream` continuations that outlive a single function call must capture `[weak self]` to avoid retain cycles that prevent deallocation.
- Rule: Any `Task { }` stored in a property or any `AsyncStream.Continuation` must use `[weak self]`.
- Exception: Short-lived `Task { }` in a function scope that completes before the function returns can capture `self` strongly.

**3.4 Task cancellation in loops**
Background loops (`while !Task.isCancelled`) must check cancellation at every iteration. Stored `Task` handles must be cancelled in `deinit` or stop methods.
- Rule: Every `while` loop in a `Task` must include `guard !Task.isCancelled else { break }` or `try Task.checkCancellation()`.
- Rule: Every task stored as a property must be explicitly cancelled when the owning service stops.
- Violation signal: A `Task` property that is reassigned without cancelling the previous value.

```swift
// GOOD — cancel before reassign
liveUpdateTask?.cancel()
liveUpdateTask = Task { ... }

// BAD — previous task leaks
liveUpdateTask = Task { ... }
```

**3.5 `nonisolated` pure computation for off-main-actor work**
Heavy pure computations (e.g., `WatchBridgeService.applyPoints()`, `MotionEstimator` window building) should be `nonisolated` functions that receive state as parameters and return results — no actor hop required.
- Rule: Functions that only transform input → output without reading/writing `@Observable` state should be `nonisolated static func` or free functions. This allows the compiler to run them off the main actor.

---

### 4. Watch Connectivity & HealthKit Rules

**4.1 Pending Watch track points must be capped**
`WatchBridgeService` caps `pendingWatchTrackPoints` at 100k entries. Beyond this, new points are dropped with a warning log.
- Rule: Any buffer that accumulates data from an external source (Watch, network) must have a hard cap. Log when the cap is hit; never grow unbounded.

**4.2 Live data uses fire-and-forget; queued data uses reliable send**
`sendLive()` transmits ephemeral real-time data (current speed, heart rate) that is acceptable to lose. `send()` queues important data (session summaries, track points) for reliable delivery.
- Rule: Never queue high-frequency ephemeral data via reliable `send()` — it fills the WCSession transfer queue and stalls important payloads.
- Rule: Never use fire-and-forget `sendLive()` for data that must survive connectivity gaps.

**4.3 `withObservationTracking` + debounce for Watch state sync**
`WatchBridgeService` uses `withObservationTracking` with a 200 ms debounce to batch rapid state changes into single Watch transfers.
- Rule: Any `withObservationTracking` loop that triggers I/O or network must include a debounce (`Task.sleep`) of ≥ 100 ms. Without debounce, rapid property changes fire one transfer per change.
- Violation signal: `withObservationTracking` calling `send()` or `transferFile()` without an intervening sleep.

**4.4 HealthKit flush interval — batch, don't stream**
`HealthKitCoordinator` buffers route points and distance samples, flushing every 3 seconds (`flushInterval`). A single `activeFlushTask` prevents concurrent HK submissions.
- Rule: Never call `HKWorkoutRouteBuilder.insertRouteData()` or `HKHealthStore.save()` per GPS update. Always batch with a timer-based flush.
- Rule: Only one flush task may be in flight at a time. Guard with a stored `Task?` and `await` completion before starting the next.

**4.5 HealthKit buffer trim — keep tail, drop head**
When `pendingRoutePoints` exceeds the max buffer size (1,800), trim to the tail (most recent) points.
- Rule: Buffer trim must preserve the newest data. Use `suffix()` or equivalent, never `prefix()`.
- Rule: On session finalize, drain all remaining buffered data before calling `endCollection()`.

**4.6 Heart rate samples use `CircularBuffer`**
`WatchBridgeService` stores heart rate in a `CircularBuffer<HeartRateSample>` to cap memory for continuous BPM data over multi-hour sessions.
- Rule: Any per-second or sub-second sample stream (heart rate, accelerometer, gyroscope) must use `CircularBuffer`, not `Array.append()`.

---

### 5. Motion Estimation Rules

**5.1 `reserveCapacity` for window builders**
`EstimateWindowBuilder` pre-allocates capacity for altitude arrays (`reserveCapacity(16)`) to avoid reallocation during iteration.
- Rule: Any accumulator struct used in a per-point loop must call `reserveCapacity` with the expected window size at initialization.

**5.2 Specialized median filter for small windows**
`medianFilter3()` is a hardcoded 3-element median (the common case) that avoids `sorted()`. The general `medianFilter()` falls back to `sorted()` for larger windows.
- Rule: When window size is known at compile time and ≤ 5, use a specialized comparator chain instead of `sorted()`. The O(n log n) sort is disproportionately expensive for tiny n due to function call overhead.
- Violation signal: Calling `sorted()` inside any per-point loop with a fixed small window.

**5.3 Single-pass dual-window estimation**
`MotionEstimator` computes both transition (short) and steady (long) motion estimates in a single iteration over the point buffer — not two separate passes.
- Rule: When computing multiple windowed statistics over the same buffer, fuse into a single pass. Two passes double the cache pressure and iteration overhead.

---

### 6. Canvas & Path Rendering Rules

**6.1 Segment batching — batch by state, not by point**
`CurveRendering` groups contiguous same-state points into a single `Path`, producing O(S) path objects where S is the number of state transitions, not O(n) where n is point count.
- Rule: When drawing multi-segment curves, batch contiguous segments sharing the same visual style into one `Path`. Never create a `Path` per point.

**6.2 Avoid `Array(slice)` allocation in render loops**
`Array(points[range])` inside a drawing loop allocates a new array per segment. For high segment counts this becomes measurable.
- Rule: Prefer iterating over the `ArraySlice` directly rather than copying to a new `Array`. If a function requires `[Element]`, refactor it to accept `some Collection<Element>` or `ArraySlice<Element>`.

```swift
// GOOD — iterates slice without copying
for point in points[start..<end] { path.addLine(to: point) }

// BAD — copies to Array first
let segment = Array(points[start..<end])
drawSegment(segment)
```

**6.3 Scale computation happens once, not per frame**
Robust scale max (90th percentile) involves `sorted()` — this must run only on data change (initial layout or new point batch), never inside `draw()` or `Canvas` closure on every frame.
- Rule: Any O(n log n) statistic (percentile, median, standard deviation) must be precomputed and cached. Recompute only when the underlying data changes.

**6.4 Binary search for incremental point append**
`ActiveTrackingView` uses binary search to find new samples since the last render — O(log n) vs O(n) linear scan.
- Rule: When appending new data to a frozen render buffer, use binary search on the timestamp to locate the insertion point. Do not rescan from index 0.

---

### 7. Profiling Guidance

#### GPS Pipeline Checkpoints

Hot path per GPS update:
```
CLLocationUpdate → accuracy filter → TrackPoint → GPSKalmanFilter → RunDetectionService.detect() → SegmentFinalizationService → state mutation → @Observable notification
```

Profile in order when CPU is high during tracking:

| Step | Tool | Target |
|------|------|--------|
| Accuracy filter | Time Profiler | < 0.01 ms, no allocation |
| Kalman filter | Time Profiler | < 0.1 ms per point |
| `detect()` | Time Profiler | < 0.05 ms, zero allocations |
| Course derivation fallback | Time Profiler | < 0.02 ms (Haversine, ~180 FP ops) |
| `@Observable` notification rate | SwiftUI Instrument | ≈ GPS update rate (not higher) |
| `distanceFilter` adjustment | Energy Log | Battery check per update is cached, not UIDevice poll |

#### SwiftData Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| N+1 fetches | `COREDATA_VERBOSE_SQL=1` shows per-run queries | Add `relationshipKeyPathsForPrefetching` |
| `trackData` decoded at list render | Memory grows on scroll | Decode only in session detail view |
| Blob in SQLite WAL | Slow batch fetch | Add `@Attribute(.externalStorage)` |
| ModelContext on wrong thread | Crash or corruption | Pass `ModelContext` as parameter; do not share across actors |

#### SwiftUI Checkpoints

| View | Expected Body Rate | Failure Signal |
|------|--------------------|----------------|
| `ActiveTrackingView` | ~1 Hz (matches GPS) | Higher than GPS rate |
| `SpeedCurveView` | On new point only | Full redraw every frame → `FrozenPoint.Equatable` broken |
| Static rows (Gear, Activity list) | Zero during tracking | Reading a tracking service property it shouldn't |
| Any view with `@Environment(\.modelContext)` | On data change only | Unnecessary re-fetch on unrelated model save |

#### Concurrency Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| Data race in delegate callback | Thread Sanitizer purple warning | Mark method `nonisolated`, dispatch via `Task` |
| Task leak (never cancelled) | Memory grows, duplicate work | Cancel stored task before reassign; cancel in stop/deinit |
| Redundant main dispatch | Time Profiler shows dispatch overhead | Remove `DispatchQueue.main.async` from `@MainActor` class |
| Retain cycle via `Task` closure | Leaks Instrument shows service not deallocated | Capture `[weak self]` in long-lived tasks |

#### Watch Connectivity Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| Transfer queue stall | WCSession `remainingComplicationTransfers` drops | Use `sendLive()` for ephemeral data, not `send()` |
| Observation tracking storm | >5 Watch transfers/sec in Console log | Add ≥ 100 ms debounce to `withObservationTracking` loop |
| Pending points overflow | Warning log "dropping track points" | Investigate Watch disconnect; verify 100k cap is active |
| Serialization on main thread | Time Profiler shows encoding in `@MainActor` | Move encoding to `nonisolated` helper |

#### HealthKit Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| Per-point HK submission | Energy Log shows HK spikes at GPS rate | Batch via 3-second flush timer |
| Concurrent flush tasks | HK errors / duplicate samples | Guard with single `activeFlushTask` |
| Data loss on session end | Route missing tail points | Drain loop before `endCollection()` |
| Buffer unbounded growth | Memory grows during poor HK connectivity | Trim to tail 1,800 points on overflow |

#### Motion Estimation Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| `sorted()` in per-point loop | Time Profiler shows sort in hot path | Use `medianFilter3()` specialization for window ≤ 3 |
| Two-pass window estimation | Double iteration over same buffer | Fuse into single-pass dual-window |
| Missing `reserveCapacity` | Allocations Instrument shows realloc in loop | Add `reserveCapacity(windowSize)` to accumulators |

#### Canvas Rendering Checkpoints

| Issue | Signal | Fix |
|-------|--------|-----|
| Path-per-point allocation | Time Profiler in `Canvas` closure | Batch contiguous same-state segments |
| `Array(slice)` in draw loop | Allocations Instrument shows copies | Iterate `ArraySlice` directly |
| Scale recomputed per frame | `sorted()` appearing in `draw()` | Cache percentile; recompute only on data change |
| Linear scan for new points | O(n) in incremental append | Use binary search on timestamp |

#### Memory Checkpoints (after 60-min simulated session)

| Check | Pass Condition |
|-------|---------------|
| `TrackPoint` allocation count | Bounded by `RecentTrackBuffer` capacity |
| `FrozenPoint` count | ≤ 300 |
| `SkiRun.trackData` decoded | Only when detail view is open |
| `pendingWatchTrackPoints` | ≤ 100k; logged warning if cap hit |
| `pendingRoutePoints` (HK) | ≤ 1,800 after each trim |
| `HeartRateSample` buffer | Bounded by `CircularBuffer` capacity |
| `RecentTrackBuffer` compaction | Triggered when head exceeds half storage |
| Stored `Task` handles | All cancelled after tracking stops |

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
- [ ] No Thread Sanitizer warnings during 30-min tracking session
- [ ] No Task leaks (all stored tasks cancelled on stop)
- [ ] Watch transfer rate < 5/sec during steady-state tracking
- [ ] HealthKit flush count ≈ session_duration / 3s (not session_duration × GPS_rate)
```

### Profile Guidance Output

List the applicable profiling checkpoints as a numbered checklist with the Xcode instrument to use and the pass/fail threshold for each.
