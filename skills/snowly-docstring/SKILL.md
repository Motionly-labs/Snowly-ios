---
name: snowly-docstring
description: Use when writing or reviewing docstrings in Snowly. Defines when docstrings are required, which tier of detail is appropriate, and how to document algorithmic logic in depth.
user-invocable: true
---

# Snowly Docstrings

## When Invoked

Operate in one of two modes:

- **Write mode** (default): Add or rewrite docstrings for the specified file(s) or function(s). Choose Tier 1 or Tier 2 based on complexity. Output the updated code with docstrings added.
- **Review mode**: If the user says "review" or "audit", check existing docstrings for compliance and list violations.

If no target is specified, ask: _"Which file or function should I document or review?"_

---

## Execution Steps

### Write Mode

1. Read the target file(s).
2. For each public or internal type, property, and function: decide Tier 1 or Tier 2 (see rules below).
3. Write the docstring following the appropriate tier template.
4. Skip items listed under **Skip Docstrings For**.
5. Output the updated code with docstrings in place.

### Review Mode

1. Read the target file(s).
2. Flag each docstring violation (see **Forbidden**).
3. Output a violations table (see **Output**).

---

## Domain Reference

### When to Document

**Always document:**
- All `public` and `internal` types, properties, and functions
- Functions with non-obvious behavior, preconditions, side effects, or error behavior
- State machines, classifiers, filters, and any algorithmic logic

**Skip docstrings for:**
- Trivial private helpers whose name is fully self-explanatory (`private func resetBuffer()`)
- SwiftUI `body` computed properties and simple `@ViewBuilder` helpers
- Boilerplate conformances (`Equatable`, `Hashable`, `Codable`) with no custom logic

---

### Tier 1 — Brief (non-algorithmic functions)

Use for: straightforward functions, data transformations, simple computed properties.

Required: one-sentence summary that explains behavior beyond the name.
Include when relevant: parameters, return value, throws, side effects.

```swift
/// Returns the session duration formatted as `h:mm:ss`, or `m:ss` if under one hour.
func formattedDuration() -> String

/// Converts the stored speed from m/s to the user's preferred unit system.
/// - Parameter system: The target unit system (`.metric` or `.imperial`).
/// - Returns: Speed value in km/h or mph.
func speed(in system: UnitSystem) -> Double

/// Persists the current session snapshot to disk.
/// - Throws: `TrackingError.writeFailed` if the target directory is not accessible.
func saveSnapshot() throws
```

---

### Tier 2 — Full (algorithmic functions)

Use for: GPS processing, motion estimation, activity classification, filtering, state machines, numerical computations, domain-specific heuristics.

Required sections — include all that apply:

**Summary** — One sentence: what the function does and why it exists.

**Algorithm** — Step-by-step logic, detailed enough to re-implement without reading the code.
```
Algorithm:
1. Maintain a rolling window of the last N GPS samples.
2. Compute 2D displacement between oldest and newest sample.
3. Estimate horizontal speed = distance / elapsed_time.
4. Apply EMA (α = 0.3) to reduce GPS jitter.
```

**Parameters** — Every numeric parameter with units and valid range.
```
- speedThreshold: Horizontal speed in m/s. Values below 0.5 are treated as stationary.
```

**Returns** — Explain semantics, not just type.
```
- Returns: Smoothed horizontal speed in m/s, averaged over the last 5 seconds.
```

**Assumptions** — What the function takes for granted.
```
Assumptions:
* GPS samples arrive approximately once per second.
* Horizontal accuracy is typically < 15 m under normal conditions.
```

**Thresholds** — Every magic number with its meaning and justification.
```
Thresholds:
* walkSpeedMax = 2.2 m/s — Above this, motion is unlikely to be human walking.
* liftSpeedMin = 2.0 m/s — Below this, chairlift motion is indistinguishable from walking.
```

**Edge Cases** — Behavior at boundaries and invalid inputs.
```
Edge Cases:
* Fewer than 2 samples in window → speed reported as 0.
* Identical timestamps → speed reported as 0 (avoid division by zero).
```

**State Decision Logic** (for classifiers) — The full decision tree.
```
State Decision Logic:
  idle:      speed < 0.5 m/s
  walk:      0.5 ≤ speed < 2.2 m/s, altitude change negligible
  chairlift: speed 2–7 m/s, altitude increasing over time
  skiing:    speed > 3 m/s, altitude decreasing
```

---

### Universal Rules

1. **Explain why, not what** — Code shows what happens. Docstrings explain why it works that way.
2. **Never restate the function name** — `/// Calculates speed.` on `func calculateSpeed()` adds nothing.
3. **Units are mandatory** — Every numeric value must state its unit (m/s, km/h, seconds, meters, degrees).
4. **Document side effects** — If the function mutates state, writes to disk, or sends a message, say so.
5. **No empty docstrings** — A bare `///` with no content is worse than no docstring.

---

### Forbidden

- Docstrings that only restate the function name
- Thresholds in code with no explanation of their meaning or justification
- Numeric parameters without units
- Describing implementation steps instead of behavior (`/// loops through samples`)
- Omitting edge cases for functions that handle optional or boundary inputs

---

## Output

### Write Mode

Return the updated file with docstrings added in-place. Do not change any logic.

### Review Report

```
## Docstring Review: <FileName>

### Violations
| # | Symbol | Issue | Required Fix |
|---|--------|-------|--------------|
| 1 | ...    | ...   | ...          |

### Missing Docstrings
- <symbol name> — <why it needs one>

### Compliant
- <symbols that are correctly documented>
```
