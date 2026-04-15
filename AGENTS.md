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

## Design Language
- Before changing UI, read [design.md](/Users/navital/Desktop/Trai/design.md) and preserve the app’s current warm, rounded, material-backed look.
- Prefer the existing design system tokens and components: `traiCard`, `traiPrimary`, `traiSecondary`, `traiTertiary`, `traiBackground`, `traiSheetBranding`, `TraiSpacing`, `TraiRadius`, and the Trai rounded font helpers.
- Keep main surfaces compact and card-based; move secondary information into toolbars, sheets, or drill-down views instead of making the main scroll surface taller.
- Use the Trai brand palette and semantic colors consistently, and keep the Trai lens/hexagon icon intact.
- Use Liquid Glass only as a small interactive accent on micro-surfaces like chat input controls or tiny buttons, not as the default language for primary cards.

## Reliability Notes
- Widget deep links: prefer routing widget `logfood` through the same `showingFoodCamera`/intent state used by `LogFoodCameraIntent`, and handle pending deep links on initial `.onAppear` (not only `.onChange`) to avoid cold-launch misses.
- Live workout HealthKit: HR streaming is anchored-query based; make sure HealthKit auth is requested explicitly and seed UI with the most recent sample so the screen doesn't appear blank while live updates warm up.

## Performance Notes
- Live workout UI is sensitive to main-thread work. Avoid JSON encode/decode in hot getters (e.g., `LiveWorkoutEntry.sets`) and avoid synchronous `modelContext.save()` on `Add Set`; prefer caching and debounced saves.
- Live workout latency checks: run `./scripts/run_live_workout_stability.sh --mode sim`; deeper context/results live in `/Users/nadav/Desktop/Trai/.agent/done/live-workout-latency-report.md`.
