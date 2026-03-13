# Constants Reference

All algorithm constants from `Snowly/Shared/SharedConstants.swift`.

---

## Feature Windows

| Constant | Value | Unit | Rationale |
|---|---|---|---|
| `transitionFeatureWindowSeconds` | 4 | s | Short window for fast activity-change response at run/lift boundaries |
| `steadyFeatureWindowSeconds` | 12 | s | Longer window for noise-resistant baseline detection |
| `historyRetentionSeconds` | 45 | s | Rolling buffer size; also the idle timeout before a segment is closed |

---

## Idle Detection

| Constant | Value | Unit | Rationale |
|---|---|---|---|
| `idleSpeedMax` | 0.6 | m/s | GPS noise floor for stationary devices; below this, speed readings are meaningless |

---

## Skiing Detection

| Constant | Value | Unit | Rationale |
|---|---|---|---|
| `skiFastMin` | 6.0 | m/s | Too fast for any ski lift; unconditionally classified as skiing |
| `skiMinSpeed` | 2.5 | m/s | Minimum horizontal speed when combined with altitude descent |
| `skiVerticalSpeedMax` | -0.15 | m/s | Must be descending at this rate or faster to confirm skiing |

---

## Lift Detection

| Constant | Value | Unit | Rationale |
|---|---|---|---|
| `liftSpeedMin` | 4.0 | m/s | Minimum horizontal speed to be moving on a lift; keeps brisk walking and station shuffling out of the lift band |
| `liftSpeedMax` | 5.8 | m/s | Maximum lift speed (below `skiFastMin` so the bands do not overlap) |
| `liftVerticalSpeedMin` | -0.10 | m/s | Allows horizontal and slightly-descending lift transport (e.g., flat gondola sections) |
| `liftContinuityVerticalSpeedMin` | -0.35 | m/s | Keeps an established lift through brief downward transfer sections (gondola acceleration/deceleration zones) |

---

## Segment Validation

| Constant | Value | Unit | Rationale |
|---|---|---|---|
| `minSkiRunDuration` | 15 | s | Segments shorter than this are lift-exit transitions, not real runs |
| `skiMinAltitudeLoss` | 12 | m | Minimum vertical drop to confirm a ski run (eliminates flat traverses) |
| `skiMinAvgSpeed` | 3.5 | m/s | Minimum average speed for a meaningful ski run |
| `liftMinSegmentDuration` | 30 | s | Very short lift segments are almost certainly false positives |
| `liftMinAltitudeGain` | 20 | m | Minimum altitude gain to confirm a lift ride |
| `liftMinAvgVerticalSpeed` | 0.10 | m/s | Distinguishes a lift from slow uphill walking |
| `walkMinSegmentDuration` | 6 | s | Walk segments shorter than this are discarded entirely as GPS noise |
| `walkHardMaxSpeed` | 8.0 | m/s | Physics guard rail: walking above this speed is impossible on snow |

---

## Activity Dwell Time (Hysteresis)

Minimum duration a newly detected activity must sustain before the stable state transitions.

| Constant | Value | Unit | Notes |
|---|---|---|---|
| `dwellTimeSkiingToLift` | 14 | s | Reduced from 25 s; lift has a distinct speed + altitude signature |
| `dwellTimeLiftToSkiing` | 6 | s | Relatively short; skier accelerates quickly from lift exit |
| `dwellTimeIdleToSkiing` | 3 | s | Short — the unconditional fast-speed rule fires before dwell expires |
| `dwellTimeIdleToLift` | 8 | s | Longer guard against brief walking |
| `dwellTimeAnyToWalk` | 4 | s | Walk transitions are uncommon; medium hysteresis |
| `dwellTimeWalkToSkiing` | 5 | s | |
| `dwellTimeWalkToLift` | 15 | s | Long guard — walking into a lift station looks like lift speed briefly |

---

## GPS Sampling

| Constant | Value | Unit | Use |
|---|---|---|---|
| `highSpeedThreshold` | 5.0 | m/s | Sampling rate hint for high-speed tracking |
| `mediumSpeedThreshold` | 2.0 | m/s | Sampling rate hint for medium-speed tracking |

---

## Detection Tuning

| Constant | Value | Rationale |
|---|---|---|
| `transitionOverrideConfidence` | 0.72 | Transition window confidence must exceed this to override the steady window |
| `transitionStrongOverrideConfidence` | 0.85 | Strong override threshold when both windows disagree and prior is neutral |
| `acceleratedDwellConfidence` | 0.80 | Only shorten hysteresis when detection is highly certain, preventing premature transitions |

---

## Stop Detection

| Constant | Value | Unit | Notes |
|---|---|---|---|
| `stopDurationThreshold` | 45 | s | Idle duration before the current segment is closed; matches `historyRetentionSeconds` |

---

## Battery

| Constant | Value | Notes |
|---|---|---|
| `lowBatteryThreshold` | 0.20 (20%) | Triggers low-battery tracking mode |
| `lowBatteryWarningThreshold` | 0.40 (40%) | Displays warning UI |
| `coldWeatherBatteryPenalty` | 0.30 (30%) | Effective capacity reduction assumed in cold weather |

---

## Crash Recovery

| Constant | Value | Notes |
|---|---|---|
| `statePersistenceInterval` | 30 | s | Tracking state serialized to `UserDefaults` every 30 s |
| `trackingStateKey` | `"snowly.tracking.state"` | `UserDefaults` key for crash-recovery state |
| `crewSyncPreferencesKey` | `"snowly.crew.syncPreferences"` | `UserDefaults` key for crew sync preferences |

---

## WCSession

| Constant | Value | Notes |
|---|---|---|
| `watchSessionKey` | `"snowly.watch.message"` | `WCSession` application context key |
