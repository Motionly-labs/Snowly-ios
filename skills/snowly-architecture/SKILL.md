---
name: snowly-architecture
description: Use when designing, implementing, or reviewing Snowly iOS/watchOS code. Defines layer responsibilities, dependency rules, state management, naming conventions, and how to add new features. Use this before snowly-ios-design or snowly-localization — it defines the structural envelope everything else fits inside.
user-invocable: true
---

# Snowly Architecture

## When Invoked

Operate in one of two modes based on user intent:

- **Review mode** (default): Audit the specified file(s) or feature for architectural violations. List each violation with severity and a concrete fix.
- **Scaffold mode**: If the user says "scaffold", "new feature", or "add [domain]", generate file stubs for all required layers (see Steps → Scaffold).

If no target is specified, ask: _"Which file, feature, or layer should I review or scaffold?"_

---

## Execution Steps

### Review Mode

1. Read the target files.
2. Check each file against the **Domain Reference** rules below.
3. Output a violation table (see **Output**).
4. List what is correctly implemented.
5. Offer to fix violations if asked.

### Scaffold Mode

1. Identify the feature domain (e.g., `Run`, `Crew`, `Weather`).
2. Generate stubs in this order:
   - `Models/<Domain>.swift` — struct or `@Model` (choose based on persistence need)
   - `Services/Protocols/<Domain>Providing.swift` — minimal `@MainActor` protocol
   - `Services/<Domain>Service.swift` — `@Observable @MainActor final class`
   - `Views/<Feature>/<Feature>View.swift` — `@Environment`-based view
3. List the injection step needed in `AppServices.swift`.
4. List required test file(s) in `SnowlyTests/`.

---

## Domain Reference

### 4-Layer Architecture (downward dependency only)

```
Views → Services → Models → Shared / Utilities
```

| Layer | Location | Rules |
|-------|----------|-------|
| **Views** | `Snowly/Views/` | Read `@Observable` state only; no service creation; no system API calls; no business logic |
| **Services** | `Snowly/Services/` | `@Observable @MainActor`; own state; wrap system frameworks; inject dependencies via `init` |
| **Models** | `Snowly/Models/` | SwiftData `@Model` (persistent) or plain struct/enum (transient); no business logic |
| **Shared** | `Snowly/Shared/` | Pure Swift only; no platform imports; compiles on both iOS and watchOS |
| **Utilities** | `Snowly/Utilities/` | Zero dependencies; pure functions as `static enum` |

### Repository Structure

```
Snowly/
├── DesignSystem/       Design tokens (ColorTokens, Typography, Spacing, …)
├── Extensions/         Type extensions (Type+Domain.swift)
├── Models/             @Model classes and non-persisted structs/enums
├── Resources/          Localizable.xcstrings, assets
├── Services/
│   ├── Protocols/      One protocol file per service
│   └── *.swift         Concrete service implementations
├── Shared/             iOS + watchOS shared types (TrackPoint, WatchMessage, …)
├── Utilities/          CircularBuffer, UnitConversion, TrackingStatePersistence, …
└── Views/
    ├── Home/           Active tracking, speed curve, session summary
    ├── Gear/           Equipment management
    ├── Activity/       Session history and detail
    ├── Profile/        User settings, personal bests
    ├── Onboarding/     First-launch flow
    └── Shared/         Reusable components used by 2+ features
```

### Dependency Rules

1. Views depend on Services via `@Environment` — never the reverse.
2. Services depend on other Services only through their protocol, injected at `init`.
3. `Shared/` has zero platform imports — no CoreLocation, CoreMotion, SwiftUI, UIKit.
4. No circular dependencies between services.
5. Tests mock services via protocol, not concrete type.

### State Management

| Annotation | When to Use |
|-----------|-------------|
| `@Observable` | Service-owned state (on `@Observable @MainActor final class`) |
| `@State` | Transient local UI state (e.g., `isSheetPresented`) |
| `@Query` | SwiftData fetches in views |
| `@Binding` | Parent → child data flow |
| `@Environment` | Injected services |

Never use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `DispatchQueue.main.async`.

### Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| Service class | `{Domain}Service` | `LocationTrackingService` |
| Service protocol | `{Domain}Providing` / `{Domain}Detecting` | `LocationProviding` |
| View | `{Feature}View` | `ActiveTrackingView` |
| SwiftData model | `{Entity}` (singular noun) | `SkiSession`, `SkiRun` |
| Data struct | `{Descriptor}Data` or plain noun | `TrackPoint`, `CompletedRunData` |
| Extension file | `{Type}+{Domain}.swift` | `CLLocation+Haversine.swift` |
| Test file | `{Subject}Tests.swift` | `RunDetectionTests.swift` |

### Adding a New Feature — Decision Tree

1. **System API needed?** → Service (`@Observable @MainActor`) + Protocol
2. **Renders UI?** → View (uses `@Environment`, no logic)
3. **Persists data?** → SwiftData `@Model`; if transient → plain struct
4. **Pure computation?** → Static-method `enum` in `Utilities/` or `Services/`
5. **Used by watchOS too?** → `Shared/` (must have zero platform imports)

### Data Model Rules

- `@Model` classes: use `@Attribute(.unique) var id: UUID`; owned children use `@Relationship(deleteRule: .cascade)`.
- **Never** store high-frequency arrays (e.g., `TrackPoint`) as `@Model` children. Serialize as `Data` with `@Attribute(.externalStorage)`.
- Large binary `Data` fields on `@Model` must use `@Attribute(.externalStorage)` (threshold: >~1 KB).
- Local-only settings → `DeviceSettings` in the local store. Never add them to a CloudKit-synced model.

### Testing Conventions

- Framework: **Apple Swift Testing** (`@Test`, `#expect`, `#require`) — not XCTest for unit tests.
- Location: `SnowlyTests/`.
- What to test: pure functions, state machine transitions, algorithms.
- What **not** to test: SwiftUI rendering, system API integration.
- Mock via protocol injection at `init`.
- Annotate test structs with `@MainActor` when testing `@MainActor` services.

### Anti-Patterns (flag as violations)

| Anti-Pattern | Correct Approach |
|-------------|-----------------|
| ViewModel of any kind | Use `@Observable` service + `@Environment` |
| Singleton (`.shared`) | Inject service from `AppServices` |
| Business logic in view `body` | Move to service method |
| System API imported in a view | Move to service |
| Service created inside a view | Created once in `AppServices`, injected |
| Circular service dependency | Refactor; one service is doing too much |
| `TrackPoint` as `@Model` children | Serialize as `Data` with `.externalStorage` |
| Struct mutation in-place | Create new instance (value-type immutability) |
| Hardcoded visual values in views | Use `DesignSystem/` tokens |
| Hardcoded UI text | Use `Localizable.xcstrings` key |
| `UserDefaults` for app data | Use SwiftData (`DeviceSettings`) |
| Reading `locationService.currentAltitude` / `currentSpeed` downstream | Use `SessionTrackingService.currentAltitude` / `currentSpeed` (Kalman-filtered). Only `TrackingEngine.ingest()` and `primeRecentWindow()` consume raw `TrackPoint` data. |
| Adding raw GPS fields to `LocationProviding` protocol | The protocol must not expose sensor values — only stream and authorization APIs. Filtered values live on `SessionTrackingService`. |

### Key Files Reference

| File | Role |
|------|------|
| `Snowly/SnowlyApp.swift` | App entry point, `AppServices` wiring, `ModelContainer` setup |
| `Snowly/Services/SessionTrackingService.swift` | Orchestrator — coordinates all tracking services |
| `Snowly/Services/LocationTrackingService.swift` | GPS wrapper, active + passive modes |
| `Snowly/Services/RunDetectionService.swift` | Pure activity detection (`static enum`) |
| `Snowly/Services/SegmentFinalizationService.swift` | Converts windows to finalized runs |
| `Snowly/Services/GPSKalmanFilter.swift` | Position + speed smoothing |
| `Snowly/Services/StatsService.swift` | Pure stats aggregation (`static enum`) |
| `Snowly/Shared/SharedConstants.swift` | All algorithm tuning parameters |
| `Snowly/Shared/TrackPoint.swift` | Core GPS data model (shared iOS + watchOS) |
| `Snowly/Models/SkiSession.swift` | Aggregate root for a tracking session |
| `Snowly/Models/SkiRun.swift` | Single run/lift segment with binary track storage |
| `Snowly/Models/SchemaVersions.swift` | SwiftData schema migration plan |

---

## Output

### Review Report

```
## Architecture Review: <FileName or Feature>

### Violations
| # | File | Line | Rule Violated | Severity | Fix |
|---|------|------|---------------|----------|-----|
| 1 | ...  | ...  | ...           | Critical / High / Low | ... |

### Compliant Patterns
- <what is correctly implemented>

### Recommendations
- <optional non-critical improvements>
```

Severity guide: **Critical** = compile-time issue or data loss risk; **High** = architectural rule violation; **Low** = style or naming.

### Scaffold Output

Emit each file as a fenced Swift code block labeled with the file path. Include only skeletons — no implementation bodies. End with the injection step for `AppServices.swift` and the list of test files to create.
