---
name: snowly-localization
description: Use when writing, reviewing, or refactoring any UI text in the Snowly app (iOS or watchOS). Enforces a clean localization system with strict separation between code keys and user-facing strings.
user-invocable: true
---

# Snowly Localization

## When Invoked

Operate in one of three modes:

- **Write mode** (default): Add localization keys and translations for new UI text. Read the relevant `.xcstrings` file first to avoid duplicates.
- **Review mode**: If the user says "review" or "audit", check existing UI code and flag violations.
- **Migrate mode**: If the user says "migrate" or "refactor", replace hardcoded strings with proper keys throughout the specified file(s).

If no target is specified, ask: _"Which file or feature should I localize, review, or migrate?"_

---

## Execution Steps

### Write Mode

1. Read the relevant `.xcstrings` file (`Snowly/Resources/Localizable.xcstrings` for iOS, `SnowlyWatch/Resources/Localizable.xcstrings` for watchOS).
2. Check if a suitable key already exists. Reuse it if so.
3. If not, create a new key following the **Key Naming Convention** below.
4. Add translations for all supported languages (`en`, `zh-Hans`).
5. Replace any hardcoded text in code with the key.
6. Output: updated `.xcstrings` entries + updated Swift code.

### Review Mode

1. Read the target file(s).
2. Flag each violation from the **Review Checklist**.
3. Output a findings report (see **Output**).

### Migrate Mode

1. Read the target file(s) and the relevant `.xcstrings` file.
2. For each hardcoded string found: check if a key already exists, reuse or create, add translations, replace in code.
3. Remove any orphaned old keys from the catalog.
4. Output: updated `.xcstrings` entries + updated Swift code.

---

## Domain Reference

### String Catalog Files

| Target | File |
|--------|------|
| iOS | `Snowly/Resources/Localizable.xcstrings` |
| watchOS | `SnowlyWatch/Resources/Localizable.xcstrings` |

Supported languages: `en` (source), `zh-Hans` (Simplified Chinese).

---

### Three Fundamental Principles

**1. Code keys must use professional English**

Keys must be:
- Formal, precise, and semantic (represent meaning, not literal phrase)
- Stable across versions
- Dot-separated: `<domain>.<element>[.<qualifier>]`

```
// Good keys
record.start_button
session.summary_title
settings.units.metric
activity.no_sessions_placeholder

// Bad keys — never use
go_ski          // slang
lets_gooo       // casual
start_now       // ambiguous
Start Recording // literal text as key
开始滑雪        // non-English key
```

**2. User-facing text can be expressive**

The key stays formal and stable. The localization evolves freely.

| Key | en | zh-Hans |
|-----|----|---------|
| `record.start_button` | Start Recording | 开始滑雪 |
| `session.completed_title` | Nice run! | 滑得不错！ |
| `home.greeting` | Ready to ride? | 准备开滑？ |
| `session.empty_state` | No sessions yet | 还没有记录哦 |

**3. Code must never contain hardcoded UI text**

```swift
// Forbidden
Text("Start")
Button("Stop Recording")

// Required
Text("record.start_button")
Button("record.stop_button") {}
```

SwiftUI `Text(_:)` with a `String` literal looks up the key in `Localizable.xcstrings` automatically when the key exists.

---

### Key Naming Convention

Format: `<domain>.<element>[.<qualifier>]`

**Domains:**

| Domain | Scope |
|--------|-------|
| `record` | Active tracking / recording session |
| `session` | Session summary, history, detail |
| `home` | Home tab |
| `gear` | Gear tab |
| `activity` | Activity tab |
| `profile` | User profile |
| `settings` | Settings screens |
| `onboarding` | Onboarding flow |
| `share` | Share card |
| `map` | Map views |
| `weather` | Weather display |
| `common` | Reusable across domains (`common.cancel`, `common.done`) |
| `accessibility` | VoiceOver labels and hints |
| `error` | Error messages |
| `alert` | Alert titles and messages |
| `watch` | watchOS-specific strings |

**Element suffixes:**

| Suffix | Usage |
|--------|-------|
| `_title` | Screen or section titles |
| `_subtitle` | Secondary titles |
| `_label` | Static labels |
| `_button` | Button text |
| `_placeholder` | Placeholder / empty state |
| `_hint` | Accessibility hints or helper text |
| `_message` | Alert or notification body |
| `_description` | Longer descriptive text |
| `_action` | Action sheet or menu items |
| `_format` | Strings with format specifiers |
| `_unit` | Unit labels (km, mph, etc.) |

---

### String Catalog Entry Format

```json
"record.start_button" : {
  "localizations" : {
    "en" : {
      "stringUnit" : { "state" : "translated", "value" : "Start Recording" }
    },
    "zh-Hans" : {
      "stringUnit" : { "state" : "translated", "value" : "开始滑雪" }
    }
  }
}
```

- `state: "translated"` — finalized strings
- `state: "new"` — auto-extracted, not yet reviewed
- Always include all supported languages when adding a new key

### Format Strings

Use positional specifiers for interpolation:

```json
"session.run_count_format" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "%lld runs" } },
    "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "%lld 趟" } }
  }
}
```

### Plural Support

```json
"session.run_count" : {
  "localizations" : {
    "en" : {
      "variations" : {
        "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld run" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld runs" } }
        }
      }
    }
  }
}
```

---

### Review Checklist

Flag the following violations:

1. **Hardcoded UI text** — Any `Text("literal")`, `Button("literal")`, `Label("literal", ...)` where the string is not a localization key
2. **Casual or non-English keys** — Slang, abbreviations, or non-English text as keys
3. **Missing domain prefix** — Keys without a clear `domain.` namespace
4. **Duplicate keys** — Same semantic meaning with different keys
5. **Missing translations** — Key present in one language but missing in others
6. **SF Symbol names are not localized** — `systemImage:` parameters are fine as literals

---

## Output

### Write / Migrate Mode

Output two blocks:

1. **`.xcstrings` additions** — JSON entries to add to the catalog
2. **Swift code changes** — Updated view code with hardcoded strings replaced by keys

### Review Report

```
## Localization Review: <FileName>

### Violations
| # | File | Line | Violation | Fix |
|---|------|------|-----------|-----|
| 1 | ...  | ...  | Hardcoded text: "Start" | Use key: record.start_button |

### Missing Keys (need to be added to .xcstrings)
- <key> — <en value> — <zh-Hans value>

### Compliant
- <what is correctly localized>
```
