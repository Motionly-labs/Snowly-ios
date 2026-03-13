# Main Branch Merge Checklist

Use this checklist before opening or merging a PR into `main`, especially for the first public-facing merge.

---

## Repository And Documentation

- [ ] `README.md` matches the current repo name, clone URL, platform requirements, and feature set
- [ ] `Docs/README.md` links to any new setup, architecture, or release docs
- [ ] `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, and `LICENSE` are still accurate
- [ ] User-visible or contributor-visible behavior changes were documented in the same PR
- [ ] Product wording is consistent across UI copy and docs
- [ ] Any backend assumptions in docs match the current `DEBUG` and `RELEASE` defaults

---

## Automated Verification

- [ ] iOS app builds
- [ ] Unit and integration tests pass
- [ ] UI tests pass if the touched area is covered
- [ ] Watch app still builds if shared code or connectivity changed

Suggested commands:

```bash
xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

xcodebuild -project Snowly.xcodeproj -scheme Snowly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SnowlyUITests test
```

---

## Manual Validation

Simulator:

- [ ] App launches cleanly
- [ ] Onboarding completes
- [ ] Fixture replay still works for tracking/history changes
- [ ] Gear, history, settings, and export flows still behave as expected

Real iPhone:

- [ ] Location permission flow still makes sense
- [ ] Background tracking still works with the phone locked
- [ ] HealthKit flow still authorizes and writes workouts
- [ ] CloudKit sync still behaves correctly when available
- [ ] Share card export still renders correctly

Apple Watch:

- [ ] Watch app launches and records a session
- [ ] Watch-to-phone import still works if connectivity or tracking code changed
- [ ] Active session widget / Live Activity behavior still makes sense

Backend-backed flows:

- [ ] Crew create/join/pin flows work against the intended server
- [ ] Session upload works against the intended server
- [ ] Server health check works for the configured base URL

---

## Privacy And Capability Hygiene

- [ ] No third-party analytics or dependency creep was introduced
- [ ] `Info.plist` permission strings still describe the actual behavior
- [ ] `Snowly/PrivacyInfo.xcprivacy` was updated if collected/accessed data changed
- [ ] New deep links, shortcuts, widgets, or capabilities are documented
- [ ] Any new server communication is explicit and justified by product behavior

---

## Release Hygiene

- [ ] Version/build numbers were updated if this merge is meant to ship
- [ ] No debug-only assumptions leaked into user-facing docs
- [ ] No localhost URLs or personal test endpoints remain in release-facing copy
- [ ] The PR description explains risk areas, test coverage, and any known follow-up work
