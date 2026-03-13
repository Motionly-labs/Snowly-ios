---
name: snowly-ios-design
description: Use when generating or reviewing UI code for the Snowly iOS app. Enforces token-driven styling, Apple-native visual language, and brand consistency. Applies to iOS target only — watchOS has its own tokens in SnowlyWatch/DesignSystem/.
user-invocable: true
---

# Snowly iOS Design System

## When Invoked

Operate in one of two modes:

- **Generate mode** (default): Produce new UI code that is fully token-compliant. Before generating, read the relevant token files in `Snowly/DesignSystem/` to use existing values.
- **Review mode**: If the user says "review" or "audit", check existing UI code for violations and output a findings report.

If no target is specified, ask: _"Which screen or component should I generate or review?"_

---

## Execution Steps

### Generate Mode

1. Read the relevant token files (`ColorTokens.swift`, `Spacing.swift`, `CornerRadius.swift`, `Typography.swift`, `ChartTokens.swift`, `RunColorPalette.swift`) before writing any UI.
2. Write all visual values using tokens — never hardcode colors, fonts, spacing, corner radii, opacity, shadows, or animation values.
3. If a needed token doesn't exist, add it to the appropriate `Snowly/DesignSystem/` file first, then reference it.
4. Follow the Visual Direction guidelines below.

### Review Mode

1. Read the target file(s).
2. Flag violations against the rules below.
3. Output a findings report (see **Output**).

---

## Domain Reference

### Token Files

All design tokens in `Snowly/DesignSystem/` as Swift enums:

| File | Contents |
|------|----------|
| `ColorTokens.swift` | Brand palette, semantic colors, gradients. Uses custom `Color(hex:)` initializer. |
| `Spacing.swift` | Padding and layout spacing values |
| `CornerRadius.swift` | Corner radius scale |
| `Typography.swift` | Font styles and weights |
| `ChartTokens.swift` | Chart-specific colors and dimensions |
| `RunColorPalette.swift` | Per-run color assignments |

### Brand Palette

- Primary: **warm amber/orange** — `ColorTokens.brandWarmAmber` (not blue)
- Destructive/emphasis: `brandRed`
- Highlights: `brandGold`
- Gradients: use defined gradients (`brandGradient`, `progressArcGradient`) — do not create new gradients inline

### Token Usage

```swift
// Correct — tokens
.padding(Spacing.lg)
.background(ColorTokens.brandWarmAmber)
.clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
.font(Typography.primaryTitle)

// Wrong — hardcoded literals
.padding(16)
.background(Color(hex: "F88800"))
.clipShape(RoundedRectangle(cornerRadius: 12))
```

### Rules

1. **Token-only styling** — No hardcoded colors, font sizes, spacing, padding, corner radii, opacity, shadows, or animation values in UI code.
2. **Single source of truth** — If a needed token doesn't exist, add it to `Snowly/DesignSystem/` first, then reference it. Do not create new token files for a single value; add to the appropriate existing file.
3. **Read before writing** — Always read token files before generating UI to avoid duplicates or contradictions.
4. **Refactor first** — When extending UI that has hardcoded values, extract those values into tokens before adding new code.
5. **If a design conflicts with the token system**, produce a token-aligned alternative and explain why.

### Visual Direction

Apple-native, typography-led, minimal. Core principles:

- Prefer **whitespace** over containers to separate content
- **Restrained color** — accent is used sparingly for hierarchy, not decoration
- **Subtle motion** — no bouncy or playful animations unless explicitly requested
- Avoid Material design, web-dashboard aesthetics, excessive cards, or gratuitous gradients

### Component Guidelines

| Component | Rule |
|-----------|------|
| Buttons | Brand amber for primary; clear primary/secondary hierarchy; minimal chrome |
| Cards | Use only when containment genuinely helps — prefer spacing to separate content |
| Dashboards | Emphasize a few key metrics; avoid cluttered stat grids |

---

## Output

### Generate Mode

Return SwiftUI code with every visual value sourced from a token. Label any new tokens added to `DesignSystem/` files.

### Review Report

```
## Design Review: <FileName>

### Violations
| # | File | Line | Rule | Hardcoded Value | Correct Token |
|---|------|------|------|-----------------|---------------|
| 1 | ...  | ...  | ...  | ...             | ...           |

### Missing Tokens
- <description of value that needs a new token> → add to <TokenFile.swift>

### Compliant
- <what is correctly token-driven>
```
