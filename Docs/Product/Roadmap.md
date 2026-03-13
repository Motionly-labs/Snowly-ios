# Product Roadmap

Snowly's next product bets after the core tracking foundation. This roadmap is a prioritization document, not a release contract.

Snapshot date: March 11, 2026.

---

## Current Position

Snowly already has a strong core ski-day stack:

- Live tracking with run detection
- Apple Watch companion and independent mode
- Resort map caching and weather
- Crew real-time location sharing and pins
- Session history, share cards, and gear checklist

The main gaps are no longer in raw data capture. They are in:

- **Post-session understanding** - users can record a day, but cannot deeply replay or explain it
- **Between-session retention** - season goals and progress loops are still light
- **Crew utility** - group awareness exists, but group coordination is still shallow
- **Gear intelligence** - gear is organized, but not connected to actual ski days

---

## Prioritization Rules

Every roadmap item should pass these filters:

1. Strengthen a core ski-day job to be done, not a generic lifestyle feature.
2. Reuse existing product assets first: `trackData`, resort maps, watch data, and Crew infrastructure.
3. Preserve Snowly's product principles: privacy by default, offline first, no mandatory accounts, no third-party analytics.
4. Prefer features that improve retention or differentiation without forcing a heavy backend footprint.

---

## Roadmap Summary

| Priority | Feature | Why it matters now | Main dependencies |
|---|---|---|---|
| P0 | Session Replay + Trail Attribution | Turns history from an archive into a destination | `SkiRun.trackData`, `SkiMapCacheService`, resort trail/lift geometry, SwiftData migration |
| P1 | Season Goals + Challenge Center | Creates a reason to reopen the app between ski days | `StatsService`, `UserProfile`, `DeviceSettings`, light model changes |
| P1 | Crew Meet-up 2.0 | Upgrades Crew from passive presence to active coordination | `CrewService`, `CrewAPIClient`, server endpoints, map labels |
| P2 | Gear Locker + Checklist | Makes gear preparation useful without bloating the product language | `GearSetup`, `GearAsset`, `SkiSession`, local reminder persistence |
| P2 | Safety Mode | High user trust value, but only after tuning and opt-in design | tracking state, battery state, Crew, notification rules |

---

## P0: Session Replay + Trail Attribution

### Product Goal

After a ski day, users should be able to answer:

- Which trails did I ski?
- Which lifts did I take?
- What was my fastest run?
- Where did I spend most of my time?
- How did the day unfold from first lift to last run?

### Why P0

This is the highest-leverage next step because Snowly already captures the raw inputs. The missing layer is interpretation. It deepens the value of every recorded session without requiring a broad new social or backend system.

### Scope

- Match completed runs to named trails and lifts within the current resort map
- Add a session replay timeline with scrubber and map playback
- Show run rankings: fastest, longest, biggest vertical, smoothest streak
- Add a trail summary: most-skied trail, number of passes per trail, favorite lift
- Add richer share output based on the replay summary

### Data / Engineering Notes

- Best initial implementation is mostly client-side
- Use existing `SkiRun.trackData` blobs plus resort geometry already cached by `SkiMapCacheService`
- Persist derived metadata only after the matching logic is stable
- Expect a SwiftData migration if matched trail/lift identifiers are stored on `SkiRun`

### Risks

- OpenStreetMap resort data quality varies by mountain
- Matching confidence must degrade gracefully when trail geometry is incomplete or ambiguous

### Success Signal

History becomes a feature users reopen on the same day, not just a record they never revisit.

---

## P1: Season Goals + Challenge Center

### Product Goal

Give users a reason to come back even when they are not actively on the mountain.

### Scope

- Season goals for ski days, runs, vertical, distance, and total active time
- Progress widgets on Activity and Profile
- Lightweight streaks and milestone badges
- Optional monthly challenges that work entirely on-device
- End-of-day and end-of-week progress summaries

### Why Now

Snowly already computes strong stats, but they are mostly retrospective. This feature turns stats into forward momentum and improves retention without changing the app's privacy posture.

### Data / Engineering Notes

- Start with local goals in `UserProfile` or `DeviceSettings`
- Reuse `StatsService` for aggregation rather than creating a parallel logic path
- Keep badge logic deterministic and offline-capable

### Risks

- Badge spam can cheapen the product if every session triggers celebration
- Goals must adapt to casual and expert skiers without forcing checklist friction

### Success Signal

Users check Snowly before and after ski days because progress status matters, not only because tracking exists.

---

## P1: Crew Meet-up 2.0

### Product Goal

Make Crew useful for coordination, not just visibility.

### Scope

- One-tap statuses such as "on my way", "at lift", "at lodge", and "last run"
- Better pin flows: ETA, distance, and stale/fresh state
- Quick actions such as "find closest friend" or "navigate back to pinned meetup"
- Crew state cards that explain who is moving, waiting, or offline
- Optional "rejoin group" suggestions after members split apart

### Why Now

Snowly already has real-time member locations and pin messages. The next value step is not more map presence; it is actionability. This is the most natural expansion of the existing Crew system.

### Data / Engineering Notes

- Requires coordinated iOS and server work through `CrewService` and `CrewAPIClient`
- Keep the first version lightweight: event states and ETA heuristics before complex route guidance
- Watch support is a follow-up, not a launch blocker

### Risks

- Overbuilding route intelligence too early will slow delivery
- Frequent Crew updates can create battery pressure if sync rules are not tuned

### Success Signal

Crew becomes something users actively open during the ski day to regroup, not just glance at.

---

## P2: Gear Locker + Checklist

### Product Goal

Make Gear a locker-first flow: create gear once, attach reminder schedules, build checklists from locker gear, and use a visual checklist to pack.

Detailed requirements: [Gear Locker + Checklist Requirements](GearUsageMaintenanceRequirements.md)

### Scope

- Create gear in the locker with brand, model, notes, archive state, and optional reminder schedule
- Build named checklists by selecting locker gear
- Keep the body-zone visual checklist as the primary packing surface for one checklist
- Attach the active checklist to each session and show recent sessions using that checklist
- Keep reminder schedules local and device-first

### Why P2

This can become a strong retention feature, but it is still less central than replay or Crew because it mainly improves preparation, not the on-mountain tracking loop.

### Data / Engineering Notes

- `SkiSession` should continue to carry the attached checklist snapshot
- Reminder schedules and visual-checklist state can stay in local persistence layers on top of synced gear models
- Keep the persisted model names `GearSetup` and `GearAsset` for stability even though product copy says checklist and gear

### Risks

- Too much gear creation or checklist editing friction will reduce adoption
- Terminology drift between code, docs, and UI will create confusion quickly

### Success Signal

Users keep Snowly open before a trip because locker gear, reminders, and the visual checklist help them prepare faster.

---

## P2: Safety Mode

### Product Goal

Add high-trust safeguards for solo skiers and groups without creating false-alarm fatigue.

### Scope

- Long-stop reminders during an active session
- Low-battery warnings during tracking
- Optional Crew nudges when a member stops updating unexpectedly
- Clear opt-in controls and safety wording
- Local-first rules with escalation only when the user explicitly enables Crew-related alerts

### Why P2

This has meaningful trust value, but it should follow stronger replay and coordination work. Safety features are expensive to get wrong and need careful threshold tuning.

### Data / Engineering Notes

- Build on existing battery and tracking state services first
- Crew escalation rules should be conservative and fully opt-in
- Treat notification design as part of the product scope, not an afterthought

### Risks

- False positives can erode trust quickly
- Background execution constraints may limit reliability for certain alert types

### Success Signal

Users describe Snowly as something that helps them feel safer on-mountain, not just something that records stats.

---

## Explicitly Not Prioritized Yet

These are intentionally not near-term roadmap items:

- Public social feed
- Mandatory account system for core tracking
- Generic AI coaching without hard product inputs
- Broad off-mountain fitness expansion

These all pull attention away from Snowly's best current wedge: high-quality on-mountain tracking, replay, and coordination.

---

## Recommended Execution Order

1. Ship `Session Replay + Trail Attribution`
2. Ship `Season Goals + Challenge Center`
3. Ship `Crew Meet-up 2.0`
4. Ship `Gear Locker + Checklist`
5. Ship `Safety Mode`

If engineering capacity is split across iOS and server, run `Season Goals + Challenge Center` in parallel with backend-heavy Crew work.

---

## Decision Checkpoint

Re-evaluate the roadmap after P0 ships. If replay meaningfully increases post-session opens and sharing, keep compounding that layer. If Crew usage grows faster, move Crew Meet-up 2.0 ahead of goals.
