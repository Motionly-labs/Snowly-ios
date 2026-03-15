---
name: snowly-ios-design
description: Use when generating or reviewing UI code for any Snowly target — iOS app, watchOS app, or widget extension. Enforces token-driven styling, Apple-native visual language, and brand consistency across all three targets.
user-invocable: true
---

# Snowly Design System

## When Invoked

Operates across three targets. First, identify the target from the file path or user description:

| Target | Path Prefix | Token Source |
|--------|-------------|--------------|
| **iOS** | `Snowly/` | `Snowly/DesignSystem/` |
| **watchOS** | `SnowlyWatch/` | `SnowlyWatch/DesignSystem/` |
| **Widget Extension** | `SnowlyWidgetExtension/` | `SnowlyWidgetExtension/LiveActivityTokens.swift` |

If the target is ambiguous, ask before proceeding.

Then operate in one of two modes:

- **Generate mode** (default): Produce new UI code that is fully token-compliant. Read the relevant token files for the target first.
- **Review mode**: If the user says "review" or "audit", check existing UI code for violations and output a findings report.

If no target file or feature is specified, ask: _"Which screen or component should I generate or review?"_

---

## Execution Steps

### Generate Mode

1. Identify the target (iOS / watchOS / widget).
2. Read the token files for that target (see **Token Files** below) before writing any UI.
3. Write all visual values using tokens — never hardcode colors, fonts, spacing, corner radii, opacity, shadows, or animation values.
4. If a needed token doesn't exist, add it to the appropriate token file for that target first, then reference it.
5. Follow the Visual Direction guidelines below.

### Review Mode

1. Identify the target from the file path.
2. Read the target file(s).
3. Flag violations against the rules for that target.
4. Output a findings report (see **Output**).

---

## Domain Reference

### iOS Token Files (`Snowly/DesignSystem/`)

| File | Contents |
|------|----------|
| `ColorTokens.swift` | Brand palette, semantic colors, gradients. Uses custom `Color(hex:)` initializer. |
| `Spacing.swift` | Padding and layout spacing values |
| `CornerRadius.swift` | Corner radius scale |
| `Typography.swift` | Font styles and weights |
| `ShadowTokens.swift` | Shadow definitions |
| `AnimationTokens.swift` | Animation durations and presets |
| `MaterialTokens.swift` | Background material definitions |
| `Opacity.swift` | Opacity scale |
| `ChartTokens.swift` | Chart-specific colors and dimensions |
| `RunColorPalette.swift` | Per-run color assignments |

### watchOS Token Files (`SnowlyWatch/DesignSystem/`)

Each watch token file is independent — do not reference iOS `DesignSystem/` from the watch target.

| File | Contents |
|------|----------|
| `WatchColorTokens.swift` | Brand colors, gradients, semantic aliases (`sportAccent`, `completedAccent`, `connectedAccent`) |
| `WatchSpacing.swift` | Spacing grid (`xs`–`xl`) + named button geometry constants |
| `WatchOpacity.swift` | Surface and overlay opacity values |
| `WatchCornerRadius.swift` | Corner radius scale |
| `WatchTypography.swift` | Display font styles (timer, control icon, stat icon) |
| `WatchAnimationTokens.swift` | Animation presets (e.g., `holdRelease`) |

### Widget Extension Token File (`SnowlyWidgetExtension/`)

The widget extension is a separate target that cannot import iOS or watchOS DesignSystem code. All tokens live in a single file with its own `Color(hex:)` helper.

| File | Contents |
|------|----------|
| `LiveActivityTokens.swift` | Colors, spacing, padding, chip/pill geometry, typography, scale factors |

When a new widget token is needed, add it to `LiveActivityTokens.swift` directly — do not create additional files.

---

### Brand Palette

All three targets share the same accent hierarchy:

| Role | Color | Hex | Token |
|------|-------|-----|-------|
| **Primary accent** | Ice blue | `#1E88E5` | iOS: `ColorTokens.primaryAccent` / Watch: `WatchColorTokens.primaryAccent` |
| **Secondary accent** | Warm orange | `#F88000` | iOS: `ColorTokens.secondaryAccent` / Watch: `WatchColorTokens.secondaryAccent` |
| **Sport / live tracking** | Ice blue (= primary) | `#1E88E5` | iOS: `ColorTokens.sportAccent` / Watch: `WatchColorTokens.sportAccent` |
| **Completed session** | Ice blue (= primary) | `#1E88E5` | iOS: `ColorTokens.completedAccent` / Watch: `WatchColorTokens.completedAccent` |
| **Destructive** | Red | `#D82000` | `brandRed` |
| **Highlights** | Gold | `#FFD36A` | `brandGold` |

#### iOS
- `primaryAccent = brandIceBlue` — navigation, selected states, key metrics, primary CTAs
- `secondaryAccent = brandWarmOrange` — secondary actions, supporting info
- `brandGradient` = light blue → ice blue; `progressArcGradient` = multi-stop blue arc
- Never create inline gradients

#### watchOS
- `primaryAccent = brandIceBlue` — mirrors iOS exactly
- `sportAccent = primaryAccent` — active tracking tint (ice blue)
- `completedAccent = primaryAccent` — summary/completed state (ice blue)
- `secondaryAccent = brandWarmOrange` — offline/independent mode indicator
- `connectedAccent` = system green — paired iPhone reachable
- `brandGradient` = light blue → ice blue (matches iOS)

#### Widget Extension
- `pauseAccent = brandIceBlue (#1E88E5)` — shown on pause button when session is **active** (matches iOS `sportAccent`)
- `playAccent` = system green — shown on play button when session is **paused** (resume action)
- Never use `.orange`, `.blue`, `.green`, or any hardcoded `Color` in widget views

---

### Token Usage Examples

```swift
// iOS — correct
.padding(Spacing.lg)
.foregroundStyle(ColorTokens.primaryAccent)
.clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
.font(Typography.primaryTitle)
.foregroundStyle(.white.opacity(Opacity.secondary))

// watchOS — correct (value-first metric row, no card chrome)
Text(value)
    .font(WatchTypography.metricValue)
    .foregroundStyle(.white)
HStack { Image(systemName: icon).font(WatchTypography.statIcon); Text(label).font(.caption) }
    .foregroundStyle(.secondary)
Divider()  // Separate rows with Divider(), not cards

// watchOS — correct (native button)
Button { … } label: { Image(systemName: "pause.fill").font(WatchTypography.controlIcon) }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.circle)
    .tint(WatchColorTokens.sportAccent)

// watchOS — correct (timer, animation)
Text(elapsed).font(WatchTypography.timerLarge).foregroundStyle(WatchColorTokens.brandGradient)
withAnimation(WatchAnimationTokens.holdRelease) { … }

// Widget Extension — correct
.padding(.horizontal, LiveActivityTokens.chipPaddingH)
.padding(.vertical, LiveActivityTokens.chipPaddingV)
.foregroundStyle(state.isPaused ? LiveActivityTokens.playAccent : LiveActivityTokens.pauseAccent)
.font(LiveActivityTokens.speedFont)
.background(.ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: LiveActivityTokens.chipCornerRadius))

// Wrong — any target
.padding(16)
.background(Color(hex: "F88800"))
.foregroundStyle(.orange)
.clipShape(RoundedRectangle(cornerRadius: 10))
.opacity(0.08)

// Wrong — watchOS (iOS pattern imported to watch)
.background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))  // card chrome — not native watchOS
ZStack { Circle().fill(color.opacity(0.16)); Image(systemName: icon) }            // manual circle — use .borderedProminent
.background(Color.white.opacity(0.12), in: Capsule())                             // chip pill — use plain HStack
```

---

### Rules

1. **Token-only styling** — No hardcoded colors, font sizes, spacing, padding, corner radii, opacity, shadows, or animation values in any UI file across all three targets.
2. **Use the right token set for the target** — Never reference iOS `DesignSystem/` tokens from `SnowlyWatch/` or `SnowlyWidgetExtension/`. Each target is sandboxed to its own tokens.
3. **Single source of truth per target** — If a needed token doesn't exist, add it to the appropriate file for that target first, then reference it. Do not create new token files unless the category is entirely new.
4. **Read before writing** — Always read the token files for the target before generating UI to avoid duplicates or contradictions.
5. **Refactor first** — When extending UI that has hardcoded values, extract those values into tokens before adding new code.
6. **If a design conflicts with the token system**, produce a token-aligned alternative and explain why.

---

### Visual Direction

Each target follows its own platform's native design language. **Do not port iOS visual patterns to watchOS or widget extension.**

#### iOS
- Clean, modern — uses `snowlyGlass()` (wraps `.glassEffect()`, iOS 26) for card surfaces
- `primaryAccent` (ice blue) for key metrics, CTAs, navigation; `secondaryAccent` (warm orange) for supporting info
- Typography-led; avoid cluttered stat grids; restrained accent use
- Subtle motion via `AnimationTokens`; no bouncy or playful animations unless explicitly requested

#### watchOS — Follow watchOS HIG
- **Black canvas** — content is placed directly on black; no card chrome or filled `RoundedRectangle` backgrounds on content rows
- **Whitespace + `Divider()`** to separate rows — never use card containers to group stats
- **Value-first metrics** — large value at top (e.g. `WatchTypography.metricValue`), small label/icon below; matches native Workout app metric tiles
- **Native buttons** — use `.buttonStyle(.borderedProminent)` + `.buttonBorderShape(.circle)` + `.tint(WatchColorTokens.sportAccent)` for circular control buttons; never build manual `ZStack { Circle() + Image }` button chrome
- **No chip backgrounds** — secondary info (e.g. heart rate) is plain text, not wrapped in a `Capsule()` pill
- Tighter spacing grid: prefer `WatchSpacing.sm`/`md`; use `WatchSpacing.lg`/`xl` only for major section breaks
- Timer display: `WatchTypography.timerLarge` (active) / `timerAlwaysOn` (AOD); gradient fill via `WatchColorTokens.brandGradient`
- Complications: `.widgetAccentable()` for tintable elements; icon + 1–2 values maximum
- `.glassEffect()` is iOS 26 only — **never use it on watchOS**

#### Widget Extension — Follow Live Activity conventions
- Lock-screen expanded views: high information density is acceptable
- Chip/pill surfaces: `.ultraThinMaterial` background only — never opaque fills
- Dynamic Island compact: single icon + value; no labels
- All padding, color, font, and corner radius values from `LiveActivityTokens`
- Never use `.orange`, `.blue`, `.green`, or any hardcoded `Color`

---

### Component Guidelines

| Component | Target | Rule |
|-----------|--------|------|
| Primary buttons | iOS | `primaryAccent` (ice blue); minimal chrome |
| Circular control buttons | watchOS | `.buttonStyle(.borderedProminent)` + `.buttonBorderShape(.circle)` + `.tint(WatchColorTokens.sportAccent)` — never manual `ZStack { Circle() }` |
| Hold buttons | watchOS | `HoldProgressCircleButton`; diameter/iconSize from `WatchSpacing` constants |
| Stat rows | watchOS | Plain `HStack` on black canvas; `Divider()` between rows; no `RoundedRectangle` backgrounds |
| Metric tile | watchOS | Value on top (`WatchTypography.metricValue`), icon+label below (`.secondary`); no background |
| Secondary inline info | watchOS | Plain `HStack`; `.secondary` foreground; no `Capsule` wrapper |
| Dashboards | iOS | Emphasize a few key metrics; avoid cluttered stat grids |
| Stat chips | Widget | `LiveActivityTokens` padding + corner radius; `.ultraThinMaterial` background |
| Metric pills | Widget | `Capsule()` shape; `LiveActivityTokens` padding; `.ultraThinMaterial` background |
| Complications | watchOS | Minimal — icon + 1-2 values; `.widgetAccentable()` for primary elements |

---

## Output

### Generate Mode

Return SwiftUI code with every visual value sourced from a token. Label any new tokens added to a `DesignSystem/` file (or `LiveActivityTokens.swift` for widgets), noting the file and the value.

### Review Report

```
## Design Review: <FileName> [iOS / watchOS / Widget]

### Violations
| # | File | Line | Rule | Hardcoded Value | Correct Token |
|---|------|------|------|-----------------|---------------|
| 1 | ...  | ...  | ...  | ...             | ...           |

### Missing Tokens
- <description of value that needs a new token> → add to <TokenFile.swift>

### Compliant
- <what is correctly token-driven>
```
