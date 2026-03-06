//
//  CachedAreasSheet.swift
//  Snowly
//
//  Sheet for browsing and managing cached ski area data.
//

import SwiftUI
import CoreLocation

struct CachedAreasSheet: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case nearby
        case downloaded

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nearby:
                return String(localized: "cache_tab_nearby")
            case .downloaded:
                return String(localized: "cache_tab_downloaded")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SkiMapCacheService.self) private var skiMapService
    @Environment(LocationTrackingService.self) private var locationService

    @State private var selectedTab: Tab = .nearby
    @State private var nearbyAreas: [NearbySkiArea] = []
    @State private var cachedAreas: [CachedAreaSummary] = []
    @State private var isLoadingNearby = false
    @State private var actionAreaID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch selectedTab {
                    case .nearby:
                        nearbyContent
                    case .downloaded:
                        downloadedContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .navigationTitle(String(localized: "cache_sheet_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common_cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            refreshCached()
            await refreshNearby()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .downloaded {
                refreshCached()
            } else {
                Task {
                    await refreshNearby()
                }
            }
        }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        if locationService.currentLocation == nil {
            ContentUnavailableView {
                Label(String(localized: "cache_empty_nearby"), systemImage: "location.slash")
            } description: {
                Text(String(localized: "home_weather_status_waiting_for_gps"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingNearby {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if nearbyAreas.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "cache_empty_nearby"), systemImage: "mappin.slash")
            } description: {
                if let error = skiMapService.lastError, !error.isEmpty {
                    Text(error)
                } else {
                    Text(String(localized: "cache_empty_nearby_description"))
                }
            } actions: {
                Button(String(localized: "cache_action_retry")) {
                    Task {
                        await refreshNearby()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(nearbyAreas) { area in
                let isBusy = actionAreaID == area.id || skiMapService.isAreaOperationInProgress(area.id)
                let isCached = cachedAreas.contains(where: { $0.id == area.id })

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(area.name)
                            .font(.headline)
                        Text(distanceText(for: area.distanceMeters))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isBusy {
                        ProgressView()
                    } else if isCached {
                        Button(String(localized: "cache_action_refresh")) {
                            actionAreaID = area.id
                            Task {
                                await skiMapService.refreshArea(id: area.id)
                                refreshCached()
                                actionAreaID = nil
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(String(localized: "cache_action_download")) {
                            actionAreaID = area.id
                            Task {
                                await skiMapService.cacheArea(area)
                                refreshCached()
                                actionAreaID = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isCached else { return }
                    skiMapService.loadCachedArea(id: area.id)
                    dismiss()
                }
            }
            .listStyle(.plain)
            .refreshable {
                await refreshNearby()
                refreshCached()
            }
        }
    }

    @ViewBuilder
    private var downloadedContent: some View {
        if cachedAreas.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "cache_empty_downloaded"), systemImage: "tray")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(cachedAreas) { area in
                let isBusy = actionAreaID == area.id || skiMapService.isAreaOperationInProgress(area.id)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(area.name)
                            .font(.headline)
                        Spacer()
                        Text(statusText(for: area, isBusy: isBusy))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor(for: area, isBusy: isBusy))
                    }

                    Text(distanceText(for: area.center.clLocationCoordinate2D.distance(to: locationService.currentLocation)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button(String(localized: "cache_action_refresh")) {
                            actionAreaID = area.id
                            Task {
                                await skiMapService.refreshArea(id: area.id)
                                refreshCached()
                                actionAreaID = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)

                        Button(String(localized: "cache_action_remove"), role: .destructive) {
                            skiMapService.removeArea(id: area.id)
                            refreshCached()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    skiMapService.loadCachedArea(id: area.id)
                    dismiss()
                }
            }
            .listStyle(.plain)
            .refreshable {
                refreshCached()
            }
        }
    }

    private func refreshCached() {
        cachedAreas = skiMapService.listCachedAreas()
    }

    private func refreshNearby() async {
        guard let center = locationService.currentLocation else {
            nearbyAreas = []
            return
        }
        isLoadingNearby = true
        nearbyAreas = await skiMapService.fetchNearbyAreas(center: center)
        isLoadingNearby = false
    }

    private func distanceText(for distanceMeters: Double?) -> String {
        guard let distanceMeters, distanceMeters >= 0 else {
            return String(localized: "cache_distance_unknown")
        }
        let format = String(localized: "cache_distance_format")
        return String(format: format, locale: Locale.current, distanceMeters / 1000.0)
    }

    private func statusText(for area: CachedAreaSummary, isBusy: Bool) -> String {
        if isBusy {
            return String(localized: "cache_status_downloading")
        }

        switch area.status {
        case .fresh:
            return String(localized: "cache_status_fresh")
        case .stale:
            return String(localized: "cache_status_stale")
        case .downloading:
            return String(localized: "cache_status_downloading")
        case .failed:
            return String(localized: "cache_status_failed")
        }
    }

    private func statusColor(for area: CachedAreaSummary, isBusy: Bool) -> Color {
        if isBusy {
            return .blue
        }

        switch area.status {
        case .fresh:
            return .green
        case .stale:
            return .orange
        case .downloading:
            return .blue
        case .failed:
            return .red
        }
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D?) -> Double? {
        guard let other else { return nil }
        let lhs = CLLocation(latitude: latitude, longitude: longitude)
        let rhs = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return lhs.distance(from: rhs)
    }
}
