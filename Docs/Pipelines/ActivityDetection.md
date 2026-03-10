# Activity Detection

How Snowly classifies each GPS point as skiing, lift, walk, or idle using a two-window feature extractor and a pure-function decision tree.

Source files: `Snowly/Services/MotionEstimator.swift`, `Snowly/Services/RunDetectionService.swift`, `Snowly/Shared/SharedConstants.swift`

---

## Two-Window Architecture

Every GPS point is evaluated using two feature windows computed simultaneously:

| Window | Duration | Purpose |
|---|---|---|
| Transition | 4 s | Fast response to activity changes at run/lift boundaries |
| Steady | 12 s | Noise-resistant baseline; reduces false positives mid-run |

`MotionEstimator.transitionEstimate(current:recentPoints:)` and `MotionEstimator.steadyEstimate(current:recentPoints:)` both call a shared private `estimate(current:recentPoints:windowSeconds:window:)` function. The `window` tag distinguishes the two outputs in debugging.

---

## `MotionEstimate` Fields

```swift
struct MotionEstimate {
    let duration: TimeInterval          // window span in seconds (≥ 1)
    let avgHorizontalSpeed: Double      // m/s — haversine path / duration
    let avgVerticalSpeed: Double        // m/s — positive = ascending
    let hasReliableAltitudeTrend: Bool  // altitude rules usable?
    let sampleCount: Int                // number of filtered points used
    let confidence: Double              // [0, 1]
    let window: MotionEstimateWindow    // .transition or .steady
}
```

---

## Horizontal Speed Computation

1. Sum the haversine distances between consecutive window points (including `current`).
2. If `horizontalDistance ≥ 0.5 m` and `rawDuration > 0`, use `horizontalDistance / rawDuration`.
3. Otherwise fall back to `current.estimatedSpeed` (Kalman filter velocity output).

The 0.5 m threshold avoids dividing noise-floor displacements by small time deltas, which would produce wildly high speeds for a stationary device.

---

## Vertical Speed Computation

1. Collect altitudes from all window points (including `current`).
2. Apply a 3-point median filter if there are ≥ 3 samples (removes altitude spikes).
3. Compute a least-squares ordinary linear regression (OLS) of altitude vs time.
4. The slope is `avgVerticalSpeed` in m/s (positive = ascending, negative = descending).
5. If the regression denominator is too small (all timestamps equal), fall back to `(last - first) / duration`.

OLS is more robust than a simple first/last delta because it uses all points in the window, reducing the impact of individual GPS altitude outliers.

---

## Confidence Formula

```
coverage      = min(rawDuration / windowSeconds, 1)
sampleFactor  = min((sampleCount − 1) / 3, 1)
targetGap     = max(windowSeconds / 2, 1)
gapFactor     = min(targetGap / maxTimestampGap, 1)   // 0.5 if only 1 sample

confidence = clamp01(0.55 × coverage + 0.25 × sampleFactor + 0.20 × gapFactor)
```

`coverage` is the dominant term (55%) — if the window is mostly empty (session start, GPS gap), confidence is low even with dense samples.

---

## `hasReliableAltitudeTrend`

`true` when all four conditions hold:

1. `sampleCount ≥ 3` **OR** (`sampleCount ≥ 2` AND `rawDuration ≥ 0.75 × windowSeconds`)
2. `rawDuration ≥ 4 s`
3. `|avgVerticalSpeed| ≥ 0.15 m/s`
4. `confidence ≥ 0.35`

> **Note:** When `hasReliableAltitudeTrend = false`, all altitude-dependent classification rules are bypassed. This is correct behaviour at session start (insufficient history), in tunnels (GPS dropout), and in gondola loading zones (stationary or near-stationary). It is not a bug. The classifier falls back to speed-only rules.

---

## Classification Decision Tree

`RunDetectionService.classify(estimate:previousActivity:motion:)` applies this logic:

```
h = avgHorizontalSpeed
v = avgVerticalSpeed

h < 0.6 m/s                                        → idle
motion == .automotive                               → lift
h ≥ 6.0 m/s                                        → skiing  (unconditional)

wasLift = (previousActivity == .lift)
inLiftBand = (1.2 ≤ h ≤ 5.8)

if hasReliableAltitudeTrend:
    wasLift AND inLiftBand AND v ≥ -0.35            → lift  (continuity through transfer)
    h ≥ 2.8 AND v ≤ -0.15                           → skiing
    inLiftBand AND v ≥ -0.10                         → lift

wasLift AND inLiftBand                              → lift  (speed-only fallback)
h ≥ 2.8                                             → skiing
else                                                → idle
```

Rules are evaluated top-to-bottom; the first matching rule wins.

The `motion == .automotive` rule fires when `MotionDetectionService` reports a `MotionHint.automotive` hint, which it generates when CoreMotion's `CMMotionActivityManager` classifies the device as inside a vehicle.

---

## Conflict Resolution

When the transition window and steady window classify differently, `resolveActivity` arbitrates:

```
if transitionActivity == steadyActivity        → use either (same result)
if transitionConfidence < 0.72                 → use steady
if steadyActivity == previousActivity          → use transition (steady is conservative)
if transitionActivity == previousActivity      → use steady  (transition is conservative)
if transitionConfidence ≥ max(0.85, steadyConfidence + 0.15)
                                               → use transition (strong override)
else                                           → use steady
```

The intent: prefer the steady window for stability, but allow the transition window to override when it has high confidence and is reporting a change.

---

## Dwell-Time Hysteresis

The resolved activity from `RunDetectionService.analyze(...)` is a *raw* activity. It is not applied immediately to the tracked state. `SessionTrackingService.applyDwellTime(...)` wraps it in hysteresis:

A *candidate* activity is promoted to the stable state only after it has been observed continuously for the dwell period. If the candidate changes before the dwell expires, the timer resets.

**Normal dwell times:**

| Transition | Duration |
|---|---|
| Skiing → Lift | 14 s |
| Lift → Skiing | 6 s |
| Idle → Skiing | 3 s |
| Idle → Lift | 8 s |
| Any → Walk | 4 s |
| Walk → Skiing | 5 s |
| Walk → Lift | 15 s |

**Accelerated dwell** fires when `DetectionDecision.shouldAccelerateDwell == true`. This flag is set when:
- The resolved activity differs from `previousActivity`
- The transition window agrees with the resolved activity
- `transitionConfidence ≥ 0.80`

Accelerated dwell approximately halves the normal dwell time, allowing high-confidence transitions to register faster.
