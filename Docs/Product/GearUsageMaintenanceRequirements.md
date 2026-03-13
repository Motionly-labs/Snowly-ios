# Gear Locker + Checklist Requirements

Status: Current product direction

Last updated: March 12, 2026.

Owner: Product

Canonical terms for this document follow [Glossary](../Reference/Glossary.md). Use `gear`, `locker`, `checklist`, and `reminder schedule`.

---

## Product Thesis

Snowly Gear should work like this:

1. The user creates `gear` in their `locker`.
2. Each gear item can optionally have a `reminder schedule`.
3. The user pulls locker gear into one or more `checklists`.
4. The selected checklist powers the `visual checklist`.
5. Sessions attach a checklist snapshot so history still makes sense later.

This keeps the visual checklist, but stops treating it as the only Gear concept.

---

## Canonical Product Rules

### Rule 1

Gear is created in the locker first. Checklists do not own gear.

### Rule 2

A checklist is a selection of locker gear, not a separate type of item.

### Rule 3

Reminder schedules belong to gear, not to checklists or sessions.

### Rule 4

The visual checklist is generated from the currently selected checklist.

### Rule 5

Checklist checkmarks mean `packed`, not `used on mountain`.

### Rule 6

Product copy must not use `setup` or `asset`. Those are internal legacy names only.

---

## Core Entities

### Gear

A locker item the user wants to remember, prepare, or pack. Examples:

- skis
- boots
- helmet
- goggles
- gloves
- charger
- backpack

Each gear item supports:

- name
- category
- brand and model
- optional notes
- optional acquired date
- archive state
- optional reminder schedule
- membership in zero or more checklists

### Checklist

A named collection of locker gear. Examples:

- Japan trip
- Storm day
- Quick local night skiing

Each checklist supports:

- name
- optional notes
- active / inactive state
- a visual checklist generated from its selected gear
- recent session history

### Reminder Schedule

A local notification rule attached to one gear item. It supports:

- start date
- end date
- repeat interval value
- repeat interval unit
- time of day

Reminder schedules are device-local and schedule local notifications.

---

## Information Architecture

The Gear product should have four surfaces.

### 1. Gear Home

The default Gear tab. It is locker-first.

It should include:

- the selected checklist hero
- the visual checklist
- a reminder inbox
- gear currently in the selected checklist
- all locker gear
- recent sessions using the selected checklist

### 2. Checklist Detail

The canonical screen for one checklist.

It should allow:

- renaming the checklist
- editing notes
- making it the active checklist
- adding locker gear into the checklist
- removing gear from the checklist
- seeing recent sessions using the checklist

### 3. Gear Detail

The canonical screen for one locker gear item.

It should allow:

- editing gear identity fields
- editing reminder schedule
- assigning the gear to checklists
- seeing recent sessions through attached checklists

### 4. Session Gear Context

A lightweight session summary module showing:

- attached checklist name
- gear summary snapshot
- a quick way to change the attached checklist

---

## Gear Home Requirements

### Module A. Checklist Hero

The top card should show:

- selected checklist name
- checklist subtitle
- packed progress
- ski days using this checklist
- last used date

It should provide:

- switch checklist
- manage checklist
- reset checklist

### Module B. Visual Checklist

The visual checklist must remain a first-class part of the Gear experience.

It should provide:

- skier figure
- body-zone highlighting
- zone-by-zone packing state
- tap to mark gear as packed
- automatic movement to the next incomplete zone when useful

### Module C. Reminder Inbox

This is the first utility module under the visual checklist.

It should show:

- upcoming reminders across locker gear
- reminder cadence summary
- next reminder date
- tap through to gear detail

It should not show service or maintenance language.

### Module D. Checklist Gear

This shows the gear currently selected into the active checklist.

Each row or card should show:

- gear name
- category
- packed state inside the current checklist
- next reminder when available

### Module E. Locker Gear

This shows the full locker inventory.

It should make it obvious:

- what gear exists
- what checklists include each gear item
- whether the active checklist already includes it
- whether a reminder schedule exists

### Module F. Recent Sessions

This lists recent sessions using the active checklist.

Each row should show:

- date
- resort
- run count
- one summary stat
- gear snapshot summary when available

---

## Creation and Editing Flows

### Create Gear

The create-gear flow must support:

- gear name
- category
- optional brand and model
- optional acquired date
- optional notes
- optional reminder schedule
- zero or more checklist assignments

### Create Checklist

The create-checklist flow must support:

- checklist name
- optional notes
- active checklist toggle

The user can create an empty checklist first, then add locker gear afterward.

---

## Session Rules

- New sessions attach the active checklist by default.
- Users can change the attached checklist from session summary.
- Session gear history comes from the attached checklist snapshot, not from current checklist checkmarks.
- Editing a checklist later must not erase the historical meaning of old sessions.

---

## Non-Goals

These are outside the latest design:

- maintenance dashboard as the primary Gear concept
- service log UX as part of the main Gear flow
- setup / asset terminology in product copy
- shopping or ecommerce
- AI-generated gear advice
- auto-inferred usage from packing checkmarks

---

## Internal Mapping Notes

The current SwiftData model names remain:

- `GearAsset` for product `gear`
- `GearSetup` for product `checklist`

This naming mismatch is intentional for persistence stability. UI copy, docs, and roadmap must still use the product terms from the glossary.

Legacy maintenance fields and models may remain internally for compatibility, but they are not part of the current product surface and should not drive new UI.
