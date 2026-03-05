//
//  SchemaVersions.swift
//  Snowly
//
//  SwiftData versioned schema and migration plan.
//

import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SkiSession.self,
            SkiRun.self,
            Resort.self,
            GearSetup.self,
            GearItem.self,
            UserProfile.self,
            DeviceSettings.self,
        ]
    }
}

enum SnowlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
