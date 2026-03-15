---
name: snowly-release-gate
description: Pre-release quality gate for Snowly iOS. Run before every TestFlight or App Store submission. Audits build consistency, release configuration, product semantics, critical flows, data integrity, UI/UX, performance, privacy compliance, and App Store metadata. Produces a structured report with BLOCKER/WARNING/PASS findings and a final gate decision. A passing build is not a passing gate.
user-invocable: true
---

# Snowly Release Gate

## Purpose

This skill enforces a structured quality gate before any TestFlight or App Store submission. Its role is to prevent low-quality, inconsistent, misconfigured, or non-compliant releases — not to accelerate shipping.

A build that compiles and passes unit tests is **not** release-ready by default. This gate audits nine dimensions that build correctness does not cover.

Do not treat any dimension as optional. Do not compress multiple findings to save space. Do not mark a dimension PASS without reading the relevant files.

The gate produces one of three decisions:

- **BLOCKED** — one or more BLOCKER findings exist. Do not submit to TestFlight or App Store.
- **CONDITIONAL** — no blockers, but WARNING findings must each be acknowledged or resolved.
- **APPROVED** — no blockers, all warnings resolved or explicitly documented with rationale.

---

## When Invoked

Run all nine dimensions. There are no modes and no partial runs.

If the user specifies a version or build number, use it in the report header. Otherwise, read it from `Info.plist`.

Do not begin writing the report until all file reads from Steps 1–3 are complete. Verify; do not assume.

---

## Execution Protocol

### Step 1 — Collect Build Identity

Read before auditing any dimension:

- `Info.plist` — `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleIdentifier`, all `NS*UsageDescription` strings, `UIBackgroundModes`
- `SnowlyWidgetExtension/Info.plist` — version, build, bundle ID
- `Snowly.xcodeproj/project.pbxproj` — RELEASE build settings, `CODE_SIGN_IDENTITY`, `PRODUCT_BUNDLE_IDENTIFIER`, `IPHONEOS_DEPLOYMENT_TARGET`, entitlement file references
- `Snowly.entitlements` (or equivalent) — declared capabilities
- `Snowly/Shared/SnowlyActivityAttributes.swift` — Live Activity type used by both app and widget

### Step 2 — Collect Configuration Artifacts

Read:

- `Snowly/SnowlyApp.swift` — `AppServices` wiring, `ModelContainer` dual-store setup, any base URL constants
- `Snowly/Shared/SharedConstants.swift` — algorithm constants, state persistence keys, crash recovery key
- `Snowly/Models/SchemaVersions.swift` — current schema version, migration stages
- `Snowly/PrivacyInfo.xcprivacy` if present — declared data types and API categories

### Step 3 — Sample Critical Path Code

Read a representative cross-section of critical files. Do not skip this step:

- `Snowly/Services/SessionTrackingService.swift` — session lifecycle, HealthKit save, crash recovery
- `Snowly/Services/LocationTrackingService.swift` — permission handling, background mode, GPS rate
- `Snowly/Services/SkiDataUploadService.swift` — server URL, upload path
- `Snowly/Views/Home/ActiveTrackingView.swift` — UI during active tracking
- `Snowly/Views/Home/SessionSummaryView.swift` — post-session display, metric labels
- Any gear or checklist view — product terminology in UI
- `Snowly/Views/Profile/SettingsView.swift` — unit system, settings language

### Step 4 — Audit All Nine Dimensions

Apply every rule in each dimension section below. For every finding, record exactly:

- **Severity**: BLOCKER | WARNING
- **What is wrong** — specific, with file path and line reference when determinable
- **Why it matters for release quality**
- **What layer or area is affected**
- **What kind of fix is needed**

PASS findings require only a one-line confirmation. Do not omit PASS rows — they confirm the dimension was actually checked.

### Step 5 — Compile Report

Produce the report in the Output format. Every dimension must appear. Every finding must appear individually.

---

## Dimension Reference

---

### 1. Build & Signing Consistency

Verify that the binary produced by Archive is structurally correct and signable for distribution. A successful Debug build does not imply a correct Release Archive.

**Checks:**

- `CFBundleIdentifier` in each target's `Info.plist` matches `PRODUCT_BUNDLE_IDENTIFIER` in the RELEASE build configuration in `project.pbxproj`. Mismatch causes archive failure.
- Widget extension bundle ID is `<main_bundle_id>.SnowlyWidgetExtension`. Any other suffix will fail App Store Connect validation.
- Watch app bundle ID follows the `<main_bundle_id>.watchkitapp` convention (or the exact string in the project file).
- `CODE_SIGN_IDENTITY` for RELEASE is `iPhone Distribution` or `Apple Distribution` (Automatic signing is acceptable if the team and provisioning profile are correctly resolved). `iPhone Developer` in a RELEASE build is a BLOCKER.
- All targets share the same `IPHONEOS_DEPLOYMENT_TARGET`. A mismatch between app and extension causes runtime crashes on the lower target.
- Live Activity: `SnowlyActivityAttributes` must be compiled into both the main app and the widget extension. Verify the file's target membership in `project.pbxproj`.
- The Watch app target compiles. The Watch companion is a core product feature, not optional.
- `ENABLE_BITCODE` is not set to YES (deprecated; causes unnecessary build failure or linker warnings in Xcode 14+).

**Severity rules:**

| Issue | Severity |
|---|---|
| Bundle ID mismatch (any target) | BLOCKER |
| Signing identity is Developer in RELEASE | BLOCKER |
| Watch target does not build | BLOCKER |
| `SnowlyActivityAttributes` missing from widget target membership | BLOCKER |
| Deployment target inconsistency between targets | WARNING (BLOCKER if causes runtime crash) |
| `ENABLE_BITCODE` YES | WARNING |

---

### 2. Release Configuration Correctness

Verify that the RELEASE binary behaves as a production artifact — no debug overrides, no development endpoints, no stale version numbers.

**Checks:**

- `CFBundleShortVersionString` and `CFBundleVersion` are both incremented from the previous App Store or TestFlight submission. App Store Connect rejects duplicate build numbers; a repeated marketing version with a new build number is allowed but should be intentional.
- No hardcoded localhost URL (`127.0.0.1`, `localhost`, `0.0.0.0`), private IP, or staging server address in any source file, plist, or constants file. The production API base URL is `https://api.snowly.app/api/v1`.
- No `#if DEBUG` block that replaces a production code path with a mock, skips authentication, or disables a critical service. Debug-gated UI is acceptable; debug-gated service behavior is not.
- `ENABLE_TESTABILITY` is `NO` in the RELEASE build configuration. `YES` links extra symbols and test hooks into the binary.
- Swift optimization level (`SWIFT_OPTIMIZATION_LEVEL`) is `-O` or `-Owholemodule` for RELEASE, not `-Onone`.
- No `SWIFT_ACTIVE_COMPILATION_CONDITIONS` flags in RELEASE beyond `RELEASE` itself (e.g., no lingering `MOCK_SERVICES` or `SKIP_UPLOAD` flags).
- No `assert()` or `precondition()` calls that are relied upon for correctness — these are no-ops in optimized builds.

**Severity rules:**

| Issue | Severity |
|---|---|
| Build number repeated from prior submission | BLOCKER |
| Localhost or staging URL reachable from RELEASE binary | BLOCKER |
| Debug-gated service bypass active in RELEASE | BLOCKER |
| `ENABLE_TESTABILITY` YES in RELEASE | WARNING |
| Optimization level `-Onone` in RELEASE | WARNING |
| Stale compilation condition flag in RELEASE | WARNING |

---

### 3. Product Semantics Consistency

Verify that user-facing text uses product language, not internal model names. Snowly's product vocabulary is fixed and must not drift.

**Product Name Mapping:**

| Internal (code) | Product (UI) | Prohibited in UI |
|---|---|---|
| `GearAsset` | Gear (locker item) | "Asset", "GearAsset", "GearMaintenanceEvent" |
| `GearSetup` | Checklist | "Setup", "GearSetup" |
| `GearMaintenanceEvent` | (legacy, no UI surface) | Anything — must not appear in any visible text |
| `SkiRun` | Run / Lift Ride / Walk (per `activityType`) | "SkiRun", "run object" |
| `UserProfile` | (internal) | Raw field names |
| `DeviceSettings` | (internal) | Raw field names |

**Additional checks:**

- Unit system: speed, distance, and vertical labels must respect `DeviceSettings.unitSystem`. No hardcoded `"km/h"` or `"mph"` string literals in UI code; only the unit-system-resolved label.
- Session-level metric labels: "vertical" not "altitude drop"; "distance" not "total meters"; "runs" not "ski runs". Match the labels visible in the App Store screenshots.
- `runCount` on `SkiSession` must display only `.skiing` segments. Lifts and walks must not contribute to the displayed run count anywhere in the UI.
- Internal state labels (`idle`, `transitioning`, `walk`, `lift`) must not appear in any user-facing text. Only the product label for the resolved activity type is shown.
- "Crew" is the consistent feature name across Home, tab bar, session detail, and settings. No variant ("Team", "Group", "Friends") unless a product decision is documented.

**Severity rules:**

| Issue | Severity |
|---|---|
| Internal model name visible to user | BLOCKER |
| Unit system not respected in a metric display | BLOCKER |
| Lift or walk included in displayed run count | BLOCKER |
| Internal state label in UI | WARNING |
| Inconsistent product term across two or more screens | WARNING |

---

### 4. Critical User Flow Completeness

Verify that each critical flow is intact end-to-end. Do not accept that a flow works because its components compile. Trace the path through code; identify where it can break.

| Flow | What to Trace |
|---|---|
| **Session start** | GPS permission requested and handled; `SessionTrackingService` starts on permission grant; `ActiveTrackingView` reflects tracking state |
| **Background tracking** | `UIBackgroundModes` includes `location`; `allowsBackgroundLocationUpdates = true` set on `CLLocationManager`; session does not terminate when app backgrounds |
| **Crash recovery** | `TrackingStatePersistence` writes every `statePersistenceInterval` (30 s); on relaunch with orphaned state, recovery prompt appears and session is restorable |
| **Session stop** | All runs finalized; `SkiSession` denormalized fields populated; HealthKit workout saved; CloudKit sync triggered; no dangling in-progress state |
| **Watch companion** | WCSession activated; live metrics transmitted; watch-recorded sessions imported through `WatchBridgeService` via the tracking pipeline |
| **Crew join/leave** | `memberToken` stored in Keychain; location sharing starts after join; member removed cleanly on leave or kick; no stale Keychain entry after leave |
| **Gear checklist** | Locker gear creatable with at least a name; checklist buildable from locker gear; checklist attachable to a session; empty checklist handled gracefully |
| **Session history** | All completed sessions appear; `trackData` decoded without crash; session detail navigates and back-navigates cleanly |
| **Onboarding** | First launch shows onboarding; permission requests fire in sequence; onboarding does not re-appear after completion |
| **Share card export** | Share card renders with correct stats; no empty fields; export sheet appears and can be dismissed |

**Severity rules:**

| Issue | Severity |
|---|---|
| Flow results in crash | BLOCKER |
| Flow results in silent data loss | BLOCKER |
| Flow produces incorrect data without visible error | BLOCKER |
| Flow degrades gracefully but displays wrong state | WARNING |
| Flow unavailable when prerequisite is missing (e.g., Watch unpaired) but fails ungracefully | WARNING |

---

### 5. Data Correctness & State Integrity

Verify that the SwiftData model layer, CloudKit sync, crash recovery, and denormalized aggregates are internally consistent. Feature-level correctness does not imply data correctness.

**5.1 Denormalized session fields**

`SkiSession.totalDistance`, `totalVertical`, `maxSpeed`, and `runCount` are computed at session save from runs where `activityType == .skiing`. Lifts and walks must not contribute. Verify the computation site in `SessionTrackingService` or wherever `saveSession()` is called. Confirm the filter condition is explicit.

**5.2 TrackPoint binary blob**

`SkiRun.trackData` is a `Data` blob encoded with `JSONEncoder`. Verify:

- `trackData` is non-nil for every finalized ski run (a completed run with nil `trackData` is silent data loss)
- The decode path in `SkiRun.trackPoints` does not silently return `[]` on decode failure; it must log or surface the error

**5.3 CloudKit property requirements**

All properties on synced models (`SkiSession`, `SkiRun`, `Resort`, `GearSetup`, `GearAsset`, `GearMaintenanceEvent`, `UserProfile`) must have default values. A property without a default causes CloudKit schema rejection or silent sync failure on upgrade.

**5.4 Schema migration integrity**

If any synced model has had a property added, removed, or renamed since the last shipped version, a migration stage must exist in `SnowlyMigrationPlan.stages`. An empty `stages` array coexisting with schema changes causes data loss or a silent failure on app update. Read `SchemaVersions.swift` and compare with the model files.

**5.5 Store routing**

`DeviceSettings` and `ServerProfile` must be in the local (non-CloudKit) `ModelConfiguration`. Verify the `ModelContainer` setup in `SnowlyApp.swift` assigns them to the correct store. A local-only model routed to the synced store will be rejected by CloudKit.

**5.6 Crash recovery state**

The payload persisted at `SharedConstants.trackingStateKey` must contain enough information to reconstruct the session context on relaunch: at minimum the session ID, start time, current activity type, and accumulated metrics. Verify the serialization and deserialization are symmetric.

**5.7 No total session loss on termination**

A force-quit or OS termination during active tracking must not result in a completely lost session. The 30 s persist interval plus crash recovery must leave a restorable session record. Verify that the recovery path creates or updates the `SkiSession` record rather than discarding it.

**5.8 GearMaintenanceEvent schema presence**

`GearMaintenanceEvent` is a legacy compatibility model that must remain in the synced schema to avoid migration failures on devices that have this entity in their CloudKit database. Verify it is still declared in `SchemaVersions.swift` even if it has no UI surface.

**Severity rules:**

| Issue | Severity |
|---|---|
| Lift or walk included in session-level skiing metric | BLOCKER |
| Finalized ski run with nil `trackData` | BLOCKER |
| Synced model property without default value | BLOCKER |
| Schema change without migration stage | BLOCKER |
| Local-only model in synced store configuration | BLOCKER |
| Crash recovery payload insufficient for reconstruction | BLOCKER |
| Complete session loss on force-quit | BLOCKER |
| `trackPoints` decode failure silently returns empty | WARNING |
| `GearMaintenanceEvent` missing from schema | WARNING |

---

### 6. UI/UX & Visual Consistency

Verify that all visible UI is token-driven, brand-consistent, navigable, and resilient to empty and error states. UI polish is not sufficient; structural correctness is required.

**6.1 Design token compliance**

All visual values in UI code must come from `Snowly/DesignSystem/` token files:

- Colors: `ColorTokens.*` only — no `Color(hex:)`, no `Color(.systemBlue)`, no hardcoded color literals
- Spacing: `Spacing.*` only — no numeric `.padding(16)` or `.padding(.horizontal, 12)` literals
- Typography: `Typography.*` only — no `.font(.system(size:))` without a scalable metric
- Corner radius: `CornerRadius.*` only — no `cornerRadius(12)` literals
- Gradients: only defined gradient tokens — no new inline `LinearGradient` or `AngularGradient`

Before flagging a violation, read the relevant token file to confirm whether a token exists. If no token covers the value, that is a missing token, not a hardcoding exception.

**6.2 Brand palette**

Primary accent is warm amber (`ColorTokens.brandWarmAmber`). No screen uses blue as an accent for primary interactive elements. Verify any recently added view.

**6.3 Dark mode**

All `ColorTokens` values must be adaptive. No hardcoded dark-only or light-only color not derived from a token. Test the active tracking view, session summary, gear list, and settings screen mentally against a dark background.

**6.4 Dynamic Type**

`Typography` token styles must resolve to scalable sizes. Text labels that clip or overflow at accessibility text sizes are a UX failure.

**6.5 Navigation completeness**

Every screen reachable from the tab bar must have a back, dismiss, or cancel path. Sheets and modals must provide an explicit dismiss affordance. No orphaned screen exists that can only be exited by force-quitting.

**6.6 Empty states**

Session history, gear list (locker and checklists), and Crew member list must each display a non-blank empty state — a message or prompt, not blank white space.

**6.7 Error and loading states**

CloudKit sync errors, network failures in Crew location polling, and HealthKit authorization denial must produce visible user feedback. Silent failure (spinner that never resolves, blank screen, phantom "success" state) is a BLOCKER.

**Severity rules:**

| Issue | Severity |
|---|---|
| Dead-end navigation (no dismiss path) | BLOCKER |
| Error state with no user feedback | BLOCKER |
| Brand amber replaced by a different accent on a primary CTA | BLOCKER |
| Hardcoded color on a visible component | WARNING |
| Missing empty state on a primary list | WARNING |
| Token missing from DesignSystem for an already-used value | WARNING |

---

### 7. Performance, Stability & Resource Usage

Verify that the release binary will not drain battery, hang the main thread, grow memory without bound, or fail to complete background tasks. These issues do not appear in unit tests.

**7.1 GPS hot path integrity**

The `TrackingEngine` actor's per-point processing path must:

- Invoke `GPSKalmanFilter`, `MotionEstimator`, and `RunDetectionService.detect()` as pure functions (mutating struct or static enum methods)
- Contain no `DispatchQueue.main.async`
- Contain no synchronous disk I/O
- Not call `TrackingStatePersistence` per GPS update (must be timer-based at 30 s)

**7.2 SpeedCurveView render budget**

`SpeedCurveView` must:

- Hold ≤ 300 `FrozenPoint` values in its render buffer (drop oldest beyond this cap)
- Apply EMA (α = 0.35) in the data pipeline before appending to the buffer — not inside `body`
- Use `FrozenPoint` that is `Equatable` so SwiftUI can skip unchanged renders
- Not generate new `UUID()` values inside `body` as identifiers

**7.3 @Observable granularity**

Child views must receive scalar values (e.g., `speed: Double`), not entire service objects, when only one property is needed. Passing a full `@Observable` service to a label that displays one metric causes that label to re-render on any change to the service — at GPS frequency during tracking.

**7.4 CircularBuffer for rolling windows**

Any rolling window over GPS points or speed samples that can exceed ~100 elements must use `CircularBuffer` from `Utilities/`. `Array.removeFirst()` in a hot path is O(n) and causes reallocation — it is a BLOCKER at GPS frequency.

**7.5 Battery-aware GPS rate**

GPS update cadence must come from `DeviceSettings.trackingUpdateIntervalSeconds`. No hardcoded `CLLocationManager.distanceFilter` or direct `desiredAccuracy` override outside `LocationTrackingService`. Low-battery mode (`lowBatteryThreshold = 0.20`) must visibly reduce the update rate.

**7.6 Persist interval discipline**

`TrackingStatePersistence` must be invoked on a timer at `statePersistenceInterval` (30 s), not inside the GPS ingest path. One write per GPS point at 1 Hz produces 3,600 disk writes per hour — a battery and I/O drain.

**7.7 SwiftData fetch deferral**

`SkiRun.trackData` (binary blob, up to hundreds of KB per run) must not be decoded at session list render time. It must be decoded only when the session detail view is open. Verify the list view does not access `trackPoints` or trigger `trackData` decoding.

**7.8 Background task completion**

Any `BGProcessingTask` or `BGAppRefreshTask` must call `setTaskCompleted(success:)` in all code paths — including on error, on early exit, and in the `expirationHandler`. Missing completion calls starve future background execution.

**Severity rules:**

| Issue | Severity |
|---|---|
| `Array.removeFirst()` in GPS hot path | BLOCKER |
| `DispatchQueue.main.async` inside `@MainActor` service | BLOCKER |
| `trackData` decoded at session list render | BLOCKER |
| `BGTask` without `setTaskCompleted` on error path | BLOCKER |
| Crash recovery state written per GPS update | BLOCKER |
| SpeedCurveView without point cap | WARNING |
| EMA computed inside `body` | WARNING |
| Entire service object passed to child view displaying one property | WARNING |
| Hardcoded GPS rate outside `LocationTrackingService` | WARNING |

---

### 8. Privacy, Permissions, Capabilities & App Store Compliance

Verify that every permission string is accurate, every capability is declared, and no compliance rule is violated. App Store review holds privacy and entitlement violations to a higher standard than most code issues.

**8.1 Info.plist usage descriptions**

Every `NS*UsageDescription` string must:

- Accurately describe what Snowly does with the data (not generic boilerplate like "This app requires location access")
- Reference the specific feature: GPS ski tracking, background session recording, HealthKit workout logging, etc.
- Not be placeholder text or a copy-paste from another app

Required strings for Snowly: `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSMotionUsageDescription`. If any of these is absent or generic, expect App Store review rejection.

**8.2 Background modes**

`UIBackgroundModes` in `Info.plist` must include `location` for background GPS tracking. If background HealthKit delivery is used, `healthkit` must also be present. Missing background mode causes background tracking to silently terminate.

**8.3 PrivacyInfo.xcprivacy**

If new API categories were used since the last submission (new sensor access, new system API, new third-party SDK), `PrivacyInfo.xcprivacy` must declare them. Undeclared API usage generates App Store Connect warnings that can escalate to rejection.

**8.4 Entitlements match App Store Connect capabilities**

Every entitlement in `Snowly.entitlements` must have a matching capability enabled in the App Store Connect app record. An entitlement present in the file but disabled in the record causes archive signing failure or binary rejection.

**8.5 No third-party analytics**

Snowly's product principle: no cross-app tracking or third-party analytics SDKs. Verify no analytics SDK (Firebase Analytics, Mixpanel, Amplitude, Segment, etc.) was introduced. Crash reporting without analytics (e.g., standalone MetricKit) is permissible if disclosed.

**8.6 CloudKit container identifier**

The CloudKit container identifier in `Snowly.entitlements` must match the production container in App Store Connect. A staging container in a production binary causes data to sync to the wrong CloudKit database — undetectable until users report data loss.

**8.7 Export compliance**

Snowly uses HTTPS (TLS), Keychain storage, and potentially CryptoKit. Declare `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` if only standard system encryption is used (HTTPS, Keychain). If custom encryption is implemented, an export compliance document is required.

**8.8 App Tracking Transparency**

Verify no ad network, cross-app tracking SDK, or device fingerprinting mechanism was introduced. If any is present, an ATT permission prompt is required before any data collection.

**Severity rules:**

| Issue | Severity |
|---|---|
| Generic or placeholder `NS*UsageDescription` | BLOCKER |
| Missing `location` background mode | BLOCKER |
| CloudKit container pointing to wrong environment | BLOCKER |
| Third-party analytics SDK introduced | BLOCKER |
| Missing export compliance declaration | WARNING |
| Entitlement present in file but not in App Store Connect | WARNING |
| PrivacyInfo.xcprivacy missing new API category | WARNING |

---

### 9. Release Artifacts & App Store Metadata Readiness

Verify that the submission package is complete. A technically correct binary with incomplete or misleading metadata fails review or misleads users.

**9.1 Version and build numbers**

`CFBundleShortVersionString` and `CFBundleVersion` must both be incremented from the prior submission. All targets (app, widget, watch) must show the same marketing version. Mismatched versions across targets are visually inconsistent and may cause validation warnings.

**9.2 TestFlight notes**

Before uploading to TestFlight, internal build notes must describe:

- What changed in this build
- Which specific flows to test
- Any known issues or workarounds for testers

Empty TestFlight notes waste tester time and produce vague feedback.

**9.3 App Store screenshots**

If this release changed any primary screen (Home, Session, Gear, Activity, Profile), screenshots must be updated for all required device sizes: 6.7" and 6.5" iPhone at minimum, 5.5" if still in use. Screenshots showing removed features or old UI are a review risk.

**9.4 What's New text**

The "What's New" field in App Store Connect must describe what this version adds or fixes from the user's perspective. "Bug fixes and performance improvements" alone is acceptable only for pure maintenance releases. A feature release with that text is a missed marketing opportunity and a potential review flag.

**9.5 Privacy nutrition labels**

Privacy practice labels in App Store Connect must match what the app actually collects. If a new data type was added (new HealthKit metric, new location use case, new user-provided data field), the privacy label must be updated before submission. Apple cross-references privacy labels with binary behavior.

**9.6 No placeholder content**

Verify: no TODO comments in any user-visible UI string, no placeholder images in App Store metadata, no lorem ipsum text anywhere in the submission package.

**9.7 Support and marketing URLs**

The support URL and marketing URL in App Store Connect must resolve without redirect loops or 404. App Store review verifies these URLs are reachable.

**9.8 Age rating**

If Crew messaging or pins allow user-generated content, verify the age rating in App Store Connect is still appropriate. A new social interaction vector may require re-evaluation.

**Severity rules:**

| Issue | Severity |
|---|---|
| Build number identical to prior submission | BLOCKER |
| Privacy nutrition label not updated for new data type | BLOCKER |
| Placeholder or TODO text in user-visible UI | BLOCKER |
| Screenshots show features that were removed | WARNING |
| Missing or generic "What's New" text for feature release | WARNING |
| Empty TestFlight notes | WARNING |
| Support or marketing URL broken | WARNING |

---

## Output

Produce the report in exactly this format. Do not skip any dimension. Do not collapse multiple distinct findings into one row.

```
## Release Gate Report: Snowly iOS [version] (Build [build])

Gate Decision: BLOCKED | CONDITIONAL | APPROVED

---

### Dimension 1: Build & Signing Consistency

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|
| 1 | BLOCKER  | Widget Info.plist bundle ID does not match PRODUCT_BUNDLE_IDENTIFIER in RELEASE config | Archive will fail with signing mismatch | Xcode project / build settings | Update widget Info.plist CFBundleIdentifier to com.snowly.app.SnowlyWidgetExtension |
| 2 | PASS     | Deployment target consistent at iOS 18.0 across all targets | — | — | — |

---

### Dimension 2: Release Configuration Correctness

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 3: Product Semantics Consistency

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 4: Critical User Flow Completeness

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 5: Data Correctness & State Integrity

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 6: UI/UX & Visual Consistency

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 7: Performance, Stability & Resource Usage

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 8: Privacy, Permissions, Capabilities & App Store Compliance

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Dimension 9: Release Artifacts & App Store Metadata Readiness

| # | Severity | Finding | Why It Matters | Layer | Fix |
|---|----------|---------|----------------|-------|-----|

---

### Gate Summary

| Dimension | Status | Blockers | Warnings |
|-----------|--------|----------|---------|
| 1. Build & Signing | BLOCKED / PASS / WARNING | n | n |
| 2. Release Config | | | |
| 3. Product Semantics | | | |
| 4. Critical Flows | | | |
| 5. Data Integrity | | | |
| 6. UI/UX | | | |
| 7. Performance | | | |
| 8. Privacy & Compliance | | | |
| 9. Release Artifacts | | | |

---

### Final Gate Decision

**BLOCKED** — [n] blockers must be resolved before TestFlight or App Store submission.

Blockers (must resolve):
1. [Dim N] [One-line finding summary]
2. ...

Warnings (resolve or document rationale for deferral):
1. [Dim N] [One-line finding summary]
2. ...
```

---

## What This Gate Rejects

- Treating a successful build as release approval.
- Treating passing unit tests as evidence that critical flows are intact.
- Deferring a BLOCKER to a post-release hotfix without escalation.
- Marking a dimension PASS without reading the relevant files.
- Allowing a WARNING to be silently dropped with no acknowledgment.
- Conflating local feature correctness with system-level release quality.
- Producing a report before completing Steps 1–3.

Every BLOCKER must be resolved before release. Every WARNING must be explicitly acknowledged — with a documented rationale if deferred.
