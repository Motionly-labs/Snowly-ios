# Add a New Service

How to add a stateful service to the Snowly service layer.

---

## Decide: Stateful Service vs Pure-Function Namespace

Before adding a new service class, ask: does this need persistent state or a lifecycle?

- **Yes** → follow this guide (stateful `@Observable @MainActor final class`)
- **No** → use an `enum` namespace like `RunDetectionService` (no injection needed)

Examples of pure-function namespaces:
- `MotionEstimator` — computes features from track points
- `RunDetectionService` — classifies activity
- `SegmentValidator` — validates segment quality
- `StatsService` — aggregates statistics

Pure services are simpler, thread-safe by construction, and require no mock because all inputs are parameters.

---

## Step 1 — Define the Protocol

Create a file in `Snowly/Services/Protocols/`:

```swift
// Snowly/Services/Protocols/WeatherProviding.swift

@MainActor
protocol WeatherProviding: AnyObject, Sendable {
    var currentConditions: WeatherConditions? { get }
    func startUpdates(for coordinate: CLLocationCoordinate2D) async
    func stopUpdates()
}
```

Protocols allow substitution of a mock during unit tests.

---

## Step 2 — Implement the Service

Create the implementation in `Snowly/Services/`:

```swift
// Snowly/Services/WeatherService.swift

@Observable
@MainActor
final class WeatherService: WeatherProviding {
    private(set) var currentConditions: WeatherConditions?

    func startUpdates(for coordinate: CLLocationCoordinate2D) async {
        // implementation
    }

    func stopUpdates() {
        // implementation
    }
}
```

Requirements:
- `@Observable` — enables fine-grained UI observation without `@Published`
- `@MainActor` — ensures all state mutations happen on the main thread
- `final class` — prevents subclassing; all polymorphism goes through the protocol

---

## Step 3 — Add to `AppServices`

In `Snowly/SnowlyApp.swift`, add a `let` property and initialize it:

```swift
@Observable
@MainActor
final class AppServices {
    // ...existing services...
    let weatherService: WeatherService

    init() {
        // ...existing init...
        self.weatherService = WeatherService()
    }
}
```

Use `let`, not `var`. Services have stable identity for the entire app lifecycle.

---

## Step 4 — Inject in `SnowlyApp.body`

```swift
var body: some Scene {
    WindowGroup {
        RootView()
            // ...existing injections...
            .environment(services.weatherService)
    }
}
```

---

## Step 5 — Consume in Views

```swift
struct WeatherWidget: View {
    @Environment(WeatherService.self) var weatherService

    var body: some View {
        if let conditions = weatherService.currentConditions {
            Text(conditions.summary)
        }
    }
}
```

The `@Environment` wrapper observes only the properties the view body reads. Changing an unread property does not trigger a re-render.

---

## Step 6 — Testing with a Mock

Define a mock that conforms to the protocol:

```swift
@MainActor
final class MockWeatherService: WeatherProviding {
    var currentConditions: WeatherConditions? = nil
    var didStartUpdates = false

    func startUpdates(for coordinate: CLLocationCoordinate2D) async {
        didStartUpdates = true
    }

    func stopUpdates() {}
}
```

Inject the mock in tests or previews:

```swift
// In a test
let mock = MockWeatherService()
mock.currentConditions = WeatherConditions(summary: "Sunny")
// inject via initializer or environment

// In a preview
#Preview {
    WeatherWidget()
        .environment(MockWeatherService())
}
```

---

## Service Lifecycle Conventions

| Concern | Convention |
|---|---|
| Start on app launch | Call from `AppServices.init()` or `SnowlyApp.body` `.task {}` |
| Start on demand | Expose a `func start()` method; call from the view that needs it |
| Stop when session ends | `SessionTrackingService` stops dependent services |
| Crash recovery | Services may read from `UserDefaults` in init to restore state |
