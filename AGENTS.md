# AGENTS.md

## Purpose
- Shared operating notes for coding agents working in this repository.

## Project Scope
- App code: `/Users/nadav/Desktop/Trai/Trai`
- Widgets: `/Users/nadav/Desktop/Trai/TraiWidgets`
- Xcode project: `/Users/nadav/Desktop/Trai/Trai.xcodeproj`

## Working Rules
- Make targeted, minimal changes.
- Preserve existing architecture and naming conventions.
- Run a focused build/test check after edits when possible.
- Do not revert unrelated local changes.

## Validation
- Prefer project-level build checks for modified Swift files.
- If full build is expensive, run the smallest check that still validates compile safety.

## Product Notes
- Branding: keep the Trai lens/hexagon icon unless explicitly discussed; avoid changing icon shapes unilaterally.
- Color consistency: match accents (e.g., Review with Trai buttons, toolbar checkmarks) to the Trai Memories hexagon colors; use `.tint(.accentColor)` for confirmation actions where applicable.
- Widgets: the Trai widget "Log Food" button was reported as non-functional; verify the widget action/deep link flow.

## Reliability Notes
- Widget deep links: prefer routing widget `logfood` through the same `showingFoodCamera`/intent state used by `LogFoodCameraIntent`, and handle pending deep links on initial `.onAppear` (not only `.onChange`) to avoid cold-launch misses.
- Live workout HealthKit: HR streaming is anchored-query based; make sure HealthKit auth is requested explicitly and seed UI with the most recent sample so the screen doesn't appear blank while live updates warm up.

## Performance Notes
- Live workout UI is sensitive to main-thread work. Avoid JSON encode/decode in hot getters (e.g., `LiveWorkoutEntry.sets`) and avoid synchronous `modelContext.save()` on `Add Set`; prefer caching and debounced saves.
