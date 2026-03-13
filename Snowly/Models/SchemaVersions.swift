//
//  SchemaVersions.swift
//  Snowly
//

import Foundation
import SwiftData

enum SchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

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

enum SnowlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
