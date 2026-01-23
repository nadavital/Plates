# Continuity Ledger - Trai

## Goal (incl. success criteria)
Implement bug fixes and UX improvements from user testing sessions.

## Constraints/Assumptions
- iOS 26.0+, Swift 6.2, SwiftUI, SwiftData with CloudKit
- Must maintain CloudKit compatibility (no @Attribute(.unique), all optionals)
- Use Gemini API for AI features
- Follow CLAUDE.md guidelines (modularity, <300 lines/file, modern Swift)
- App accent color is RED (not orange) - set in Assets

## Key Decisions
- **Cancel/Dismiss**: `Button("Cancel", systemImage: "xmark")` with `.cancellationAction` placement
- **Confirm/Done/Save**: `Button("Done", systemImage: "checkmark")` with `.confirmationAction` placement
- "Trai" / "Ask Trai" uses hexagon icon (`circle.hexagongrid.circle`) everywhere
- LiveActivityManager is now a singleton to prevent duplicate activities

## State

### Done (Previous Phases)
- Phase 1-6: All previous bug fixes completed
- Memory relevance filtering, Live Activity entitlement, etc.

### Done (User Testing Bug Fixes - January 2026)
- **Issue #6 & #13**: Fixed Live Activity deduplication
  - Made LiveActivityManager a singleton (`LiveActivityManager.shared`)
  - Added guard in `startActivity()` to prevent duplicates
  - Added `cancelAllActivities()` call on app launch
  - Added guard in ContentView to prevent multiple workouts
- **Issue #2**: Fixed typing slow in Live Workout View
  - Reduced Live Activity timer from 1s to 5s
  - Reduced heart rate polling from 2s to 5s
- **Issue #5**: Fixed up-next recommending same exercise
  - Added filter to exclude exercises already in current workout
- **Issue #10**: Fixed weight suggestion logic
  - Prioritizes current workout's last set weight when user modifies it
  - Falls back to historical pattern only when user hasn't changed weight
- **Issue #8**: Fixed floating point weight issues (90 showing as 89.9)
  - Added rounding to nearest 0.5 when saving weights
  - Applied to SetRow weight input and ExerciseHistory storage
- **Issue #1**: Improved photo loading indicator
  - Added modal overlay with descriptive text ("Analyzing equipment...")
  - Removed tiny inline ProgressView
- **Issue #3**: Fixed heart rate display in Live Activity
  - Shows "--" when heart rate unavailable instead of hiding the section
- **Issue #11**: Fixed description text alignment
  - Added `.multilineTextAlignment(.leading)` to description texts

### Done (January 2026 - Phase 2)
- **Issue #4**: PR management screen implemented
  - Created `PersonalRecordsView.swift` with full PR tracking
  - Shows PRs grouped by muscle group with search/filter
  - Displays max weight, max reps, max volume, estimated 1RM per exercise
  - Detail view shows PR cards and recent history
  - Accessible via trophy button in WorkoutsView toolbar
- **Issue #7**: Timer removed from Live Activity
  - Removed timer from Lock Screen view
  - Removed timer from Dynamic Island expanded and compact views
  - Replaced with volume display and current exercise name
- **Issue #9**: Machine info for non-photo exercises
  - Updated `defaultExercises` tuple to include equipment names
  - Added `inferEquipment(from:)` static method to infer equipment from exercise names
  - Added `displayEquipment` computed property that returns stored or inferred equipment
  - Updated `LiveWorkoutEntry` init to use `displayEquipment`

### Not Implemented (Deferred)
- **Issue #12**: End confirmation morphing (iOS 26 API research needed)

### Done (January 2026 - PR View Improvements)
- PersonalRecordsView improvements:
  - Fixed StatBox to use equal width distribution with consistent height
  - Fixed ExercisePRRow to use Grid layout for consistent column alignment
  - Fixed color reference (`.accent` → `Color.accentColor`)
  - Added edit functionality via EditHistorySheet (weight, reps, date)
  - Added swipe-to-delete for individual history entries
  - Added context menu with Edit/Delete options
  - Added "Delete All Records" button for exercise
  - Added confirmation dialogs for all delete actions
  - **Weight unit support**: Respects user's lbs/kg preference from UserProfile
    - All weight displays now convert kg↔lbs based on `usesMetricExerciseWeight`
    - Affects ExercisePRRow, PRDetailSheet, HistoryRow, EditHistorySheet
    - Volume displays also converted to proper units
- WorkoutsView data consistency fix:
  - `deleteLiveWorkout()` now also deletes associated ExerciseHistory entries
  - Prevents orphaned PR records when workouts are deleted
- LiveWorkoutDetailSheet edit sync:
  - When editing a completed workout, ExerciseHistory is now synced
  - `syncExerciseHistory()` updates all history entries linked to workout entries

## Open Questions
- None

## Working Set
- PersonalRecordsView.swift (PR management, edit/delete)
- WorkoutsView.swift (data consistency on deletion)
