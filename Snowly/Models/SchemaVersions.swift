//
//  SchemaVersions.swift
//  Snowly
//

import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

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
