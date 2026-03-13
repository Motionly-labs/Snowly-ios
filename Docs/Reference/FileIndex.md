# File Index

Flat index of every significant source file in the Snowly codebase.

---

## Entry Point

| Path | Role |
|---|---|
| `Snowly/SnowlyApp.swift` | App entry point; creates `AppServices`, sets up dual-store `ModelContainer`, injects services |

---

## Shared (iOS + watchOS)

| Path | Role |
|---|---|
| `Snowly/Shared/TrackPoint.swift` | `TrackPoint` struct, `FilteredTrackPoint`, `RecentTrackWindow` window utilities, haversine function |
| `Snowly/Shared/SharedConstants.swift` | All algorithm constants (thresholds, dwell times, battery levels) |
| `Snowly/Shared/WatchMessage.swift` | `WatchMessage` enum — full phone/watch IPC protocol |
| `Snowly/Shared/UnitSystem.swift` | `UnitSystem` enum (`.metric` / `.imperial`) |
| `Snowly/Shared/RunActivityType.swift` | `RunActivityType` enum (`.skiing`, `.lift`, `.walk`, `.idle`) |
| `Snowly/Shared/StartTrackingIntent.swift` | Siri / Shortcuts intent for starting a tracking session |

---

## Models

| Path | Role |
|---|---|
| `Snowly/Models/SkiSession.swift` | `@Model` — one day of skiing; denormalized aggregates |
| `Snowly/Models/SkiRun.swift` | `@Model` — individual run/lift segment; `trackData: Data?` binary blob |
| `Snowly/Models/Resort.swift` | `@Model` — resort metadata (name, location) |
| `Snowly/Models/GearSetup.swift` | `@Model` — internal checklist model backing the product-facing checklist concept |
| `Snowly/Models/GearAsset.swift` | `@Model` — internal locker gear model backing the product-facing gear concept |
| `Snowly/Models/GearMaintenanceEvent.swift` | `@Model` — compatibility-only legacy service-event model kept in the synced schema |
| `Snowly/Models/UserProfile.swift` | `@Model` — user display name, units, personal bests |
| `Snowly/Models/DeviceSettings.swift` | `@Model` — local-only device preferences, onboarding state, dashboard layout |
| `Snowly/Models/SchemaVersions.swift` | `SchemaV4` definition and `SnowlyMigrationPlan` |
| `Snowly/Models/TrackingDashboardLayout.swift` | `TrackingDashboardLayout` / `TrackingStatWidget` — widget configuration model |

---

## Services

| Path | Role |
|---|---|
| `Snowly/Services/SessionTrackingService.swift` | Orchestrator; owns tracking state machine, dwell-time filter, live metrics |
| `Snowly/Services/LocationTrackingService.swift` | GPS via `CLLocationManagerDelegate` callbacks |
| `Snowly/Services/MotionDetectionService.swift` | CoreMotion accelerometer/gyroscope; emits `MotionHint` |
| `Snowly/Services/BatteryMonitorService.swift` | Device battery level monitoring |
| `Snowly/Services/HealthKitService.swift` | HealthKit workout session (write) |
| `Snowly/Services/HealthKitCoordinator.swift` | Coordinates HealthKit authorization and workout finalization |
| `Snowly/Services/GPSKalmanFilter.swift` | Three-axis constant-velocity Kalman filter for GPS smoothing |
| `Snowly/Services/GearChecklistStore.swift` | Local persistence for visual checklist checkmarks |
| `Snowly/Services/GearLockerService.swift` | Pure helpers for locker gear and checklist composition |
| `Snowly/Services/GearReminderService.swift` | Local reminder schedules, persistence, and notification syncing |
| `Snowly/Services/MotionEstimator.swift` | Pure functions: computes `MotionEstimate` over a rolling window |
| `Snowly/Services/MotionEstimate.swift` | `MotionEstimate` and `MotionEstimateWindow` types |
| `Snowly/Services/RunDetectionService.swift` | Pure functions: classifies activity from `MotionEstimate` |
| `Snowly/Services/SegmentFinalizationService.swift` | Segment state machine; produces `CompletedRunData` |
| `Snowly/Services/SegmentValidator.swift` | Pure functions: validates and potentially demotes completed segments |
| `Snowly/Services/StatsService.swift` | Pure functions: session and season aggregate statistics |
| `Snowly/Services/WeatherService.swift` | WeatherKit current conditions |
| `Snowly/Services/SkiMapCacheService.swift` | Ski area map data (OpenStreetMap Overpass API) |
| `Snowly/Services/OverpassService.swift` | Low-level Overpass API client |
| `Snowly/Services/MusicPlayerService.swift` | `MPMusicPlayerController` wrapper |
| `Snowly/Services/PhoneConnectivityService.swift` | `WCSession` delegate; sends live updates to watch |
| `Snowly/Services/WatchBridgeService.swift` | Receives watch track points and imports them through the production pipeline |
| `Snowly/Services/SyncMonitorService.swift` | CloudKit sync status observation |
| `Snowly/Services/ShareCardRenderer.swift` | Renders 1080×1920 share card image |
| `Snowly/Services/MapSnapshotRenderer.swift` | `MKMapSnapshotter` wrapper for track map tiles |
| `Snowly/Services/FixtureReplayService.swift` | DEBUG-only: replays fixture track points through the production pipeline |
| `Snowly/Services/LiveActivityService.swift` | Live Activity / Dynamic Island updates |

---

## Service Protocols

| Path | Role |
|---|---|
| `Snowly/Services/Protocols/LocationProviding.swift` | Protocol for `LocationTrackingService` (enables mock injection) |
| `Snowly/Services/Protocols/HealthKitProviding.swift` | Protocol for `HealthKitService` |

---

## Design System

| Path | Role |
|---|---|
| `Snowly/DesignSystem/ColorTokens.swift` | Brand, semantic, and trail-difficulty color constants |
| `Snowly/DesignSystem/Typography.swift` | Font styles organized by category |
| `Snowly/DesignSystem/Spacing.swift` | 4-point spacing grid constants |
| `Snowly/DesignSystem/CornerRadius.swift` | Standard corner radius values |
| `Snowly/DesignSystem/AnimationTokens.swift` | Duration constants and preset `Animation` values |
| `Snowly/DesignSystem/ShadowTokens.swift` | Card and surface shadow presets |
| `Snowly/DesignSystem/Opacity.swift` | Named opacity levels |
| `Snowly/DesignSystem/ChartTokens.swift` | Chart-specific color and style constants |
| `Snowly/DesignSystem/RunColorPalette.swift` | Sequential warm-to-cool ramp for run indexing on maps and charts |

---

## Views

| Path | Role |
|---|---|
| `Snowly/Views/Home/HomeView.swift` | Home tab root — idle / active tracking routing |
| `Snowly/Views/Home/ActiveTrackingView.swift` | Live tracking screen with speed curve |
| `Snowly/Views/Home/TrackingStatGrid.swift` | Draggable widget grid for live stats |
| `Snowly/Views/Home/SessionSummaryView.swift` | Post-session summary card |
| `Snowly/Views/Home/SpeedCurveView.swift` | Live speed curve chart |
| `Snowly/Views/Home/HalfViolinRunSpeedChart.swift` | Session speed distribution chart |
| `Snowly/Views/Home/RunBarsView.swift` | Horizontal bar chart of run durations |
| `Snowly/Views/Home/LongPressStartButton.swift` | 2 s long-press start button |
| `Snowly/Views/Home/ResumeTrackingButton.swift` | Resume-tracking slide button |
| `Snowly/Views/Profile/ProfileView.swift` | User profile and personal bests |
| `Snowly/Views/Profile/SettingsView.swift` | App settings |
| `Snowly/Views/Onboarding/OnboardingPermissionsStep.swift` | Permission request onboarding step |
| `Snowly/Views/SplashView.swift` | Launch splash screen |

---

## Tests

| Path | Role |
|---|---|
| `SnowlyTests/GPSKalmanFilterTests.swift` | Unit tests for `GPSKalmanFilter` |
| `SnowlyTests/MotionEstimatorTests.swift` | Unit tests for `MotionEstimator` |
| `SnowlyTests/HealthKitServiceTests.swift` | Unit tests for `HealthKitService` using mocks |
| `SnowlyTests/SessionTrackingIntegrationTests.swift` | Integration tests for the full tracking pipeline |
| `SnowlyTests/CloudKitCompatibilityTests.swift` | CloudKit schema compatibility tests |

---

## Watch App

| Path | Role |
|---|---|
| `SnowlyWatch/Services/WatchConnectivityService.swift` | Receives `WatchMessage` commands from phone |
| `SnowlyWatch/Services/WatchLocationService.swift` | Watch GPS tracking for independent mode |
| `SnowlyWatch/Services/WatchWorkoutManager.swift` | HealthKit workout session on watch |

---

## Generator Scripts

| Path | Role |
|---|---|
| `Scripts/Generators/generate-zermatt-fixtures.swift` | Generates Zermatt fixture JSON from a recorded track file |

---

## Resources

| Path | Role |
|---|---|
| `Snowly/Resources/ReplayFixtures.manifest.json` | Fixture registry: IDs, display names, track file references |
| `Snowly/Resources/Localizable.xcstrings` | All user-facing strings (Swift 5.9 `.xcstrings` format) |
