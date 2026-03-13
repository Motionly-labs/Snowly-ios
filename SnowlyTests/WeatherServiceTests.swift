//
//  WeatherServiceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

struct WeatherServiceTests {

    @Test func skiWeather_init() {
        let weather = SkiWeather(
            temperature: -5.0,
            condition: "Snow",
            symbolName: "cloud.snow.fill",
            windSpeed: 25.0,
            uvIndex: 2,
            lastUpdated: Date()
        )

        #expect(weather.temperature == -5.0)
        #expect(weather.condition == "Snow")
        #expect(weather.symbolName == "cloud.snow.fill")
        #expect(weather.windSpeed == 25.0)
        #expect(weather.uvIndex == 2)
    }

    @Test @MainActor func weatherService_initialState() {
        let service = WeatherService()
        #expect(service.currentWeather == nil)
        #expect(service.isLoading == false)
        #expect(service.lastError == nil)
        #expect(service.lastUpdateDisplay == nil)
    }
}
