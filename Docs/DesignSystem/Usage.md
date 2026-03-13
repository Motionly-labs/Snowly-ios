# Design System Usage

How to apply design tokens correctly in Snowly iOS views.

---

## Dark Background Convention

All Snowly tracking and home screens use a pure black (`Color.black`) or very dark background. This is intentional: metrics appear brighter and the app reads well in bright sunlight on snow.

```swift
// Correct
var body: some View {
    ZStack {
        Color.black.ignoresSafeArea()
        content
    }
}

// Wrong — light backgrounds make metrics hard to read outdoors
var body: some View {
    content
        .background(Color.white)
}
```

Surface overlays and dividers use `ColorTokens.surfaceOverlay` and `ColorTokens.surfaceDivider` (white at low opacity) rather than gray swatches, so they work on any dark background.

---

## Using Color Tokens

Always reference `ColorTokens` constants. Never use inline hex strings or `Color(hex:)` calls in view code.

```swift
// Correct
Text("12.4 km/h")
    .foregroundStyle(ColorTokens.brandIceBlue)

// Wrong
Text("12.4 km/h")
    .foregroundStyle(Color(hex: "1E88E5"))
```

For activity-colored elements, use the activity type to select the token:

```swift
func color(for activity: RunActivityType) -> Color {
    switch activity {
    case .skiing: return ColorTokens.brandIceBlue
    case .lift:   return ColorTokens.brandWarmAmber
    case .walk:   return ColorTokens.brandGold
    case .idle:   return ColorTokens.surfaceOverlay
    }
}
```

---

## Metric Display Pattern

Hero metric displays follow a consistent layout: large number + small unit label below or beside it.

```swift
VStack(alignment: .leading, spacing: Spacing.xxs) {
    Text(formattedSpeed)
        .font(Typography.metricHero)
        .foregroundStyle(.white)
    Text("km/h")
        .font(Typography.captionSemibold)
        .foregroundStyle(.white.opacity(0.6))
}
```

Use `Typography.metricHero` (72 pt Bold Rounded) for the primary value shown during active tracking. Use `Typography.metricLarge` or `Typography.metricMedium` for secondary values in the stat grid.

---

## Spacing and Layout

Use `Spacing` constants for all padding and spacing. Do not use magic numbers.

```swift
// Correct
.padding(.horizontal, Spacing.lg)
.padding(.vertical, Spacing.md)

// Wrong
.padding(.horizontal, 16)
.padding(.vertical, 12)
```

Standard card pattern:

```swift
VStack(alignment: .leading, spacing: Spacing.sm) {
    // card content
}
.padding(Spacing.card)
.background(ColorTokens.surfaceOverlay)
.clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
```

---

## Run Colors

Use `RunColorPalette.color(forRunIndex:totalRuns:)` when rendering a list of runs in consistent colors. This ensures the first run is always warm-toned and the last is cool-toned, matching the map and chart views.

```swift
ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
    RunBar(run: run)
        .foregroundStyle(
            RunColorPalette.color(forRunIndex: index, totalRuns: runs.count)
        )
}
```

For chart fill gradients:

```swift
let (top, bottom) = RunColorPalette.chartGradientColors(forRunIndex: index, totalRuns: runs.count)
LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
```

---

## Animation

Use `AnimationTokens` presets for all view transitions. Match the animation character to the interaction:

```swift
// Standard transition (most common)
withAnimation(AnimationTokens.standardEaseInOut) {
    isExpanded.toggle()
}

// Bouncy entrance for draggable cards
.animation(AnimationTokens.gentleSpring, value: isEditing)

// Dramatic hero entrance (session summary card)
.animation(AnimationTokens.smoothEntranceFast, value: appeared)
```

---

## Previews

All previews use in-memory stores and mock services. Never reference production data or real service instances in preview code.

```swift
#Preview {
    ActiveTrackingView()
        .environment(SessionTrackingService.preview)
        .modelContainer(for: SkiSession.self, inMemory: true)
}
```

For design review, previews should exercise both the light-content-on-dark-background convention and realistic metric values (speeds in the 5–25 km/h range, vertical drops in the 50–300 m range).
