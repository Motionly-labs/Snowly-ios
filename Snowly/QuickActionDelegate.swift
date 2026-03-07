//
//  QuickActionDelegate.swift
//  Snowly
//
//  Handles Home Screen Quick Actions (long press on app icon).
//  Apple's official pattern: @UIApplicationDelegateAdaptor + UIWindowSceneDelegate.
//  See: https://developer.apple.com/documentation/UIKit/add-home-screen-quick-actions
//

import UIKit

@MainActor
final class QuickActionDelegate: NSObject, UIApplicationDelegate {
    static let startTrackingType = "com.snowly.start-tracking"

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Cold launch: capture shortcut item before scene connects
        if let shortcutItem = options.shortcutItem,
           shortcutItem.type == Self.startTrackingType {
            QuickActionState.shared.pending = true
        }
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

/// Handles quick action when app is already running (warm launch).
@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard shortcutItem.type == QuickActionDelegate.startTrackingType else {
            completionHandler(false)
            return
        }

        QuickActionState.shared.pending = true
        completionHandler(true)
    }
}
