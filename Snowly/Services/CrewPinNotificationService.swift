//
//  CrewPinNotificationService.swift
//  Snowly
//
//  Handles in-app banners and local notifications for crew activity.
//

import Foundation
import UserNotifications
import SwiftUI
import os

@Observable
@MainActor
final class CrewPinNotificationService {

    /// The pin currently shown as an in-app banner (nil = no banner).
    private(set) var currentBanner: CrewPin?
    /// The membership event currently shown as an in-app banner (nil = no banner).
    private(set) var currentMembershipBanner: CrewMembershipEvent?

    /// Updated by the view layer to reflect current scene phase.
    var scenePhase: ScenePhase = .active

    private var dismissTask: Task<Void, Never>?
    private var membershipDismissTask: Task<Void, Never>?
    private var hasRequestedPermission = false

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "CrewPinNotification"
    )

    // MARK: - Public

    func handleNewPin(_ pin: CrewPin, scenePhase: ScenePhase) {
        if scenePhase == .active {
            showBanner(pin)
        } else {
            requestPermissionIfNeeded()
            scheduleLocalNotification(pin)
        }
    }

    func handleMembershipEvent(_ event: CrewMembershipEvent, scenePhase: ScenePhase) {
        if scenePhase == .active {
            showMembershipBanner(event)
        } else {
            requestPermissionIfNeeded()
            scheduleMembershipNotification(event)
        }
    }

    func dismissBanner() {
        dismissTask?.cancel()
        dismissTask = nil
        currentBanner = nil
    }

    func dismissMembershipBanner() {
        membershipDismissTask?.cancel()
        membershipDismissTask = nil
        currentMembershipBanner = nil
    }

    func requestPermissionIfNeeded() {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true

        Task {
            do {
                try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.logger.warning(
                    "Notification permission denied: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Private

    private func showBanner(_ pin: CrewPin) {
        dismissTask?.cancel()
        currentBanner = pin

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            currentBanner = nil
        }
    }

    private func showMembershipBanner(_ event: CrewMembershipEvent) {
        membershipDismissTask?.cancel()
        currentMembershipBanner = event

        membershipDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            currentMembershipBanner = nil
        }
    }

    private func scheduleLocalNotification(_ pin: CrewPin) {
        let content = UNMutableNotificationContent()
        content.title = pin.senderDisplayName
        content.body = pin.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "crew-pin-\(pin.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error(
                    "Failed to schedule pin notification: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func scheduleMembershipNotification(_ event: CrewMembershipEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.displayName
        content.body = membershipMessage(for: event)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "crew-membership-\(event.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error(
                    "Failed to schedule membership notification: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func membershipMessage(for event: CrewMembershipEvent) -> String {
        switch event.kind {
        case .joined:
            return "joined the crew."
        case .left:
            return "left the crew."
        }
    }
}
