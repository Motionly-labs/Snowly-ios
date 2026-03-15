# File Index

Flat index of the most significant source files in the Snowly codebase.

---

## App Entry And Targets

| Path | Role |
|---|---|
| `Snowly/SnowlyApp.swift` | Main app entry point; creates `AppServices`, configures persistence, injects services |
| `Snowly/QuickActionDelegate.swift` | Home Screen quick-action registration and dispatch |
| `Snowly/Views/AppLaunchView.swift` | Thin launch wrapper that hands off immediately to `RootView` |
| `SnowlyWidgetExtension/SnowlyWidgetBundle.swift` | Widget extension entry point for Live Activity and Control widget |
| `SnowlyWatch/SnowlyWatchApp.swift` | watchOS app entry point and watch-side service wiring |

---

## Shared (iOS + watchOS + widgets)

| Path | Role |
|---|---|
| `Snowly/Shared/TrackPoint.swift` | `TrackPoint`, `FilteredTrackPoint`, rolling-window helpers, haversine distance |
| `Snowly/Shared/SharedConstants.swift` | Tracking, detection, dwell-time, battery, and WatchConnectivity constants |
| `Snowly/Shared/WatchMessage.swift` | Full phone/watch IPC payload model |
| `Snowly/Shared/UnitSystem.swift` | Metric vs imperial setting |
| `Snowly/Shared/RunActivityType.swift` | Stable activity taxonomy: skiing, lift, walk, idle |
| `Snowly/Shared/StartTrackingIntent.swift` | App Intents shortcut for starting tracking |
| `Snowly/Shared/TogglePauseIntent.swift` | App Intents shortcut for pausing and resuming tracking |
| `Snowly/Shared/QuickActionState.swift` | Shared quick-action handoff state |
| `Snowly/Shared/SnowlyActivityAttributes.swift` | ActivityKit attributes shared with the widget extension |

---

## Models

| Path | Role |
|---|---|
| `Snowly/Models/SkiSession.swift` | `@Model` for a ski day with denormalized totals |
| `Snowly/Models/SkiRun.swift` | `@Model` for a run or transport segment, including serialized track data |
| `Snowly/Models/Resort.swift` | Cached resort metadata and identity |
| `Snowly/Models/UserProfile.swift` | Display name, units, avatar, and personal bests |
| `Snowly/Models/DeviceSettings.swift` | Local-only device preferences, onboarding state, dashboard layout |
| `Snowly/Models/ServerProfile.swift` | Local-only backend server profiles for Crew and upload flows |
| `Snowly/Models/GearAsset.swift` | Locker gear items |
| `Snowly/Models/GearSetup.swift` | Saved checklist definitions assembled from locker gear |
| `Snowly/Models/GearMaintenanceEvent.swift` | Legacy synced maintenance event model kept for schema compatibility |
| `Snowly/Models/ActiveTrackingCard.swift` | Persisted dashboard card instances plus the shared card-input contracts consumed by the UI |
| `Snowly/Models/ActiveTrackingCardRegistry.swift` | Static metadata, supported slots, and default layout for each tracking card kind |
| `Snowly/Models/TrackingDashboardLayout.swift` | Persisted configuration for the tracking stat grid |
| `Snowly/Models/SchemaVersions.swift` | `SchemaV1` definition and `SnowlyMigrationPlan` |

---

## Services

| Path | Role |
|---|---|
| `Snowly/Services/SessionTrackingService.swift` | Main tracking orchestrator and dwell-time owner |
| `Snowly/Services/LocationTrackingService.swift` | `CLLocationManager` wrapper with passive and active GPS collection |
| `Snowly/Services/MotionDetectionService.swift` | Core Motion integration and motion hints |
| `Snowly/Services/BatteryMonitorService.swift` | Battery level monitoring and low-battery state |
| `Snowly/Services/HealthKitService.swift` | HealthKit authorization and workout write path |
| `Snowly/Services/HealthKitCoordinator.swift` | Batches route and distance writes during active tracking |
| `Snowly/Services/GPSKalmanFilter.swift` | Three-axis Kalman filter for GPS smoothing |
| `Snowly/Services/MotionEstimator.swift` | Pure rolling-window feature extraction |
| `Snowly/Services/MotionEstimate.swift` | Motion estimate data structures shared by the detector |
| `Snowly/Services/RunDetectionService.swift` | Pure activity classification logic |
| `Snowly/Services/SegmentFinalizationService.swift` | Segment state machine and run completion pipeline |
| `Snowly/Services/SegmentValidator.swift` | Validation and demotion rules for completed segments |
| `Snowly/Services/StatsService.swift` | Aggregate stats and personal-best updates |
| `Snowly/Services/ActiveTrackingCardSnapshotAssembler.swift` | Centralized assembler that maps motion semantics and presentation series into card inputs |
| `Snowly/Services/SkiMapCacheService.swift` | Resort map cache and lookup orchestration |
| `Snowly/Services/OverpassService.swift` | Low-level Overpass API client for ski geometry |
| `Snowly/Services/WeatherService.swift` | WeatherKit access with cached fallback |
| `Snowly/Services/MusicPlayerService.swift` | Apple Music authorization, queue, and playback control |
| `Snowly/Services/SyncMonitorService.swift` | CloudKit sync event monitoring |
| `Snowly/Services/PhoneConnectivityService.swift` | iPhone-side `WCSession` coordination |
| `Snowly/Services/WatchBridgeService.swift` | Imports watch workouts into the iPhone production pipeline |
| `Snowly/Services/CrewAPIClient.swift` | Network client for Crew endpoints |
| `Snowly/Services/CrewService.swift` | Crew lifecycle, sync loops, pins, and membership state |
| `Snowly/Services/CrewPinNotificationService.swift` | Local notifications for crew pins and membership events |
| `Snowly/Services/SkiDataAPIClient.swift` | Network client for Snowly ski-day upload APIs |
| `Snowly/Services/SkiDataUploadService.swift` | Registration, token refresh, and session upload orchestration |
| `Snowly/Services/ServerHealthCheck.swift` | Stateless `/api/v1/health` connectivity check |
| `Snowly/Services/GearLockerService.swift` | Locker/checklist composition helpers |
| `Snowly/Services/GearChecklistStore.swift` | Persistence for visual checklist state |
| `Snowly/Services/GearReminderService.swift` | Reminder permission and notification scheduling |
| `Snowly/Services/ShareCardRenderer.swift` | Renders the 1920x1080 landscape share card |
| `Snowly/Services/MapSnapshotRenderer.swift` | `MKMapSnapshotter` wrapper for route imagery |
| `Snowly/Services/FixtureReplayService.swift` | DEBUG-only fixture replay into the production pipeline |
| `Snowly/Services/LiveActivityService.swift` | ActivityKit lifecycle management |

---

## Service Protocols

| Path | Role |
|---|---|
| `Snowly/Services/Protocols/LocationProviding.swift` | Protocol abstraction for location services |
| `Snowly/Services/Protocols/HealthKitProviding.swift` | Protocol abstraction for HealthKit workout services |
| `Snowly/Services/Protocols/CrewAPIProviding.swift` | Protocol abstraction for the Crew API client |
| `Snowly/Services/Protocols/SkiDataAPIProviding.swift` | Protocol abstraction for ski-day upload APIs |
| `Snowly/Services/Protocols/BatteryMonitoring.swift` | Protocol for battery state dependencies |
| `Snowly/Services/Protocols/MotionDetecting.swift` | Protocol for motion detection dependencies |

---

## Design System

| Path | Role |
|---|---|
| `Snowly/DesignSystem/ColorTokens.swift` | Brand, semantic, and trail-difficulty colors |
| `Snowly/DesignSystem/Typography.swift` | Named font styles |
| `Snowly/DesignSystem/Spacing.swift` | 4-point spacing grid |
| `Snowly/DesignSystem/CornerRadius.swift` | Standard corner radii |
| `Snowly/DesignSystem/AnimationTokens.swift` | Timing and animation presets |
| `Snowly/DesignSystem/ShadowTokens.swift` | Surface and card shadows |
| `Snowly/DesignSystem/Opacity.swift` | Named opacity levels |
| `Snowly/DesignSystem/ChartTokens.swift` | Chart-specific styling constants |
| `Snowly/DesignSystem/RunColorPalette.swift` | Sequential run coloring for charts and maps |
| `Snowly/DesignSystem/DashboardCardBackground.swift` | Shared material background for dashboard cards |

---

## Views

| Path | Role |
|---|---|
| `Snowly/Views/RootView.swift` | Top-level routing between onboarding and the main app |
| `Snowly/Views/MainTabView.swift` | Main tab scaffold |
| `Snowly/Views/Home/HomeView.swift` | Home-tab root for idle vs active tracking |
| `Snowly/Views/Home/ActiveTrackingView.swift` | Active session screen that consumes assembled tracking card inputs for hero, landscape, and summary stats |
| `Snowly/Views/Home/TrackingStatGrid.swift` | Reorderable live-stat widget grid that renders shared scalar/series card inputs without redefining semantics |
| `Snowly/Views/Home/RouteMapView.swift` | Session map and route rendering |
| `Snowly/Views/Home/SessionSummaryView.swift` | Post-session recap and share flow |
| `Snowly/Views/Home/ShareCardView.swift` | Share card composition view used by the renderer |
| `Snowly/Views/Activity/ActivityHistoryView.swift` | Session history list |
| `Snowly/Views/Activity/SessionDetailView.swift` | Full session detail screen |
| `Snowly/Views/Gear/GearLockerView.swift` | Locker inventory surface |
| `Snowly/Views/Gear/GearWorkspaceView.swift` | Checklist editing and body-zone workspace |
| `Snowly/Views/Profile/ProfileView.swift` | User profile and personal stats |
| `Snowly/Views/Profile/SettingsView.swift` | Settings, export, cache, and about screens |
| `Snowly/Views/Profile/ServerManagementView.swift` | Manage production and self-hosted API endpoints |
| `Snowly/Views/Profile/PrivacyView.swift` | In-app privacy policy presentation |
| `Snowly/Views/Onboarding/OnboardingFlow.swift` | First-launch onboarding flow |

---

## Tests

| Path | Role |
|---|---|
| `SnowlyTests/SessionTrackingIntegrationTests.swift` | End-to-end pipeline integration coverage |
| `SnowlyTests/RunDetectionTests.swift` | Activity classification tests |
| `SnowlyTests/GPSKalmanFilterTests.swift` | Filter predict/update tests |
| `SnowlyTests/SegmentFinalizationServiceTests.swift` | Segment state machine coverage |
| `SnowlyTests/CloudKitCompatibilityTests.swift` | Schema compatibility tests for CloudKit-safe models |
| `SnowlyUITests/SnowlyUITests.swift` | Basic UI smoke tests |

---

## Watch App

| Path | Role |
|---|---|
| `SnowlyWatch/Services/WatchConnectivityService.swift` | Watch-side connectivity to the phone |
| `SnowlyWatch/Services/WatchLocationService.swift` | Watch GPS management |
| `SnowlyWatch/Services/WatchWorkoutManager.swift` | Independent workout lifecycle and import payload creation |
| `SnowlyWatch/Views/WatchRootView.swift` | Watch root routing |
| `SnowlyWatch/Views/WorkoutActiveView.swift` | Active workout screen |
| `SnowlyWatch/Views/WorkoutSummaryView.swift` | Watch summary screen |
| `SnowlyWatch/Complications/ActiveSessionWidget.swift` | Watch complication for active sessions |

---

## Scripts And Resources

| Path | Role |
|---|---|
| `Scripts/generate-zermatt-fixtures.swift` | Generates or refreshes Zermatt replay fixtures |
| `Scripts/generate-zone-assets.swift` | Generates gear-zone mask assets |
| `Scripts/generate_share_card.swift` | Generates share-card output for local iteration |
| `Snowly/Resources/ReplayFixtures.manifest.json` | Fixture registry for `-replay_recap` |
| `Snowly/Resources/Localizable.xcstrings` | App localization catalog |
| `Snowly/PrivacyInfo.xcprivacy` | Apple privacy manifest for collected/accessed data declarations |
