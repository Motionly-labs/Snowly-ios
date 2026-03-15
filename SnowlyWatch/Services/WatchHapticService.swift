//
//  WatchHapticService.swift
//  SnowlyWatch
//
//  Haptic feedback for workout events.
//

import WatchKit

enum WatchHapticService {
    static func playStart() { WKInterfaceDevice.current().play(.start) }
    static func playStop() { WKInterfaceDevice.current().play(.stop) }
    static func playPause() { WKInterfaceDevice.current().play(.click) }
    static func playResume() { WKInterfaceDevice.current().play(.start) }
    static func playFailure() { WKInterfaceDevice.current().play(.failure) }
    static func playPersonalBest() { WKInterfaceDevice.current().play(.success) }
    static func playNewRun() { WKInterfaceDevice.current().play(.directionUp) }
}
