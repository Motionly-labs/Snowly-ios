# Add a New Metric

How to add a new per-run metric from raw track points all the way to the UI.

This guide uses `avgTurnRate` (degrees/second) as the running example throughout.

---

## Overview

Adding a metric touches these layers in order:

1. `CompletedRunData` — in-memory representation
2. `SegmentFinalizationService` — computation
3. `SkiRun` (`@Model`) — persistence
4. `SchemaVersions.swift` — migration (if needed)
5. `SkiSession` — optional denormalization for list queries
6. `StatsService` — season aggregation
7. UI — tracking dashboard, session detail, or share card

---

## Step 1 — Add to `CompletedRunData`

`CompletedRunData` is an immutable `struct` in `SegmentFinalizationService.swift`. Add a new `let` field:

```swift
struct CompletedRunData: Sendable, Equatable {
    // ...existing fields...
    let avgTurnRate: Double  // degrees/second; 0 if not applicable
}
```

Update all call sites that construct `CompletedRunData` — the compiler will flag every location.

---

## Step 2 — Compute in `finalizeCurrentSegment()`

In `SegmentFinalizationService.finalizeCurrentSegment()`, compute the metric from `currentSegmentPoints` before building `CompletedRunData`. Follow the pattern of the existing `derivedMaxSpeed(from:)` helper:

```swift
private func derivedAvgTurnRate(from points: [TrackPoint]) -> Double {
    guard activityType == .skiing, points.count > 1 else { return 0 }
    var totalTurnDegrees = 0.0
    for (a, b) in zip(points, points.dropFirst()) {
        let delta = abs(b.course - a.course)
        totalTurnDegrees += delta > 180 ? 360 - delta : delta
    }
    let duration = max(
        points.last!.timestamp.timeIntervalSince(points.first!.timestamp),
        1
    )
    return totalTurnDegrees / duration
}
```

> **Note:** If the metric only makes sense for `.skiing` activity, guard with `activityType == .skiing` both in the helper and in how you use the result. Lift and walk `avgTurnRate` should be 0.

Then include it in the `CompletedRunData` constructor:

```swift
let run = CompletedRunData(
    // ...existing fields...
    avgTurnRate: segmentType == .skiing ? derivedAvgTurnRate(from: currentSegmentPoints) : 0
)
```

---

## Step 3 — Add to `SkiRun` (`@Model`)

In `Snowly/Models/SkiRun.swift`, add a stored property with a default value:

```swift
var avgTurnRate: Double = 0  // degrees/second
```

The default value is required for CloudKit compatibility and backward compatibility with existing stored data.

Then update `SessionTrackingService.saveSession(to:resort:)` to transfer the value from `CompletedRunData` to `SkiRun`:

```swift
let run = SkiRun(
    // ...existing fields...
    avgTurnRate: runData.avgTurnRate
)
```

---

## Step 4 — Schema Migration

Because you added a property with a default value (`= 0`), a lightweight migration is sufficient. See [Add a SwiftData Migration](AddSwiftDataMigration.md) for the complete steps.

For a `Double` with a default value, the migration is three lines:

```swift
// In SnowlyMigrationPlan.stages:
.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
```

---

## Step 5 — Denormalize on `SkiSession` (Optional)

Only add this step if you need to sort or filter sessions by the metric in list views (e.g., "most technical session" sorted by `avgTurnRate`).

Add a field to `SkiRun.swift`:

```swift
var sessionAvgTurnRate: Double = 0  // denormalized session-level average
```

In `SessionTrackingService.saveSession()`, compute and assign it after creating the `SkiSession`:

```swift
let skiingRuns = completedRuns.filter { $0.activityType == .skiing }
session.sessionAvgTurnRate = skiingRuns.isEmpty ? 0
    : skiingRuns.map(\.avgTurnRate).reduce(0, +) / Double(skiingRuns.count)
```

---

## Step 6 — Add to `StatsService` Aggregate Stats

If the metric should appear in the aggregate summary (e.g., `ActivityHistoryView`), add it to `AggregateStats` in `StatsService.swift` and compute it in `aggregateStats(from:)`:

```swift
struct AggregateStats {
    // ...existing fields...
    let avgTurnRate: Double
}

static func aggregateStats(from sessions: [SkiSession]) -> AggregateStats {
    // ...
    let allSkiRuns = sessions.flatMap(\.runs).filter { $0.activityType == .skiing }
    let avgTurnRate = allSkiRuns.isEmpty ? 0
        : allSkiRuns.map(\.avgTurnRate).reduce(0, +) / Double(allSkiRuns.count)
    return AggregateStats(
        // ...
        avgTurnRate: avgTurnRate
    )
}
```

---

## Step 7 — UI

**Tracking dashboard widget:** Add a case to `TrackingStatWidget` in `TrackingDashboardLayout.swift`:

```swift
enum TrackingStatWidget: String, Codable, CaseIterable {
    // ...existing cases...
    case turnRate

    var icon: String {
        switch self {
        // ...
        case .turnRate: return "arrow.triangle.turn.up.right.circle"
        }
    }
}
```

Then handle the new case in `TrackingStatGrid` (`TrackingStatGrid.swift`).

**Session detail:** Add the metric to `SessionDetailView` in the appropriate stats section.

**Share card:** If the metric is notable (e.g., personal best), add it to `ShareCardView`.

---

## Step 8 — Tests

Write a unit test in `SnowlyTests/SegmentFinalizationServiceTests.swift` (create this file if it does not exist):

```swift
@MainActor
struct SegmentFinalizationServiceTests {
    @Test func avgTurnRate_skiingSegment_computesCorrectly() {
        let service = SegmentFinalizationService()
        let t0 = Date()
        let points: [TrackPoint] = [
            TrackPoint(timestamp: t0,          ..., course: 0),
            TrackPoint(timestamp: t0 + 1,      ..., course: 90),
            TrackPoint(timestamp: t0 + 2,      ..., course: 180),
        ]
        for point in points {
            service.processPoint(point, activity: .skiing)
        }
        service.finalizeCurrentSegment()
        let run = service.completedRuns.last
        #expect(run?.avgTurnRate ?? 0 > 0)
    }
}
```

For integration coverage, use `FixtureReplayService.buildCompletedRunData(activityType:points:)` with the Zermatt fixture to verify the metric produces plausible values on a real track.
