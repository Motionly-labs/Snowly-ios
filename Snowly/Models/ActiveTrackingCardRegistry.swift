//
//  ActiveTrackingCardRegistry.swift
//  Snowly
//
//  Static metadata and default layout for every known card kind.
//

import Foundation

struct ActiveTrackingCardDefinition: Sendable {
    let kind: ActiveTrackingCardKind
    let titleKey: String                            // localisation key
    let icon: String                                // SF Symbol name
    let defaultSlot: ActiveTrackingSlot
    let defaultPresentationKind: ActiveTrackingPresentationKind
    let defaultConfig: ActiveTrackingCardConfig
    let supportedSlots: Set<ActiveTrackingSlot>
    let supportsSettings: Bool
}

enum ActiveTrackingCardRegistry {

    // MARK: - Definition lookup

    nonisolated static func definition(for kind: ActiveTrackingCardKind) -> ActiveTrackingCardDefinition {
        switch kind {
        case .currentSpeed:
            return .init(kind: kind, titleKey: "stat_current_speed",    icon: "speedometer",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .peakSpeed:
            return .init(kind: kind, titleKey: "stat_peak_speed",       icon: "bolt.fill",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .avgSpeed:
            return .init(kind: kind, titleKey: "stat_avg_speed",        icon: "gauge.with.dots.needle.33percent",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .vertical:
            return .init(kind: kind, titleKey: "common_vertical",       icon: "arrow.down",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .distance:
            return .init(kind: kind, titleKey: "common_distance",       icon: "point.topleft.down.to.point.bottomright.curvepath",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .runCount:
            return .init(kind: kind, titleKey: "common_runs",           icon: "number",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .skiTime:
            return .init(kind: kind, titleKey: "common_ski_time",       icon: "timer",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .liftCount:
            return .init(kind: kind, titleKey: "stat_lift_count",       icon: "arrow.up.arrow.down.circle",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .currentAltitude:
            return .init(kind: kind, titleKey: "stat_current_altitude", icon: "mountain.2",
                         defaultSlot: .grid, defaultPresentationKind: .scalar,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .altitudeCurve:
            return .init(kind: kind, titleKey: "stat_altitude_curve",   icon: "chart.xyaxis.line",
                         defaultSlot: .hero, defaultPresentationKind: .series,
                         defaultConfig: ActiveTrackingCardConfig(windowSeconds: SharedConstants.altitudeSampleWindowSeconds, smoothingAlpha: nil),
                         supportedSlots: [.hero], supportsSettings: true)
        case .speedCurve:
            return .init(kind: kind, titleKey: "stat_speed_curve",      icon: "speedometer",
                         defaultSlot: .hero, defaultPresentationKind: .series,
                         defaultConfig: .empty,
                         supportedSlots: [.hero], supportsSettings: false)
        case .profile:
            return .init(kind: kind, titleKey: "tracking_hero_profile_title", icon: "square.grid.2x2",
                         defaultSlot: .hero, defaultPresentationKind: .profile,
                         defaultConfig: ActiveTrackingCardConfig(windowSeconds: nil, smoothingAlpha: nil,
                             profileStatKinds: ["currentSpeed", "vertical", "runCount"]),
                         supportedSlots: [.hero], supportsSettings: true)
        case .heartRate:
            return .init(kind: kind, titleKey: "stat_heart_rate",       icon: "heart.fill",
                         defaultSlot: .grid, defaultPresentationKind: .text,
                         defaultConfig: .empty,
                         supportedSlots: [.grid], supportsSettings: false)
        case .heartRateCurve:
            return .init(kind: kind, titleKey: "stat_heart_rate_curve", icon: "heart.fill",
                         defaultSlot: .hero, defaultPresentationKind: .heartRateSeries,
                         defaultConfig: ActiveTrackingCardConfig(windowSeconds: SharedConstants.heartRateSampleWindowSeconds, smoothingAlpha: nil),
                         supportedSlots: [.hero], supportsSettings: false)
        }
    }

    // MARK: - Convenience lists

    nonisolated static var allHeroKinds: [ActiveTrackingCardKind] {
        ActiveTrackingCardKind.allCases.filter { definition(for: $0).supportedSlots.contains(.hero) }
    }

    nonisolated static var allGridKinds: [ActiveTrackingCardKind] {
        ActiveTrackingCardKind.allCases.filter { definition(for: $0).supportedSlots.contains(.grid) }
    }

    /// Default layout: three curve hero cards + number stat grid + hidden landscape config.
    nonisolated static var defaultInstances: [ActiveTrackingCardInstance] {
        let heroKinds: [ActiveTrackingCardKind] = [.speedCurve, .altitudeCurve, .heartRateCurve]
        let gridKinds: [ActiveTrackingCardKind] = [.vertical, .currentSpeed, .peakSpeed, .distance, .runCount]
        // .profile is not shown in portrait but lives in the layout to persist
        // landscape stat configuration across launches.
        let landscapeKinds: [ActiveTrackingCardKind] = [.profile]
        return (heroKinds + gridKinds + landscapeKinds).map { ActiveTrackingCardInstance.make(kind: $0) }
    }
}
