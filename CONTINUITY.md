# Continuity Ledger - Trai

## Goal (incl. success criteria)
Equipment photo exercise identification now matches to existing exercises in user's library.

## Constraints/Assumptions
- iOS 26.0+, Swift 6.2, SwiftUI, SwiftData with CloudKit
- Must maintain CloudKit compatibility (no @Attribute(.unique), all optionals)
- Use Gemini API for AI features
- Follow CLAUDE.md guidelines (modularity, <300 lines/file, modern Swift)
- App accent color is RED (not orange) - set in Assets

## Key Decisions (This Session)
- **Cancel/Dismiss**: `Button("Cancel", systemImage: "xmark")` with `.cancellationAction` placement
- **Confirm/Done/Save**: `Button("Done", systemImage: "checkmark")` with `.confirmationAction` placement
- Plain `xmark` (not `xmark.circle.fill`) for toolbar cancel buttons
- "Trai" / "Ask Trai" uses hexagon icon (`circle.hexagongrid.circle`) everywhere
- Chat history icons stay as bubbles (they represent conversations, not Trai specifically)

## State

### Done (This Session)
Comprehensive toolbar button standardization (26+ sheets updated):

**Cancel buttons with xmark:**
- LiveWorkoutView, LogWeightSheet, ManualFoodEntrySheet, ProfileEditSheet
- MacroTrackingSettingsSheet, PlanAdjustmentSheet, EditFoodEntrySheet
- CustomReminderSheet, AddCustomExerciseSheet, CustomWorkoutSetupSheet
- ExerciseListView, ChatMealComponents, ChatCameraComponents, ChatPlanComponents
- FoodCameraView, WorkoutPlanChatFlow, EquipmentPhotoComponents, AddWeightView, AddFoodView

**Done/Confirm buttons with checkmark:**
- LiveWorkoutView (end + chat done), MacroDetailSheet, CalorieDetailSheet
- WorkoutDetailSheet, WorkoutSummarySheet, LiveWorkoutDetailSheet
- WorkoutPlanEditSheet, WorkoutTrendDetailSheet, AllWorkoutsSheet
- MuscleRecoveryCard, MemoryViews, PlanHistoryView, SettingsView
- PlanChatView, ChatCameraComponents, ChatPlanComponents, ChatMemoryComponents

**Trai icons standardized to hexagon:**
- LiveWorkoutComponents, TraiWidgets (both sizes), TraiShortcuts

### Now
- Complete

### Next
- Test equipment photo identification with existing exercises

## Files Modified
- GeminiService+Exercise.swift - Added existingExerciseNames parameter to analyzeExercisePhoto()
- ExerciseListView.swift - Pass exercise names when analyzing photo
- MuscleRecoveryService.swift - Exclude fullBody from recovery tracking (line 81)
- WeightTrackingView.swift - Removed sync HealthKit toolbar button
- LiveWorkoutView.swift - Apple Watch card only shows when connected/has data; summary shown inline instead of nested sheet
- WorkoutSummarySheet.swift - Added WorkoutSummaryContent for inline display

## Open Questions
- None

## Working Set
- Trai/Core/Services/GeminiService+Exercise.swift
- Trai/Features/Workouts/ExerciseListView.swift
