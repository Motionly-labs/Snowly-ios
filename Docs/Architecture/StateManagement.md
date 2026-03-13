# State Management

How Snowly manages application state without ViewModels, `@Published`, or `ObservableObject`.

---

## The Pattern

Snowly uses the observation framework introduced in Swift 5.9 / iOS 17:

- **`@Observable` services** — hold mutable state; Swift generates fine-grained per-property observation automatically
- **`@Environment` injection** — services flow down the view hierarchy without manual propagation
- **`@Query`** — views load SwiftData objects directly without a ViewModel layer
- **No ViewModels** — views read from services and the model context directly

This is intentionally different from MVVM. There is no `@ObservableObject`, no `@Published`, and no `@StateObject` in the Snowly codebase.

---

## Environment Injection Chain

`AppServices` is created once in `SnowlyApp.body` as a `@State var`. All services are injected at the scene root:

```swift
// SnowlyApp.swift
var body: some Scene {
    WindowGroup {
        RootView()
            .environment(services.trackingService)
            .environment(services.locationService)
            .environment(services.skiMapCacheService)
            // ... other services
    }
    .modelContainer(modelContainer)
}
```

Leaf views access a service with:

```swift
struct ActiveTrackingView: View {
    @Environment(SessionTrackingService.self) var trackingService

    var body: some View {
        Text(trackingService.currentSpeedFormatted)
    }
}
```

The `@Environment` wrapper subscribes to only the properties the view body actually reads. Unrelated state changes in the service do not trigger a re-render.

---

## Service Classification

| Category | Examples | Pattern |
|---|---|---|
| Stateful services — injected | `SessionTrackingService`, `LocationTrackingService`, `PhoneConnectivityService` | `@Observable @MainActor final class`; injected via `.environment()` |
| Pure-function services — called directly | `RunDetectionService`, `MotionEstimator`, `SegmentValidator`, `StatsService` | `enum` namespace with `nonisolated static func`; no injection needed |
| SwiftData models — queried directly | `SkiSession`, `SkiRun`, `UserProfile` | `@Query` in views; `@Environment(\.modelContext)` for writes |

Pure-function services require no injection because they carry no state. They are called inline wherever needed.

---

## SwiftData in Views

**Reading:**

```swift
struct SessionListView: View {
    @Query(sort: \SkiSession.startDate, order: .reverse) var sessions: [SkiSession]

    var body: some View {
        List(sessions) { session in
            SessionRow(session: session)
        }
    }
}
```

**Writing:**

```swift
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let session: SkiSession

    func save(note: String) {
        session.noteBody = note
        try? modelContext.save()
    }
}
```

**Previews** always use in-memory containers:

```swift
#Preview {
    SessionListView()
        .modelContainer(for: SkiSession.self, inMemory: true)
}
```

---

## `DeviceSettings` Query

`DeviceSettings` lives in the local-only store. Views query it the same way as synced models — SwiftData routes to the correct store automatically:

```swift
@Query(sort: \DeviceSettings.createdAt) private var settings: [DeviceSettings]
private var deviceSettings: DeviceSettings? { settings.first }
```

---

## `SessionTrackingService` State Machine

The service exposes `state: TrackingState` which drives the home-screen routing:

```
idle ──(startTracking)──► tracking ──(pauseTracking)──► paused
                                    ◄──(resumeTracking)──
tracking / paused ──(stopTracking)──► idle
```

Views branch on `trackingService.state` directly — no additional state wrapper needed.

---

## Actor / MainActor Boundary

`SessionTrackingService` is `@MainActor`. Heavy GPS processing runs in a private Swift `actor` (`TrackingEngine`) off the main thread. Results are batched and published back to the `@MainActor` service via `await`, which keeps the UI responsive even at 1 Hz GPS update rate.

Views never interact with `TrackingEngine` directly — all communication goes through `SessionTrackingService`.
