# Add a SwiftData Migration

How to add a new property to a synced `@Model` and keep existing data intact.

Source file: `Snowly/Models/SchemaVersions.swift`

---

## When This Is Required

You need a migration whenever you make a structural change to a `@Model` in the synced store (`SkiSession`, `SkiRun`, `Resort`, `GearSetup`, `GearAsset`, `GearMaintenanceEvent`, `UserProfile`). Local-only models (`DeviceSettings`, `ServerProfile`) require the same treatment.

Changes that **require** a migration:
- Adding a new stored property
- Removing a stored property
- Renaming a property (without an `@Attribute(.originalName:)` annotation)
- Changing a relationship's delete rule

Changes that **do not** require a migration:
- Changing a computed property
- Adding a Swift `extension` with no stored state
- Adding a new `@Model` class (SwiftData handles this automatically)

---

## CloudKit Constraint

All properties on synced-store models must have default values. This is a CloudKit requirement, not a Snowly convention. A new `Double` field with `= 0` or a new `String?` field with `= nil` both satisfy this constraint.

If you add a non-optional field without a default value, the CloudKit sync will fail at runtime on devices that already have data.

---

## Step-by-Step

### Step 1 — Copy the current schema into a new version

In `SchemaVersions.swift`, add the next version by copying the current schema enum. For example, if the live app is on `SchemaV1`, create `SchemaV2`:

```swift
enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SkiSession.self,
            SkiRun.self,
            Resort.self,
            GearSetup.self,
            GearAsset.self,
            GearMaintenanceEvent.self,
            UserProfile.self,
            DeviceSettings.self,
            ServerProfile.self,
        ]
    }
}
```

### Step 2 — Apply structural changes to the live models

Edit the actual `@Model` class (e.g., `SkiRun.swift`) to add the new property with a default value:

```swift
var avgTurnRate: Double = 0  // degrees/second
```

Do **not** modify `SchemaV1`. The schema enum is a snapshot — it references the model type, not a copy. `SchemaV2` is just a new version identifier pointing at the same updated models.

### Step 3 — Add the new schema to the migration plan

```swift
enum SnowlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        ]
    }
}
```

A lightweight migration handles adding columns with default values automatically. No custom code is needed.

### Step 4 — Custom migration (when required)

If you need to transform existing data (e.g., split one column into two, convert units), use a custom migration stage:

```swift
final class MigrateV1toV2: NSObject, NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        // custom transformation
    }
}

// In SnowlyMigrationPlan.stages:
.custom(MigrateV1toV2())
```

### Step 5 — Test

1. Build and run on the simulator. The existing store should open without crashing.
2. Check that existing sessions display correct data.
3. Create a new session and verify the new field is populated correctly.
4. On a physical device, install over an existing build to verify the migration path.

> **Note:** If `SnowlyMigrationPlan.stages` is empty, `SnowlyApp` treats an installed-app change as incompatible and resets existing store files before launch. Once migration stages exist, Snowly preserves the store and trusts SwiftData to migrate it on both simulator and device.
