//
//  LaunchRestorationCoordinator.swift
//  Snowly
//
//  Determines whether the current launch is a returning user who should
//  restore from CloudKit, a fresh user starting from scratch, or an
//  offline returning user whose iCloud data is currently unreachable.
//
//  Lifecycle:
//  1. Created during app init.
//  2. `determine()` called once RootView appears (needs iCloud availability info).
//  3. Onboarding steps read `state` to tailor their UI.
//  4. `beginRestoration()` / `completeFreshSetup()` called by user action.
//

import CoreData
import Foundation
import SwiftData
import os

@Observable @MainActor
final class LaunchRestorationCoordinator {

    enum State: Equatable {
        /// Initial state — checking fingerprint + iCloud availability.
        case determining
        /// Keychain fingerprint found + iCloud available → suggest restore.
        case returningUser
        /// User chose restore, waiting for CloudKit import.
        case restoringFromCloud
        /// CloudKit data arrived, ready for main app.
        case restored
        /// No fingerprint or user chose Start Fresh.
        case freshUser
        /// Fingerprint exists but iCloud is not available.
        case offlineReturning
    }

    private(set) var state: State = .determining

    private let fingerprint: UserIdentityFingerprint?
    private var cloudKitObserver: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var restorationModelContext: ModelContext?
    private let logger = Logger(subsystem: "com.Snowly", category: "RestorationCoordinator")

    init(fingerprint: UserIdentityFingerprint?) {
        self.fingerprint = fingerprint
    }

    deinit {
        let observer = MainActor.assumeIsolated { self.cloudKitObserver }
        let task = MainActor.assumeIsolated { self.timeoutTask }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        task?.cancel()
    }

    // MARK: - Public API

    /// Call once at launch to determine the user's status.
    func determine() {
        guard state == .determining else { return }

        guard let fingerprint else {
            logger.info("No Keychain fingerprint — treating as fresh user.")
            state = .freshUser
            return
        }

        let iCloudAvailable: Bool
        #if targetEnvironment(simulator)
        iCloudAvailable = false
        #else
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        #endif

        if iCloudAvailable {
            logger.info("Returning user detected (profile \(fingerprint.profileId)). iCloud available.")
            state = .returningUser
        } else {
            logger.info("Returning user detected but iCloud unavailable.")
            state = .offlineReturning
        }
    }

    /// User tapped "Restore from iCloud". Begin monitoring for CloudKit data.
    func beginRestoration(modelContext: ModelContext) {
        guard state == .returningUser || state == .determining else { return }
        state = .restoringFromCloud
        restorationModelContext = modelContext
        logger.info("Restoration started — listening for CloudKit import events.")

        startCloudKitObserver()
        startTimeout()
    }

    /// Called when profiles are detected by @Query in the restore step.
    func profilesArrived() {
        guard state == .restoringFromCloud else { return }
        logger.info("Profile data arrived from CloudKit.")
        state = .restored
        cleanup()
    }

    /// User chose Start Fresh or restoration timed out.
    func completeFreshSetup() {
        state = .freshUser
        cleanup()
    }

    /// Whether the timeout has fired without data arriving.
    /// The restore step can show a "continue waiting / start fresh" choice.
    private(set) var hasTimedOut = false

    // MARK: - Private

    private func startCloudKitObserver() {
        cloudKitObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard
                    self.state == .restoringFromCloud,
                    let event = notification.userInfo?[
                        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    ] as? NSPersistentCloudKitContainer.Event,
                    event.type == .import,
                    event.endDate != nil
                else { return }

                // Give @Query a moment to reflect newly imported records.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.state == .restoringFromCloud else { return }
                    guard let modelContext = self.restorationModelContext else { return }
                    // Check if profiles exist now.
                    let descriptor = FetchDescriptor<UserProfile>()
                    let count = (try? modelContext.fetchCount(descriptor)) ?? 0
                    if count > 0 {
                        self.profilesArrived()
                    }
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
                guard let self, self.state == .restoringFromCloud else { return }
                self.logger.info("Restoration timed out after 30s.")
                self.hasTimedOut = true
            } catch {}
        }
    }

    private func cleanup() {
        if let observer = cloudKitObserver {
            NotificationCenter.default.removeObserver(observer)
            cloudKitObserver = nil
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        restorationModelContext = nil
    }
}
