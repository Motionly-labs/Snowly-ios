//
//  OnboardingPermissionResolverTests.swift
//  SnowlyTests
//

import CoreLocation
import Testing
@testable import Snowly

@Suite("Onboarding Permission Resolver")
struct OnboardingPermissionResolverTests {

    @Test("tracking location requires always authorization")
    func trackingLocationRequiresAlwaysAuthorization() {
        #expect(
            OnboardingPermissionResolver.trackingLocationAction(for: .notDetermined) == .request
        )
        #expect(
            OnboardingPermissionResolver.trackingLocationAction(for: .authorizedWhenInUse) == .request
        )
        #expect(
            OnboardingPermissionResolver.trackingLocationAction(for: .authorizedAlways) == .done
        )
        #expect(
            OnboardingPermissionResolver.trackingLocationAction(for: .denied) == .openSettings
        )
    }

    @Test("weather follows foreground location availability")
    func weatherFollowsForegroundLocationAvailability() {
        #expect(
            OnboardingPermissionResolver.weatherAction(for: .notDetermined) == .request
        )
        #expect(
            OnboardingPermissionResolver.weatherAction(for: .authorizedWhenInUse) == .done
        )
        #expect(
            OnboardingPermissionResolver.weatherAction(for: .authorizedAlways) == .done
        )
        #expect(
            OnboardingPermissionResolver.weatherAction(for: .restricted) == .openSettings
        )
    }

    @Test("health action matches real HealthKit authorization state")
    func healthActionMatchesHealthKitAuthorizationState() {
        #expect(
            OnboardingPermissionResolver.healthAction(for: .notDetermined) == .request
        )
        #expect(
            OnboardingPermissionResolver.healthAction(for: .denied) == .openSettings
        )
        #expect(
            OnboardingPermissionResolver.healthAction(for: .authorized) == .done
        )
        #expect(
            OnboardingPermissionResolver.healthAction(for: .unavailable) == .unavailable
        )
    }
}
