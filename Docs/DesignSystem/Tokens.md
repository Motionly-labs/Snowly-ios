# Design System Tokens

All token files in `Snowly/DesignSystem/`, with values and usage notes.

---

## Color Tokens (`ColorTokens.swift`)

### Brand Colors

| Token | Hex | Use |
|---|---|---|
| `brandIceBlue` | `#1E88E5` | Skiing segments, primary interactive elements, stats for current run |
| `brandWarmAmber` | `#F88800` | Start button, lift segments, active state highlight |
| `brandWarmOrange` | `#F88000` | Brand gradient second stop (nearly identical to Amber) |
| `brandRed` | `#D82000` | Danger actions, stop button, sensor error state |
| `brandGold` | `#FFD36A` | Personal best highlights, progress arc, achievement badges |

### Text

| Token | Value | Use |
|---|---|---|
| `textOnBrand` | `Color.black.opacity(0.86)` | Text rendered on brand-color backgrounds |

### Semantic

| Token | Base Color | Use |
|---|---|---|
| `success` | `Color.green` | Confirmed actions, healthy sensor readings |
| `warning` | `Color.orange` | Degraded state, low battery |
| `error` | `Color.red` | Failure, validation errors |
| `info` | `Color.blue` | Informational notices |

### Sensor Status

| Token | Value | Use |
|---|---|---|
| `sensorGreen` | `#39D353` | GPS / motion sensor active |
| `sensorRed` | `brandRed` | Sensor unavailable or error |

### Trail Difficulty

| Token | Use |
|---|---|
| `trailGreen` | Green (easy) piste label |
| `trailBlue` | Blue (intermediate) piste label |
| `trailRed` | Red (advanced) piste label |
| `trailBlack` | Black (expert) piste label |
| `trailOrange` | Orange (varies by region) |
| `trailYellow` | Yellow (beginner or ski cross) |
| `trailUnknown` | `Color.white.opacity(0.35)` — trail with no known difficulty |

### Surface

| Token | Value | Use |
|---|---|---|
| `surfaceOverlay` | `Color.white.opacity(0.12)` | Card fill on dark background |
| `surfaceDivider` | `Color.white.opacity(0.15)` | Divider lines on dark background |

### Gradients

| Token | Colors | Use |
|---|---|---|
| `brandGradient` | Amber → WarmOrange | Start button fill, CTA backgrounds |
| `progressArcGradient` | Gold → Amber → WarmOrange → Red | Progress arc fill in session summary |

---

## Typography (`Typography.swift`)

### Display

| Token | Spec | Use |
|---|---|---|
| `splashTitle` | System 48 Black | App name on splash screen |
| `splashSubtitle` | System 18 Light | Tagline on splash screen |
| `splashIcon` | System 64 Thin | Logo icon on splash |
| `onboardingHeroIcon` | System 80 Thin | Large icon on onboarding steps |
| `onboardingIcon` | System 60 Regular | Standard onboarding icon |
| `musicIcon` | System 48 | Music player icon |

### Metric (hero numbers)

| Token | Spec | Use |
|---|---|---|
| `metricHero` | System 72 Bold Rounded | Top-line speed display |
| `temperatureHero` | System 76 Semibold Rounded | Weather temperature |
| `metricLarge` | System 48 Bold Rounded | Secondary large metric |
| `metricMedium` | System 44 Bold Rounded | Mid-size metric value |
| `metricSmall` | System 36 Bold Rounded | Smaller metric in compact layouts |
| `speedDisplay` | System 44 Medium | Alternate speed display style |
| `statValue` | System 24 Bold Rounded | Stat grid cell value |

### Heading

| Token | Spec | Use |
|---|---|---|
| `onboardingTitle` | Title Bold | Onboarding step title |
| `primaryTitle` | Title2 Semibold | Screen titles |
| `headingLarge` | System 28 Semibold | Section headings |
| `headingMedium` | System 22 Semibold | Card headings |
| `settingsIcon` | System 22 | Settings row icon |

### Button

| Token | Spec | Use |
|---|---|---|
| `buttonHero` | System 26 Bold Rounded | Hero button label (Start) |
| `buttonResume` | System 22 Bold Rounded | Resume button label |
| `buttonLabel` | Title3 Semibold | Standard button label |
| `buttonStrong` | System 18 Bold | Strong action button |

### Body

| Token | Spec | Use |
|---|---|---|
| `bodyLabel` | System 18 Medium | Primary body text |
| `bodyMedium` | System 17 Medium | Secondary body text |
| `captionMedium` | System 16 Medium | Caption text |

### Small

| Token | Spec | Use |
|---|---|---|
| `smallSemibold` | System 14 Semibold | Small labels |
| `smallBold` | System 13 Bold | Compact bold labels |
| `smallLabel` | System 13 Semibold | Compact labeled values |
| `badgeLabel` | System 12 Bold | Badge counts |
| `iconBold` | System 16 Bold | Icon-adjacent labels |

### System Weighted

| Token | Spec | Use |
|---|---|---|
| `subheadlineMedium` | Subheadline Medium | Subheadline with medium weight |
| `subheadlineSemibold` | Subheadline Semibold | Prominent subheadline |
| `captionSemibold` | Caption Semibold | Compact caption |
| `caption2Semibold` | Caption2 Semibold | Smallest caption |

---

## Spacing (`Spacing.swift`)

4-point grid. All values are `CGFloat`.

| Token | Value (pt) | Typical Use |
|---|---|---|
| `xxs` | 2 | Tight inline gaps (icon/label) |
| `xs` | 4 | Small gaps within a component |
| `gap` | 6 | Between related elements in a row |
| `sm` | 8 | Padding inside compact cards |
| `gutter` | 10 | List row horizontal inset |
| `md` | 12 | Standard intra-component padding |
| `lg` | 16 | Primary layout spacing |
| `card` | 18 | Card internal padding |
| `content` | 20 | Content area padding |
| `xl` | 24 | Section internal spacing |
| `xxl` | 32 | Between major layout sections |
| `xxxl` | 40 | Large section breathing room |
| `section` | 48 | Between distinct page sections |
| `heroButton` | 188 | Diameter of the circular Start / Resume button |

---

## Corner Radius (`CornerRadius.swift`)

| Token | Value (pt) | Use |
|---|---|---|
| `small` | 8 | Small chips, compact tags |
| `medium` | 12 | Standard cards |
| `large` | 16 | Large cards, panels |
| `pill` | 18 | Pill-shaped buttons and tags (tighter capsule aesthetic) |
| `xLarge` | 24 | Modal sheets, hero cards |

---

## Animation Tokens (`AnimationTokens.swift`)

### Durations

| Token | Value (s) | Use |
|---|---|---|
| `quick` | 0.15 | Micro-interactions (state toggles) |
| `fast` | 0.20 | Quick transitions |
| `standard` | 0.25 | Standard UI transitions |
| `moderate` | 0.30 | Moderate pace transitions |
| `slow` | 0.45 | Large layout changes |

### Preset Animations

| Token | Curve | Use |
|---|---|---|
| `quickEaseOut` | `.easeOut(0.15)` | Dismissals, quick fades |
| `quickEaseInOut` | `.easeInOut(0.15)` | Compact toggle animations |
| `fastEaseInOut` | `.easeInOut(0.20)` | Fast transitions |
| `standardEaseInOut` | `.easeInOut(0.25)` | Default for most transitions |
| `moderateEaseInOut` | `.easeInOut(0.30)` | Moderate transitions |
| `slowEaseInOut` | `.easeInOut(0.45)` | Large content transitions |
| `standardEaseIn` | `.easeIn(0.25)` | Elements entering from off-screen |
| `gentleSpring` | `.spring(response: 0.35, dampingFraction: 0.7)` | Draggable elements, bouncy entrances |
| `smoothEntranceFast` | `timingCurve(0.22, 1, 0.36, 1, duration: 0.8)` | Cards sliding in |
| `smoothEntranceMedium` | `timingCurve(0.22, 1, 0.36, 1, duration: 1.2)` | Slower hero entrances |
| `smoothEntrance` | `timingCurve(0.22, 1, 0.36, 1, duration: 1.5)` | Dramatic entrances |

---

## Run Color Palette (`RunColorPalette.swift`)

Maps run index → color for consistent coloring across maps, charts, and share cards.

**Sequential stops (warm → cool):**

| Position | Color |
|---|---|
| 0.00 | `brandRed` |
| 0.24 | `brandWarmAmber` |
| 0.50 | RGB (0.22, 0.83, 0.52) — lime green |
| 0.76 | `brandIceBlue` |
| 1.00 | RGB (0.56, 0.43, 0.96) — violet |

**API:**

```swift
// Base color for a run at a given position in the session
RunColorPalette.color(forRunIndex: 3, totalRuns: 10)

// Gradient pair (lighter top, darker bottom) for chart fills
let (top, bottom) = RunColorPalette.chartGradientColors(forRunIndex: 3, totalRuns: 10)
```

Colors are linearly interpolated between the nearest stops. The first run (index 0) is always red; the last run is always violet.
