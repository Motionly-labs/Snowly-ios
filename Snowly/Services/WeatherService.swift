//
//  WeatherService.swift
//  Snowly
//
//  WeatherKit integration with offline cache fallback.
//

import Foundation
import WeatherKit
import CoreLocation
import Observation

/// Simplified weather data for display.
struct SkiWeather: Sendable {
    let temperature: Double      // Celsius
    let condition: String        // e.g., "Snow", "Clear"
    let symbolName: String       // SF Symbol name
    let windSpeed: Double        // km/h
    let uvIndex: Int
    let lastUpdated: Date
}

@Observable
@MainActor
final class WeatherService {
    private(set) var currentWeather: SkiWeather?
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let weatherService = WeatherKit.WeatherService.shared
    private var lastFetchDate: Date?
    private static let minimumFetchInterval: TimeInterval = 300 // 5 minutes

    /// Fetch weather for a location, with cache fallback.
    func fetchWeather(latitude: Double, longitude: Double) async {
        // Rate limit: skip if last fetch was within 5 minutes
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < Self.minimumFetchInterval {
            return
        }

        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather

            currentWeather = SkiWeather(
                temperature: current.temperature.value,
                condition: current.condition.description,
                symbolName: current.symbolName,
                windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
                uvIndex: current.uvIndex.value,
                lastUpdated: Date()
            )
            lastFetchDate = Date()
        } catch {
            lastError = error.localizedDescription
            // Keep cached data if available
        }
    }

    /// Time since last weather update, formatted.
    var lastUpdateDisplay: String? {
        guard let weather = currentWeather else { return nil }
        let interval = Date().timeIntervalSince(weather.lastUpdated)
        if interval < 60 { return "Just now" }
        let minutes = Int(interval / 60)
        return "\(minutes)m ago"
    }
}
