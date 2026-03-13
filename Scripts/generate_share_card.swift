#!/usr/bin/env swift
import Foundation

print("🚀 Booting up Snowly Share Card Simulator...")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
task.arguments = [
    "test",
    "-project", "Snowly.xcodeproj",
    "-scheme", "Snowly",
    "-only-testing:SnowlyTests/ShareCardGeneratorTest",
    "-destination", "platform=iOS Simulator,name=iPhone 17 Pro"
]

print("   Executing: xcodebuild test -only-testing:SnowlyTests/ShareCardGeneratorTest ...")
print("   Please wait, compiling UI view and generating map snapshots...")

do {
    try task.run()
    task.waitUntilExit()

    let cardPath = "/tmp/Snowly/snowly_share_card.png"
    if FileManager.default.fileExists(atPath: cardPath) {
        print("✅ Success! Opening \(cardPath)")
        let openTask = Process()
        openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openTask.arguments = [cardPath]
        try openTask.run()
    } else {
        print("❌ Failed. Could not find generated share card at \(cardPath)")
    }
} catch {
    print("❌ Error running script: \(error)")
}
