# Fixture Replay

How GPS fixtures are stored, loaded, and replayed through the production pipeline for integration testing.

Source files: `Snowly/Services/FixtureReplayService.swift`, `Snowly/Resources/ReplayFixtures.manifest.json`

---

## Purpose

The fixture replay system lets you run real GPS track data through the exact same pipeline that processes live GPS during a session. This verifies that the Kalman filter, activity detection, dwell-time logic, segment validation, and persistence all produce sensible results on known data — without requiring a physical ski session.

---

## Manifest Format

`Snowly/Resources/ReplayFixtures.manifest.json` lists available fixtures:

```json
{
  "fixtures": [
    {
      "id": "zermatt_loop",
      "display_name": "Zermatt Loop",
      "trackpoints_resource": "zermatt_loop_trackpoints",
      "session_id": "12345678-...",
      "resort": {
        "id": "AAAAAAAA-...",
        "name": "Zermatt",
        "latitude": 46.0207,
        "longitude": 7.7491,
        "country": "CH"
      }
    }
  ]
}
```

The `trackpoints_resource` value is the name of a JSON file in `Debug/Fixtures/` (e.g., `zermatt_loop_trackpoints.json`). The file contains an array of raw track point objects:

```json
[
  {
    "timestamp": 0.0,
    "latitude": 46.0207,
    "longitude": 7.7491,
    "altitude": 3883.5,
    "accuracy": 5.0,
    "course": 180.0
  },
  ...
]
```

Timestamps are relative seconds from the start of the recording. `FixtureReplayService` re-anchors them to `Date() - 90 minutes` at replay time so the session appears recent in the Activity tab.

---

## Launch Argument: `-replay_fixture`

To load a fixture into the app at launch (DEBUG builds only):

1. In Xcode, edit the Snowly scheme
2. Under **Run → Arguments**, add:
   ```
   -replay_fixture zermatt_loop
   ```
3. Build and run on a simulator

At launch, `SnowlyApp.init()` calls `FixtureReplayService.replayFixtureDataIfNeeded(in:launchArguments:)`. The service:

1. Loads the manifest and finds the fixture with matching `id`
2. Loads the track points JSON
3. Deletes any existing session with the same `sessionId`
4. Anchors timestamps to near-current time
5. Runs the full replay pipeline (Kalman → detection → dwell → segmentation → validation)
6. Inserts `SkiSession` + `[SkiRun]` into the main context
7. Updates personal bests via `StatsService`

After launch, `SessionDetailView` will show the replayed session with all metrics populated.

---

## `FixtureReplayService.buildCompletedRunData(activityType:points:)`

A synchronous helper used in tests and the watch import path. Runs the production validation pipeline on a pre-segmented list of `FilteredTrackPoint` values:

```swift
// In a test
let points: [FilteredTrackPoint] = ...
let run = FixtureReplayService.buildCompletedRunData(
    activityType: .skiing,
    points: points
)
#expect(run?.activityType == .skiing)
#expect(run?.distance ?? 0 > 100)  // at least 100 m for a valid run
```

This function does not apply dwell time or segmentation — it takes a pre-classified segment and returns a validated `CompletedRunData`, or `nil` if the segment fails the quality gates.

---

## Generator Script

`Scripts/Generators/generate-zermatt-fixtures.swift` converts a raw recorded track file into the fixture JSON format. Run it when adding a new fixture:

```bash
swift Scripts/Generators/generate-zermatt-fixtures.swift \
    --input path/to/recorded_track.gpx \
    --output Snowly/Resources/Debug/Fixtures/zermatt_loop_trackpoints.json
```

After generating the file:

1. Add an entry to `ReplayFixtures.manifest.json`
2. Add the JSON file to the Xcode project (it will be auto-included via `PBXFileSystemSynchronizedRootGroup`)

---

## Replay Pipeline Internals

`buildCompletedRunsViaReplay(from:)` in `FixtureReplayService` runs:

```
for each raw TrackPoint:
  1. GPSKalmanFilter.update(point:)         → FilteredTrackPoint
  2. replayMotionHint(...)                  → MotionHint (lift continuity)
  3. RunDetectionService.detect(...)        → DetectedActivity (raw)
  4. SessionTrackingService.applyDwellTime(...)  → stable DetectedActivity
  5. segment accumulation
  6. (on type change) FixtureReplayService.buildCompletedRunData(...)
       → CompletedRunData or nil (validator may discard)

after loop: finalize remaining segment
```

This is identical to the production path in `SessionTrackingService`, making fixture replay a high-fidelity integration test.

---

## Expected Fixture Output

When the Zermatt loop fixture is replayed, `SessionDetailView` should display:

| Metric | Expected Range |
|---|---|
| Run count | 5–12 runs |
| Total vertical | 1,000–4,000 m |
| Max speed | 15–35 m/s (54–126 km/h) |
| Avg speed | 6–15 m/s |

If any value falls outside these ranges, investigate the pipeline rather than adjusting the expected ranges — the fixture represents a real ski day.
