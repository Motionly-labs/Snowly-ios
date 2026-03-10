# Segment Lifecycle

How GPS points accumulate into segments, how segments are finalized, and the quality gates that determine whether a segment is saved, demoted, or discarded.

Source files: `Snowly/Services/SegmentFinalizationService.swift`, `Snowly/Services/SegmentValidator.swift`

---

## Segment State Machine

`SegmentFinalizationService` runs a simple state machine per session:

```
IDLE
  │
  └─(first non-idle point arrives)
  ▼
ACCUMULATING
  │  currentSegmentType = targetType
  │  currentSegmentPoints = [point]
  │
  ├─(same activity type) ──► append point ──► ACCUMULATING
  │
  ├─(activity type changes)
  │    finalizeCurrentSegment()
  │    currentSegmentType = newType
  │    currentSegmentPoints = [point]
  │    ──► ACCUMULATING
  │
  └─(idle arrives AND lastActiveTime > 45 s ago)
       finalizeCurrentSegment()
       ──► IDLE
```

The 45-second idle threshold matches `SharedConstants.historyRetentionSeconds` / `stopDurationThreshold`.

---

## `processPoint(_:activity:)`

Called once per stable (post-dwell) GPS point:

1. Map `DetectedActivity` → `RunActivityType?`:
   - `.skiing` → `.skiing`
   - `.lift` → `.lift`
   - `.walk` → `.walk`
   - `.idle` → `nil`
2. If `targetType` is non-nil:
   - If `targetType != currentSegmentType` → finalize old segment, start new one
   - Else → append point to current segment
   - Update `lastActiveTime`
3. If `targetType` is `nil` (idle) and the current segment has been idle for >45 s → finalize

---

## Finalization Pipeline

`finalizeCurrentSegment()` executes on `@MainActor`:

1. Guard that `currentSegmentType` and `currentSegmentPoints` are non-empty
2. Compute **distance**: haversine sum over consecutive point pairs
3. Compute **duration**: `last.timestamp − first.timestamp`
4. Compute **avgSpeed**: `distance / duration`
5. Compute **maxSpeed**: `derivedMaxSpeed(from:)` — max displacement/dt over consecutive pairs
6. Compute **verticalDrop**: `SegmentValidator.verticalDrop(effectiveType:firstAltitude:lastAltitude:)`
7. Capture `currentSegmentPoints` for background encoding
8. Append a `CompletedRunData` with `trackData: nil` to `completedRuns`
9. If `activityType == .skiing`, increment `runCount`
10. Reset segment state
11. Launch `Task.detached` to encode points: `JSONEncoder().encode(points)`
12. On completion, call `patchTrackData(_:at:)` on `@MainActor` to fill in the `trackData` field

The `Task.detached` avoids blocking the main thread on JSON encoding of potentially thousands of points.

> **Note:** `completedRuns[index].trackData` is `nil` for a brief moment after finalization. Code that consumes `CompletedRunData` must handle this case.

---

## `SegmentValidator.effectiveType()`

After finalization, the validator applies quality gates to determine whether the segment should be saved, demoted to `.walk`, or discarded.

**Skiing validation** (when `activityType == .skiing`):

| Gate | Threshold | Failure action |
|---|---|---|
| Duration | ≥ 15 s | Demote to `.walk` |
| Altitude loss (`first − last`) | ≥ 12 m | Demote to `.walk` |
| Average speed | ≥ 3.5 m/s | Demote to `.walk` |

All three gates must pass. Any single failure demotes the segment.

**Lift validation** (when `activityType == .lift`):

| Gate | Threshold | Failure action |
|---|---|---|
| Duration | ≥ 30 s | Demote to `.walk` |
| Altitude gain (`last − first`) | ≥ 20 m | Demote to `.walk` |
| Average vertical speed (`gain / duration`) | ≥ 0.10 m/s | Demote to `.walk` |

**Walk discard**:

| Gate | Threshold | Action |
|---|---|---|
| Duration | < 6 s | Return `nil` (discard entirely) |
| Average speed | ≥ 8.0 m/s AND original type ≠ `.walk` | Restore original type (physics guard) |

The physics guard prevents a GPS glitch that inflated average speed from permanently demoting a real ski run to walk.

---

## `verticalDrop(effectiveType:firstAltitude:lastAltitude:)`

Returns the meaningful altitude change in meters, clamped to ≥ 0:

| Activity | Convention | Zero condition |
|---|---|---|
| `.skiing` | `max(0, first − last)` | Segment ended higher than it started |
| `.lift` | `max(0, last − first)` | Segment ended lower than it started |
| `.walk`, `.idle` | Always 0 | — |

---

## `SkiRun` Persistence

After `saveSession()` is called, each `CompletedRunData` in `SegmentFinalizationService.completedRuns` is mapped to a `SkiRun @Model` and inserted into SwiftData. Only segments with a non-`nil` effective type (i.e., not discarded by the validator) are persisted.

```swift
let run = SkiRun(
    startDate: runData.startDate,
    endDate: runData.endDate,
    distance: runData.distance,
    verticalDrop: runData.verticalDrop,
    maxSpeed: runData.maxSpeed,
    averageSpeed: runData.averageSpeed,
    activityType: runData.activityType,
    trackData: runData.trackData
)
run.session = session
context.insert(run)
```

---

## Accumulation Filter

Session-level aggregates (`SkiSession.totalDistance`, `totalVertical`, `maxSpeed`) are computed from the subset of `CompletedRunData` where `activityType == .skiing`. Lift and walk segments are stored in `SkiRun` but excluded from session totals.

This is the *accumulation filter* described in the [Glossary](../Reference/Glossary.md).
