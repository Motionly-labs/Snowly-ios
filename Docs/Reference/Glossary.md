# Glossary

Domain terms used throughout the Snowly codebase and documentation.

---

## Track Point

A single raw GPS observation captured by `CLLocationManager`. Stored as a `TrackPoint` struct (`timestamp`, `latitude`, `longitude`, `altitude`, `speed`, `accuracy`, `course`). Immutable and `Codable`. Not a SwiftData `@Model`.

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

A scalar in [0, 1] attached to each `MotionEstimate`. Derived from three factors: `coverage` (how much of the window is filled), `sampleFactor` (number of samples), and `gapFactor` (evenness of sample spacing). High confidence means the estimate is based on dense, gap-free GPS history.

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
