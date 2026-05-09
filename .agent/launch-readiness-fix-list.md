# Trai Launch Readiness Fix List

Status legend: `[ ]` open, `[/]` in progress, `[x]` fixed locally, `[?]` blocked or needs external verification.

## App Store / Account / Billing

- [x] Add public in-app account deletion for Sign in with Apple accounts.
- [x] Add backend account deletion/tombstone endpoint and revoke active sessions.
- [x] Move backend access and refresh tokens out of `UserDefaults` and into Keychain.
- [x] Apply verified StoreKit entitlements locally after purchase/restore even when backend sync fails, then reconcile with backend later.
- [x] Update HealthKit purpose strings to disclose the full activity, workout, heart-rate, body, nutrition, and active-energy scope.
- [x] Request time-sensitive notification authorization when using time-sensitive interruption levels, or remove the entitlement/levels.
- [x] Add a normal backend `test` command that runs release-critical verification checks.

## Privacy / Health / AI Logging

- [x] Respect `syncFoodToHealthKit` in every food save path.
- [x] Stop food save flows from reporting success or writing side effects when SwiftData persistence fails.
- [x] Redact/gate raw AI prompt, response, and nutrition logging outside debug builds.
- [x] Rewrite or enforce Incognito chat behavior so privacy copy matches what leaves the device.
- [x] Add a manual fallback from the food camera review error state.
- [x] Remove local `Secrets.swift` from the app source tree and add a build-time guard against checked-in/source-tree secrets.
- [x] Rotate the previously local Google API key outside this repo.
  - [x] Repo-side scan found no source-tree `AIza...` key outside the intentional guard text.
  - [x] `git log --all -- Trai/Core/Services/Secrets.swift` found no tracked history for the deleted local file.
  - [x] `git log --all -S 'AIza' -- Trai Backend Shared scripts` found no matching git-history commit.
  - [x] Created replacement restricted Gemini API key in project `gen-lang-client-0500643819` without printing the final key string.
  - [x] Added replacement key as Secret Manager `GEMINI_API_KEY` version 2.
  - [x] Deleted old Gemini API key `Plates` (`07dd2631-e039-45ef-8c05-d0f4d995989f`).
  - [x] Destroyed old Secret Manager `GEMINI_API_KEY` version 1.
  - [x] Verified production and staging Cloud Run health after rotation; both use `TRAI_AI_PROVIDER=openai`, have provider key present, and do not mount `GEMINI_API_KEY`.

## Workouts / Live Activities / Widgets

- [x] Do not cancel active workout Live Activities on app relaunch.
- [x] Make Live Activity widget controls durable or route users back to the active workout instead of relying on in-process polling only.
- [x] Prevent duplicate active workouts.
- [x] Refresh widget data after workout completion/cancel/delete and relevant HealthKit merge writes.
- [x] Surface HealthKit/watch setup failures inside the live workout UI.
- [x] Verify Control Center workout start routing opens the intended workout path.

## Destructive Actions / Accessibility / Polish

- [x] Confirm before clearing all chat history.
- [x] Confirm before deleting workouts from the all-workouts sheet and disable full-swipe deletion.
- [x] Improve Dynamic Type behavior for fixed-size profile/settings controls.
- [x] Improve Dynamic Type behavior for fixed-size chat and food suggestion cards.
- [x] Give tappable workout goal cards accessible button semantics or explicit accessibility actions.
- [x] Tighten food review layout and use Trai surface styles consistently.

## Verification

- [x] `npm --prefix Backend test`
- [x] `sh scripts/check_no_source_tree_secrets.sh`
- [x] XcodeBuildMCP simulator build/run for `Trai` on iPhone 17 Pro with `-traiUITesting -traiUseInMemoryStore -traiSkipOnboarding`
- [x] XcodeBuildMCP screenshot capture after latest simulator launch: `/var/folders/bj/cxpn19xd78q4k1h9w4c_99700000gn/T/screenshot_optimized_1284e823-c14a-4206-b5f3-4cce842b595c.jpg`
- [x] Focused simulator unit tests: `TraiTests/FoodHealthKitSyncPolicyTests` and `TraiTests/AccountSessionTokenPersistenceTests` passed 3/3.
- [x] `TraiTests/FoodMemoryModelStorageTests` passed 49/49 after fixing memory-only suggestions and deterministic resolver ordering.
- [x] Full `TraiTests` unit target passed 160 tests with 1 expected device-debug skip and 0 failures.
- [x] Latest simulator UI smoke suite passed 15 tests with 1 expected stress-path skip and 0 failures.
