//
//  GearLockerService.swift
//  Snowly
//
//  Pure helpers for resolving locker gear and checklists.
//

import Foundation

enum GearLockerService {
    static func gear(
        in checklist: GearSetup,
        from lockerGear: [GearAsset],
        includeArchived: Bool = false
    ) -> [GearAsset] {
        lockerGear
            .filter { item in
                (includeArchived || !item.isArchived) && item.setupIDs.contains(checklist.id)
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func gearCount(
        in checklist: GearSetup,
        from lockerGear: [GearAsset],
        includeArchived: Bool = false
    ) -> Int {
        lockerGear.filter { item in
            (includeArchived || !item.isArchived) && item.setupIDs.contains(checklist.id)
        }.count
    }

    static func coreGearSummary(
        for checklist: GearSetup,
        in lockerGear: [GearAsset],
        limit: Int = 4
    ) -> String {
        let gearNames = gear(in: checklist, from: lockerGear)
            .prefix(limit)
            .map(\.displayName)

        if !gearNames.isEmpty {
            return gearNames.joined(separator: ", ")
        }

        if let notes = checklist.trimmedNotes.nonEmpty {
            return notes
        }

        return String(localized: "gear_locker_summary_empty")
    }

    static func checklistSubtitle(
        for checklist: GearSetup,
        in lockerGear: [GearAsset]
    ) -> String {
        let notes = checklist.trimmedNotes.nonEmpty
        let count = gearCount(in: checklist, from: lockerGear)
        let gearLabel = count == 1 ? String(localized: "gear_locker_item_count_one") : String(localized: "\(count) gear items")

        if let notes, count > 0 {
            return "\(notes) · \(gearLabel)"
        }
        if let notes {
            return notes
        }
        if count > 0 {
            return gearLabel
        }
        return String(localized: "gear_locker_subtitle_empty")
    }

    static func checklists(
        for gear: GearAsset,
        from lockerChecklists: [GearSetup]
    ) -> [GearSetup] {
        lockerChecklists
            .filter { gear.setupIDs.contains($0.id) }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    static func assign(_ asset: GearAsset, to setup: GearSetup) {
        guard !asset.setupIDs.contains(setup.id) else { return }
        asset.setupIDs.append(setup.id)
    }

    static func unassign(_ asset: GearAsset, from setup: GearSetup) {
        asset.setupIDs.removeAll { $0 == setup.id }
    }

    static func recentSessions(
        for asset: GearAsset,
        from sessions: [SkiSession],
        limit: Int = 5
    ) -> [SkiSession] {
        let setupIDs = Set(asset.setupIDs)
        guard !setupIDs.isEmpty else { return [] }
        return sessions
            .filter { session in
                guard session.runCount > 0, let setupId = session.gearSetupId else { return false }
                return setupIDs.contains(setupId)
            }
            .prefix(limit)
            .map { $0 }
    }

    static func checklistNamesSummary(
        for gear: GearAsset,
        from lockerChecklists: [GearSetup]
    ) -> String {
        let assignedChecklists = checklists(for: gear, from: lockerChecklists)
        guard !assignedChecklists.isEmpty else {
            return String(localized: "gear_locker_not_in_checklist")
        }

        let names = assignedChecklists.prefix(2).map(\.name)
        let remainingCount = assignedChecklists.count - names.count
        if remainingCount > 0 {
            return "\(names.joined(separator: ", ")) +\(remainingCount)"
        }
        return names.joined(separator: ", ")
    }
}
