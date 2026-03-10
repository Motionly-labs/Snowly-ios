# Writing Tests

Code patterns for unit tests and integration tests in `SnowlyTests/`.

---

## Unit Test: Pure Service

Pure services (`MotionEstimator`, `RunDetectionService`, `SegmentValidator`) take all inputs as parameters. Tests construct inputs directly — no mocks needed.

```swift
@MainActor
struct RunDetectionServiceTests {

    // MARK: - Helpers

    private func makePoint(
        speed: Double,
        altitude: Double = 2000,
        timestamp: Date = Date(),
        lat: Double = 46.0,
        lon: Double = 7.0
    ) -> FilteredTrackPoint {
        FilteredTrackPoint(
            rawTimestamp: timestamp,
            timestamp: timestamp,
            latitude: lat,
            longitude: lon,
            altitude: altitude,
            estimatedSpeed: max(speed, 0),
            accuracy: 5.0,
            course: 180.0
        )
    }

    // MARK: - Tests

    @Test func belowIdleThreshold_isIdle() {
        let decision = RunDetectionService.analyze(
            point: makePoint(speed: 0.3, altitude: 1000),
            recentPoints: [],
            previousActivity: .idle,
            motion: .unknown
        )
        #expect(decision.activity == .idle)
    }

    @Test func aboveFastThreshold_isSkiing() {
        let decision = RunDetectionService.analyze(
            point: makePoint(speed: 7.0, altitude: 1000),
            recentPoints: [],
            previousActivity: .idle
        )
        #expect(decision.activity == .skiing)
    }
}
```

Use `#expect` for soft assertions (test continues on failure) and `#require` for hard preconditions (test stops if the expression is false/nil).

---

## Unit Test: `MotionEstimator`

Build a history array with helper functions:

```swift
@MainActor
struct MotionEstimatorTests {

    private func makePoint(
        speed: Double,
        altitude: Double = 2000,
        timestamp: Date = Date()
    ) -> TrackPoint {
        TrackPoint(
            timestamp: timestamp,
            latitude: 46.0, longitude: 7.0,
            altitude: altitude,
            speed: speed,
            accuracy: 5.0,
            course: 180.0
        )
    }

    private func makePoints(
        count: Int,
        startAltitude: Double,
        endAltitude: Double,
        speed: Double = 4.0,
        startTime: Date,
        stepSeconds: Double = 3
    ) -> [TrackPoint] {
        (0..<count).map { i in
            let fraction = count > 1 ? Double(i) / Double(count - 1) : 0
            let alt = startAltitude + (endAltitude - startAltitude) * fraction
            return makePoint(
                speed: speed,
                altitude: alt,
                timestamp: startTime.addingTimeInterval(Double(i) * stepSeconds)
            )
        }
    }

    @Test func estimate_emptyHistory_usesInstantaneousSpeed() {
        let current = makePoint(speed: 5.0, altitude: 2000)
        let estimate = MotionEstimator.estimate(current: current, recentPoints: [])
        #expect(estimate.avgHorizontalSpeed == 5.0)
        #expect(estimate.avgVerticalSpeed == 0)
        #expect(!estimate.hasReliableAltitudeTrend)
    }
}
```

---

## Unit Test: Stateful Service with Mock

For services that depend on a protocol, inject a mock:

```swift
@MainActor
final class MockLocationService: LocationProviding {
    private var continuation: AsyncStream<TrackPoint>.Continuation?

    func startTracking() -> AsyncStream<TrackPoint> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func stopTracking() {
        continuation?.finish()
        continuation = nil
    }

    func emit(_ point: TrackPoint) {
        continuation?.yield(point)
    }
}

@MainActor
struct SessionTrackingServiceTests {

    @Test func startTracking_transitionsToTracking() async {
        let mockLocation = MockLocationService()
        let service = SessionTrackingService(
            locationService: mockLocation,
            // ...other dependencies...
        )

        await service.startTracking()
        #expect(service.state == .tracking)
    }
}
```

---

## Async Yield Pattern

When a service processes injected points asynchronously (via actors or `Task`), insert `await Task.yield()` to allow the event loop to process them before asserting:

```swift
@Test func emittingPoint_updatesCurrentSpeed() async {
    let mockLocation = MockLocationService()
    let service = SessionTrackingService(locationService: mockLocation, ...)

    await service.startTracking()
    mockLocation.emit(TrackPoint(speed: 12.5, ...))

    await Task.yield()  // let the actor process the point

    #expect(service.currentSpeed > 0)
}
```

---

## Segment Validation Tests

Test each validator gate independently to ensure the boundary conditions are correct:

```swift
@MainActor
struct SegmentValidatorTests {

    private func makePoint(altitude: Double, timestamp: Date = Date()) -> TrackPoint {
        TrackPoint(timestamp: timestamp, latitude: 46.0, longitude: 7.0,
                   altitude: altitude, accuracy: 5.0, course: 0)
    }

    @Test func skiing_shortDuration_demotedToWalk() {
        let result = SegmentValidator.effectiveType(
            activityType: .skiing,
            firstAltitude: 2100,
            lastAltitude: 2000,   // 100 m drop — passes altitude gate
            duration: 10,         // 10 s — fails duration gate (< 15 s)
            averageSpeed: 4.0     // passes speed gate
        )
        #expect(result == .walk)
    }

    @Test func walk_veryShort_discarded() {
        let result = SegmentValidator.effectiveType(
            activityType: .walk,
            firstAltitude: 2000,
            lastAltitude: 2000,
            duration: 4,          // < 6 s
            averageSpeed: 1.0
        )
        #expect(result == nil)
    }
}
```

---

## Serialized Test Suite

Use `@Suite(.serialized)` when tests share mutable global state (e.g., `UserDefaults`):

```swift
@Suite(.serialized)
@MainActor
struct TrackingStatePersistenceTests {

    @Test func save_andRestore_roundTrips() {
        // ...
        TrackingStatePersistence.save(state)
        let restored = TrackingStatePersistence.load()
        #expect(restored == state)
    }
}
```

---

## Integration Test with Fixture Replay

For end-to-end pipeline verification, use `FixtureReplayService`:

```swift
@MainActor
struct SessionTrackingIntegrationTests {

    @Test func zermattFixture_producesExpectedRunCount() throws {
        // Load fixture points (from test bundle resource)
        let points: [TrackPoint] = try loadZermattFixturePoints()

        let runs = FixtureReplayService.buildCompletedRunData(
            activityType: .skiing,
            points: points.map(\.filteredEstimatePoint)
        )

        // Verify at least one valid skiing run was detected
        #expect(runs != nil)
        #expect(runs?.activityType == .skiing)
    }
}
```

For the full replay pipeline (including dwell time and segmentation), use `FixtureReplayService.replayFixtureDataIfNeeded` with an in-memory `ModelContainer` — see [Fixture Replay](FixtureReplay.md).
