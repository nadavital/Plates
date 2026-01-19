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

## Quick Reference: Navigation Destination Safety

When creating a view that will be a NavigationLink destination:

| Pattern | Safe? | Notes |
|---------|-------|-------|
| `@Query` at view level | ❌ | Can cause freeze |
| `@State` + manual fetch | ✅ | Always works |
| Pass data from parent | ✅ | Best for simple cases |
| `@Bindable` model | ✅ | Good for editing |
