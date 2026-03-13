# Data Models

How Snowly persists ski session data, why `TrackPoint` is a binary blob, and how the schema evolves.

---

## SwiftData Dual Store

`SnowlyApp` creates two separate `ModelConfiguration` instances inside a single `ModelContainer`:

| Store | Name | Models | CloudKit |
|---|---|---|---|
| Synced | `"Synced"` | `SkiSession`, `SkiRun`, `Resort`, `GearSetup`, `GearAsset`, `GearMaintenanceEvent`, `UserProfile` | Private database (disabled on simulator and during tests) |
| Local | `"Local"` | `DeviceSettings`, `ServerProfile` | None (device-only) |

SwiftData routes each model type to the correct store automatically. Views and services do not need to specify a store — `@Query` and `@Environment(\.modelContext)` work without modification.

> **Note:** CloudKit requires all synced-store properties to have default values. This applies to any new field you add to `SkiSession` or `SkiRun`.

## Gear Naming Mapping

The product language is fixed:

- `Gear` = one locker item the user creates
- `Checklist` = a named selection of locker gear
- `Reminder schedule` = local notification cadence attached to one gear item

The persisted model names remain:

- `GearAsset` = product `Gear`
- `GearSetup` = product `Checklist`
- `GearMaintenanceEvent` = compatibility-only legacy model kept in the synced schema

Reminder schedules and visual-checklist checkmarks are not stored in SwiftData. They are local persistence layers (`GearReminderScheduleStore`, `GearChecklistStore`) on top of the synced gear models.

---

## Entity Relationship

```
SkiSession (1) ──────────────── (*) SkiRun
  id: UUID (unique)                   id: UUID (unique)
  startDate: Date                     startDate: Date
  endDate: Date?                      endDate: Date?
  totalDistance: Double  ← denorm     distance: Double
  totalVertical: Double  ← denorm     verticalDrop: Double
  maxSpeed: Double       ← denorm     maxSpeed: Double
  runCount: Int          ← denorm     averageSpeed: Double
  resort: Resort?                     activityType: RunActivityType
  runs: [SkiRun]                      trackData: Data?  ← binary blob
                                      session: SkiSession?

SkiSession (*) ──── (0..1) Resort
  (cascade delete: SkiRun deleted with SkiSession)
```

---

## `TrackPoint` Storage Design

`SkiRun.trackData` is declared as:

```swift
@Attribute(.externalStorage) var trackData: Data?
```

`[TrackPoint]` is encoded with `JSONEncoder` and stored as a single binary blob, not as child `@Model` objects.

**Why not child objects?**

A single ski season of daily sessions produces approximately 100,000–300,000 track points. SwiftData uses SQLite under the hood. Storing each point as an individual row would mean:

- Hundreds of thousands of object faults on fetch
- O(n) SwiftData change tracking overhead on every GPS update during recording
- Slow `@Query` results whenever a session list loads

The binary blob approach means SwiftData tracks one row per run. The `@Attribute(.externalStorage)` annotation instructs SQLite to store the data payload in a separate file rather than inline in the row, which keeps the main database file small.

**Encoding:**

```swift
// Write (in SegmentFinalizationService, off-MainActor)
let trackData = try? JSONEncoder().encode(points)

// Read (in SkiRun.trackPoints computed property)
let points = try JSONDecoder().decode([TrackPoint].self, from: data)
```

`TrackPoint` is `Codable`, `Sendable`, and `Equatable`. It contains no platform-specific types, so it compiles for both iOS and watchOS.

---

## Denormalized Session Fields

`SkiSession` stores aggregate values that are redundant with `SkiRun` data:

| Field | Computed from |
|---|---|
| `totalDistance` | Sum of `SkiRun.distance` where `activityType == .skiing` |
| `totalVertical` | Sum of `SkiRun.verticalDrop` where `activityType == .skiing` |
| `maxSpeed` | Max of `SkiRun.maxSpeed` where `activityType == .skiing` |
| `runCount` | Count of `SkiRun` where `activityType == .skiing` |

These are populated once in `SessionTrackingService.saveSession()` at session end. The benefit is that `@Query(sort: \SkiSession.maxSpeed)` and similar queries execute in SQLite without loading any child runs.

> **Note:** Only `.skiing` segments contribute to session-level metrics. Lift and walk distances are stored per-`SkiRun` but excluded from the session aggregates.

---

## Schema Migrations

Schema versions and migration stages are defined in `Snowly/Models/SchemaVersions.swift`.

The current state is `SchemaV1` only, with an empty `stages` array:

```swift
enum SnowlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

When you add a property to a synced model, you must create a new schema version. See [Add a SwiftData Migration](../HowTo/AddSwiftDataMigration.md) for the step-by-step process.

CloudKit imposes the constraint that all new properties on synced models must have default values. A new `Double` property with `= 0` satisfies this automatically.

---

## Non-Persisted Models

Some types used in the tracking pipeline are plain Swift structs, not SwiftData models:

| Type | Role |
|---|---|
| `TrackPoint` | Raw GPS observation |
| `FilteredTrackPoint` | Kalman-smoothed GPS point |
| `MotionEstimate` | Feature window output |
| `DetectionDecision` | Activity classification result |
| `CompletedRunData` | In-memory finalized segment |
| `SessionSkiingMetrics` | Live session aggregate (displayed during tracking) |

These types are value types (`struct` or `enum`) and are discarded at session end after being serialized into the SwiftData store.
