# Glossary

Canonical product and technical terms used throughout the Snowly codebase and documentation.

---

## Product Terms

## Gear

A single user-created locker item such as skis, boots, goggles, gloves, charger, or a bag. In product copy, always say `gear`, never `asset` or `item`.

## Locker

The complete inventory of a user's gear. Gear is created in the locker first, then selected into checklists.

## Checklist

A named selection of locker gear used for preparation and packing. In product copy, always say `checklist`, never `setup`.

## Active Checklist

The checklist that Snowly auto-attaches to new sessions by default. Users can still correct the attached checklist later from session summary.

## Visual Checklist

The body-zone packing surface built from one checklist. It includes the skier figure, zone highlights, and packed / not packed state.

## Reminder Schedule

A local notification cadence attached to one gear item. A reminder schedule has:

- a start date
- an end date
- an interval value and unit
- a reminder time

## Attached Checklist

The checklist snapshot linked to a `SkiSession`. It records which checklist a ski day used, independent of later checklist edits.

## Internal Model Mapping

Internal code names intentionally differ from product language:

- `GearAsset` = product `Gear`
- `GearSetup` = product `Checklist`
- `GearReminderScheduleStore` = local persistence for reminder schedules
- `GearChecklistStore` = local persistence for visual checklist checkmarks

## Deprecated Gear Terms

These are not current product language and should not appear in new UI copy or docs:

- `asset`
- `setup`
- `maintenance` as the primary Gear concept

Legacy maintenance fields and models still exist internally for persistence compatibility, but they are not part of the latest product design.

---

## Tracking Terms

## Track Point

A single raw GPS observation captured by `CLLocationManager`. Stored as a `TrackPoint` struct (`timestamp`, `latitude`, `longitude`, `altitude`, `speed`, `horizontalAccuracy`, `verticalAccuracy`, `course`). Immutable and `Codable`. Not a SwiftData `@Model`.

## Filtered Track Point

A `TrackPoint` that has been processed through `GPSKalmanFilter`. The resulting `FilteredTrackPoint` carries smoothed position (`latitude`, `longitude`, `altitude`) and a filter-derived `estimatedSpeed`. Downstream services (motion estimation, detection) operate on filtered points only.

## Segment

A contiguous sequence of track points that share the same detected activity type (`.skiing`, `.lift`, or `.walk`). A segment begins when the activity type changes and ends when the type changes again or when the idle timeout fires (45 s). Segments are built up by `SegmentFinalizationService`.

## Completed Run

An immutable `CompletedRunData` struct produced when a segment is finalized. Contains summary statistics (`distance`, `verticalDrop`, `maxSpeed`, `averageSpeed`, `activityType`) and optionally a `trackData: Data?` blob encoded by a background task after finalization.

## Dwell Time (Hysteresis)

A minimum duration that a newly detected activity must sustain before the stable activity state transitions. Prevents false positives from momentary GPS glitches. For example, the classifier must observe `.lift` continuously for 14 s before the tracked activity switches from `.skiing` to `.lift`. Constants are in `SharedConstants`.

## Transition Window

A 4-second rolling window of filtered GPS points used by `MotionEstimator` to produce a fast-reacting feature estimate. Enables quick response to activity changes at run/lift boundaries.

## Steady Window

A 12-second rolling window of filtered GPS points used by `MotionEstimator` to produce a noise-resistant baseline estimate. Used alongside the transition window to resolve ambiguous detections.

## Confidence

A scalar in [0, 1] attached to each `MotionEstimate`. Derived from window coverage, sample count, timestamp spacing, and both horizontal and vertical GPS accuracy. High confidence means the estimate is based on dense, gap-free, high-quality GPS history.

## `hasReliableAltitudeTrend`

A boolean field on `MotionEstimate`. `true` when there are enough samples, sufficient time span, a measurable vertical rate, and adequate confidence to trust altitude-based classification rules. When `false`, the classifier falls back to speed-only rules. This is correct behaviour in tunnels, gondola loading zones, and at session start.

## Demotion

The process by which `SegmentValidator` reclassifies a completed segment to a lower type. A segment classified as `.skiing` that fails minimum duration, altitude loss, or speed thresholds is demoted to `.walk`. A demoted `.walk` segment shorter than 6 s is discarded entirely (`nil`).

## Denormalized

The pattern of storing aggregate values (`totalDistance`, `totalVertical`, `maxSpeed`, `runCount`) directly on `SkiSession` so they can be queried and sorted without loading child `SkiRun` objects. These fields are written once in `SessionTrackingService.saveSession()`.

## Companion Mode

The default watch operating mode when the paired iPhone is reachable and actively tracking. The watch mirrors live stats received over `WCSession` from `PhoneConnectivityService`. The watch does not run its own GPS pipeline in this mode.

## Independent Mode

The watch operating mode when the iPhone is unreachable. The watch runs `WatchLocationService` + `RunDetectionService` + `WatchWorkoutManager` independently. Track points are batched and sent to the iPhone on reconnect, where `WatchBridgeService` runs the full production pipeline.

## ENU Frame

East-North-Up local coordinate frame used internally by `GPSKalmanFilter`. The first GPS point in a session sets the origin. All subsequent positions are expressed in meters east, north, and up from that origin, enabling the constant-velocity Kalman filter to operate in Euclidean space.

## Accumulation Filter

The rule that only `.skiing` activity contributes to session aggregate metrics (`totalDistance`, `totalVertical`, `maxSpeed`). Lift and walk distances are tracked per-`SkiRun` but are excluded from the session-level summary.

## Season

A logical grouping of `SkiSession` records. There is no `@Model` for a season — it is a query-time concept. `StatsService.aggregateStats(from:)` accepts any array of sessions; the caller decides the time range (e.g. current ski season, all time). Season boundaries are not enforced by the model layer.

## Personal Best

A cross-session, all-time single-day record stored on `UserProfile` (`personalBestMaxSpeed`, `personalBestVertical`, `personalBestDistance`). Updated by `StatsService.applyPersonalBestUpdate(_:to:)` at the end of each session. These are all-time records, not season-scoped records. Season-scoped goals are a planned P1 feature and will use separate fields when introduced.
