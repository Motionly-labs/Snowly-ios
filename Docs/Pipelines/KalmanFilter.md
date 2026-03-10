# Kalman Filter

How `GPSKalmanFilter` smooths raw GPS track points into `FilteredTrackPoint` values suitable for activity detection.

Source file: `Snowly/Services/GPSKalmanFilter.swift`

---

## Purpose

Raw GPS positions from `CLLocationManager` contain noise of ±5–20 m even under good sky conditions. Skiing generates rapid direction changes and speed transients that amplify this noise in derived velocity estimates. The Kalman filter fuses position measurements with a constant-velocity motion model to produce smooth position and velocity estimates.

The filter is a `nonisolated mutating struct` — it carries no platform dependencies and can be used on any thread (including the `TrackingEngine` actor and the `FixtureReplayService` background loop).

---

## State Model

Three independent `KalmanFilter1D` instances run in parallel for the East, North, and Altitude axes of a local ENU coordinate frame.

Each `KalmanFilter1D` maintains a 2-element state vector:

```
x = [position, velocity]ᵀ
```

**Transition model (constant velocity):**

```
F = [[1, dt],
     [0,  1]]
```

**Process noise covariance (acceleration model):**

```
Q = σ_a² × [[dt⁴/4,  dt³/2],
             [dt³/2,  dt²  ]]
```

where `σ_a` is the acceleration noise standard deviation (`horizontalProcessNoise` for East/North, `verticalProcessNoise` for Altitude).

**Covariance matrix:** stored as three scalars of the symmetric 2×2 matrix: `p00` (position variance), `p01` (cross-term), `p11` (velocity variance).

---

## Tuning Constants

| Constant | Value | Unit | Meaning |
|---|---|---|---|
| `horizontalProcessNoise` | 3.0 | m/s² | Acceleration uncertainty for skiing turns and stops |
| `verticalProcessNoise` | 1.0 | m/s² | Smoother vertical — terrain changes gradually |
| `baseVelocityNoise` | 0.3 | m/s | Velocity measurement noise under good signal |
| `altitudeAccuracyFactor` | 2.5 | × | GPS altitude is typically 2.5× noisier than horizontal |
| `maxDt` | 10 | s | Cap time step; prevents covariance explosion on GPS gaps |
| `minMeasuredSpeed` | 0.1 | m/s | Ignore Doppler velocity update when speed is too low to be reliable |
| `metersPerDegree` | 111,320 | m/° | WGS-84 mean conversion for ENU frame |

---

## ENU Local Frame

The first GPS point in a session sets the origin (`originLat`, `originLon` in radians). All subsequent positions are converted to East-North meters from that origin:

```
east  = (lonRad − originLon) × cos(originLat) × metersPerDegree × (180/π)
north = (latRad − originLat) × metersPerDegree × (180/π)
```

The cosine factor compensates for longitude convergence at higher latitudes. Ski resorts in the Alps sit at ~46°N where `cos(46°) ≈ 0.695`, making a 1° longitude step only ~77 km rather than the equatorial 111 km.

The inverse transform (`localToGeo`) converts filtered ENU positions back to latitude/longitude for the output `FilteredTrackPoint`.

---

## Predict–Update Cycle (Per GPS Point)

For each call to `GPSKalmanFilter.update(point:)`:

**1. Compute `dt`**

```swift
let rawDt = point.timestamp.timeIntervalSince(lastTimestamp)
let dt = min(rawDt, maxDt)
```

If `rawDt > maxDt`, scale process noise up by `sqrt(rawDt / maxDt)` to reflect growing uncertainty during a GPS gap.

**2. Predict**

All three 1D filters advance their state by `dt`:

```
position += velocity × dt
P = F·P·Fᵀ + Q
```

**3. Position Update**

Convert the raw GPS lat/lon to ENU, then call `updatePosition` on each axis:

```
Kalman gain: k = p00 / (p00 + R)   where R = accuracy²
position += k × (measurement − position)
velocity += (p01 / (p00 + R)) × (measurement − position)
P = (I − K·H) · P
```

Altitude measurement noise is `accuracy × altitudeAccuracyFactor`.

**4. Velocity Update (Horizontal Only)**

If measured speed exceeds `minMeasuredSpeed`, decompose into East/North velocity components using the bearing between the previous and current raw points, then call `updateVelocity` on each horizontal axis.

**5. Build Output**

Convert filtered ENU position back to lat/lon. Derive `estimatedSpeed` from the Euclidean magnitude of East/North velocities:

```swift
let speed = sqrt(eastFilter.velocity² + northFilter.velocity²)
```

Derive `course` from `atan2(eastVelocity, northVelocity)` and normalize to [0, 360).

---

## Initialization

On the first call to `update(point:)`, the filter initializes with:

- Position set to the raw GPS point (ENU origin)
- Velocity set to 0 m/s
- Position variance set to `max(accuracy², 1.0)`
- Velocity variance set to 100.0 m²/s² (≈ 10 m/s uncertainty — conservative prior)

The first point is returned unmodified as a `FilteredTrackPoint`.

---

## Reset

Call `GPSKalmanFilter.reset()` before starting a new tracking session. This zeros all filter state and clears the ENU origin, ensuring the filter starts fresh without any contamination from the previous session.

---

## Design Notes

- The filter does **not** use the `speed` field from `CLLocation` (Doppler-derived). It derives velocity from position displacements between consecutive raw points, which is more robust when the Doppler lock is poor (e.g., narrow mountain valleys).
- `@Attribute(.externalStorage)` on `SkiRun.trackData` stores raw (unfiltered) `TrackPoint` values. Filtering is re-applied on demand via `FixtureReplayService` or on-device review.
