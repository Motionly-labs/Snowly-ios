//
//  SyncMonitorService.swift
//  Snowly
//
//  Monitors CloudKit sync status via NSPersistentCloudKitContainer events.
//

import Foundation
import CoreData

@Observable
@MainActor
final class SyncMonitorService {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var syncError: String?

    @ObservationIgnored private var observer: Any?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }

            MainActor.assumeIsolated {
                self?.handleEvent(event)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleEvent(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            markSyncStarted()
        } else {
            markSyncCompleted(endDate: event.endDate, error: event.error)
        }
    }

    // Internal for testability.
    func markSyncStarted() {
        isSyncing = true
        syncError = nil
    }

    // Internal for testability.
    func markSyncCompleted(endDate: Date?, error: Error?) {
        isSyncing = false
        lastSyncDate = endDate
        syncError = error?.localizedDescription
    }
}
