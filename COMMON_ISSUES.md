# Common Issues & Solutions

This document tracks recurring issues encountered during development and their solutions.

---

## 1. Navigation Freeze with @Query in Destination Views

### Symptom
App freezes when navigating to a view (e.g., clicking a NavigationLink in Profile). The app becomes unresponsive and may need to be force-quit.

### Cause
Using `@Query` property wrapper directly in views that are **navigation destinations** can cause freezing. This appears to be a SwiftUI/SwiftData bug where the query initialization conflicts with the navigation transition.

### Solution
Use `@State` + manual fetch with `onAppear` instead of `@Query`:

**Bad (causes freeze):**
```swift
struct CustomExercisesView: View {
    @Query(filter: #Predicate<Exercise> { $0.isCustom == true })
    private var customExercises: [Exercise]  // CAUSES FREEZE

    var body: some View { ... }
}
```

**Good (works correctly):**
```swift
struct CustomExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var customExercises: [Exercise] = []

    var body: some View {
        List { ... }
        .onAppear {
            fetchCustomExercises()
        }
    }

    private func fetchCustomExercises() {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isCustom == true },
            sortBy: [SortDescriptor(\.name)]
        )
        customExercises = (try? modelContext.fetch(descriptor)) ?? []
    }
}
```

### Affected Views (already fixed)
- `CustomExercisesView` - Custom exercises management
- `AllMemoriesView` - Coach memories list
- `ReminderSettingsView` - Uses `@State` for custom reminders

### Key Pattern
Views that use `@Query` at the root level (like `ProfileView`, `DashboardView`) work fine. The issue occurs specifically in **navigation destination** views.

---

## 2. HealthKit Authorization Not Persisting

### Symptom
HealthKit data sync (weight, food) doesn't work even though the toggle is enabled.

### Cause
- User may not have granted HealthKit permissions
- Errors are being silently swallowed with `try?`
- The app needs to request specific read/write permissions

### Solution
1. Ensure proper permissions are requested in `HealthKitService.requestAuthorization()`:
   - Read: bodyMass, bodyFatPercentage, activeEnergyBurned, stepCount, workouts
   - Write: bodyMass, **dietaryEnergyConsumed**

2. Use proper error handling instead of `try?`:
```swift
do {
    try await healthKitService.requestAuthorization()
    try await healthKitService.saveDietaryEnergy(calories, date: date)
    print("HealthKit: Success")
} catch {
    print("HealthKit: Failed - \(error.localizedDescription)")
}
```

3. Check iOS Settings > Privacy > Health > Trai to verify permissions were granted.

---

## 3. SwiftData CloudKit Constraints

### Issue
CloudKit sync doesn't support certain SwiftData features.

### Constraints
- **No `@Attribute(.unique)`** - CloudKit doesn't support unique constraints
- **All properties need defaults or be optional** - Required for CloudKit sync
- **All relationships must be optional** - CloudKit requirement

### Solution
Always use optional relationships and provide default values:
```swift
@Model
final class MyModel {
    var name: String = ""  // Default value
    var optionalField: String?  // Optional
    var relationship: RelatedModel?  // Optional relationship
}
```

---

## 4. Unit Conversion Mid-Workout

### Symptom
When changing weight units (kg/lbs) during a workout, displayed values don't update correctly.

### Cause
The weight values are stored internally as kg, but the display wasn't re-rendering when the unit preference changed.

### Solution
Add `.onChange(of: usesMetricWeight)` to re-calculate display values:
```swift
.onChange(of: usesMetricWeight) { _, newUsesMetric in
    if set.weightKg > 0 {
        let displayWeight = newUsesMetric ? set.weightKg : set.weightKg * 2.20462
        weightText = formatWeight(displayWeight)
    }
}
```

---

## 5. Keyboard Not Dismissing

### Symptom
Tapping outside text fields doesn't dismiss the keyboard.

### Solution
Add scroll dismiss behavior and tap gesture:
```swift
ScrollView {
    // Content
}
.scrollDismissesKeyboard(.interactively)
.onTapGesture {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
```

---

## 6. Live Workout Is Smooth In Simulator But Slow On Phone

### Symptom
Live workout interactions (typing reps/weight, add set, switching cards) feel fine on simulator but stall on a physical device.

### Why It Happens
- Device traces include real scheduling, thermal behavior, and sync pressure that simulator often hides.
- Large local/CloudKit history can amplify SwiftData and view invalidation work.

### Repro + Profiling Commands
1. Seed deterministic heavy workout data in simulator/device build:
```bash
xcrun simctl launch booted Nadav.Trai --seed-live-workout-perf-data
```

2. Capture a fresh-data trace from a connected phone:
```bash
./scripts/profile_live_workout_device.sh --udid <DEVICE_UDID> --bundle-id Nadav.Trai --duration 90 --tag fresh
```

3. Capture a heavy-data trace:
```bash
./scripts/profile_live_workout_device.sh --udid <DEVICE_UDID> --bundle-id Nadav.Trai --duration 90 --tag heavy --launch-arg --seed-live-workout-perf-data
```

### Output Artifacts
- `/tmp/Trai-liveworkout-<tag>-<timestamp>.trace`
- `/tmp/Trai-liveworkout-<tag>-time-sample.xml`
- `/tmp/Trai-liveworkout-<tag>-hotspots.csv`

### Phone-Only Latency Troubleshooting Matrix
| Trace Signal | Likely Cause | What To Verify | Mitigation |
|---------|---------|---------|---------|
| `WorkoutsView.loadRecoveryAndScores` / `MuscleRecoveryService` samples during live workout | Background tab recomputation still running while sheet is open | `ActiveWorkoutRuntimeState` is wired in `ContentView`, `LiveWorkoutView`, `DashboardView`, and `WorkoutsView` | Keep runtime gating enabled and refresh deferred work only after workout sheet closes |
| Dominant `AG::Graph::*` / `find1` on Main Thread | Excessive SwiftUI invalidation and list filtering work | Whether expensive getters/filters run per keystroke | Cache derived values and avoid broad recomputation on each set edit |
| Frequent `SetRow` / live row body reevaluation hitches | UI update churn from timers/polling | Poll cadence and watch payload update frequency | Keep adaptive polling + payload-delta publishing; avoid adding high-frequency timers |
| Spikes around save/merge/CloudKit frames | Save pressure from rapid edits | Save frequency during typing/add-set bursts | Route edits through `LiveWorkoutPersistenceCoordinator` and flush only on critical events |
| Simulator smooth, phone stutters | Device-only scheduling, thermal, and sync pressure | Compare fresh vs heavy traces on physical iPhone | Always baseline on device with both data states before/after optimization |

---

## 7. App Launch / Reopen / Tab Latency Regression Workflow

### When to Use
Use this when launch, reopen, or tab transitions feel slower than expected, or before merging larger UI/data-loading changes.

### Primary Guardrail Command
```bash
./scripts/run_app_latency_regression.sh --sim-id <SIM_UDID>
```

### What It Produces
- JSON summary: `/tmp/trai-app-latency-summary-<timestamp>.json`
- Markdown report: `/Users/navital/Desktop/Trai/.agent/done/app-latency-regression-report.md`
- Raw xcodebuild log: `/tmp/trai-app-latency-<timestamp>.log`

### Baseline Source of Truth
- `scripts/latency_baseline_simulator.json`
- If baseline budgets are updated, also update `/Users/navital/Desktop/Trai/.agent/app-latency-issues.md` with rationale and latest measured values.

### Extractor Fixture Validation
```bash
python3 scripts/test_extract_ui_latency_metrics.py
```

### Optional Combined Stability + App Latency Run
```bash
./scripts/run_live_workout_stability.sh --mode sim --with-app-latency
```

---

## Quick Reference: Navigation Destination Safety

When creating a view that will be a NavigationLink destination:

| Pattern | Safe? | Notes |
|---------|-------|-------|
| `@Query` at view level | ❌ | Can cause freeze |
| `@State` + manual fetch | ✅ | Always works |
| Pass data from parent | ✅ | Best for simple cases |
| `@Bindable` model | ✅ | Good for editing |
