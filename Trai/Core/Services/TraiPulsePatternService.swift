//
//  TraiPulsePatternService.swift
//  Trai
//
//  Deterministic behavior pattern extraction for Trai Pulse personalization.
//

import Foundation

enum TraiPulsePatternService {
    static func buildProfile(
        now: Date,
        foodEntries: [FoodEntry],
        workouts: [WorkoutSession],
        liveWorkouts: [LiveWorkout],
        suggestionUsage: [SuggestionUsage],
        behaviorEvents: [BehaviorEvent],
        profile: UserProfile?
    ) -> TraiPulsePatternProfile {
        let calendar = Calendar.current
        let end = now
        guard let start = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: end)) else {
            return .empty
        }

        let windowFoodEntries = foodEntries.filter { $0.loggedAt >= start && $0.loggedAt <= end }
        let workoutDays = combinedWorkoutDays(workouts: workouts, liveWorkouts: liveWorkouts, calendar: calendar)
        let workoutDatesInWindow = workoutDays.filter { $0 >= start && $0 <= end }
        let windowBehaviorEvents = behaviorEvents.filter { $0.occurredAt >= start && $0.occurredAt <= end }

        var workoutBucketCounts: [TraiPulseTimeWindow: Int] = [:]
        for workoutDate in workoutDatesInWindow {
            let hour = calendar.component(.hour, from: workoutDate)
            let bucket = workoutWindow(forHour: hour)
            workoutBucketCounts[bucket, default: 0] += 1
        }

        var mealBucketCounts: [TraiPulseTimeWindow: Int] = [:]
        for entry in windowFoodEntries {
            let hour = calendar.component(.hour, from: entry.loggedAt)
            let bucket = mealWindow(forHour: hour)
            mealBucketCounts[bucket, default: 0] += 1
        }

        let workoutWindowScores = normalizedScores(from: workoutBucketCounts, total: workoutDatesInWindow.count)
        let mealWindowScores = normalizedScores(from: mealBucketCounts, total: windowFoodEntries.count)
        let commonProteinAnchors = topProteinAnchors(entries: windowFoodEntries, proteinGoal: profile?.dailyProteinGoal)

        let adherenceContext = buildAdherenceContext(
            entries: windowFoodEntries,
            workoutsInWindow: Array(workoutDatesInWindow),
            proteinGoal: profile?.dailyProteinGoal
        )

        let behaviorActionAffinity = buildActionAffinity(from: windowBehaviorEvents)
        let legacyActionAffinity = buildActionAffinity(from: suggestionUsage)
        let actionAffinity = mergeAffinities(
            primary: behaviorActionAffinity,
            fallback: legacyActionAffinity,
            primaryWeight: 0.85
        )

        let actionSignalStrength = clamp(Double(windowBehaviorEvents.count) / 42.0)
        let maxActionAffinity = actionAffinity.values.max() ?? 0

        let confidence = clamp(
            (0.40 * adherenceContext.loggingCoverage) +
            (0.25 * adherenceContext.workoutCoverage) +
            (0.20 * actionSignalStrength) +
            (0.15 * maxActionAffinity)
        )

        return TraiPulsePatternProfile(
            workoutWindowScores: workoutWindowScores,
            mealWindowScores: mealWindowScores,
            commonProteinAnchors: commonProteinAnchors,
            adherenceNotes: adherenceContext.notes,
            actionAffinity: actionAffinity,
            confidence: confidence
        )
    }

    static func buildTrendSnapshot(
        now: Date,
        foodEntries: [FoodEntry],
        workouts: [WorkoutSession],
        liveWorkouts: [LiveWorkout],
        profile: UserProfile?,
        daysWindow: Int = 7
    ) -> TraiPulseTrendSnapshot? {
        guard daysWindow > 0, let profile else { return nil }

        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: now)
        guard let startDay = calendar.date(byAdding: .day, value: -(daysWindow - 1), to: endDay),
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            return nil
        }

        let windowFoodEntries = foodEntries.filter { entry in
            entry.loggedAt >= startDay && entry.loggedAt < endExclusive
        }

        var nutritionByDay: [Date: (calories: Int, protein: Double, entries: Int)] = [:]
        for entry in windowFoodEntries {
            let day = calendar.startOfDay(for: entry.loggedAt)
            let existing = nutritionByDay[day] ?? (0, 0, 0)
            nutritionByDay[day] = (
                calories: existing.calories + entry.calories,
                protein: existing.protein + entry.proteinGrams,
                entries: existing.entries + 1
            )
        }

        let proteinTarget = Double(max(profile.dailyProteinGoal, 1))
        let proteinHitThreshold = proteinTarget * 0.8
        let lowProteinThreshold = proteinTarget * 0.65
        let calorieGoal = max(profile.dailyCalorieGoal, 1)
        let calorieMin = Int(Double(calorieGoal) * 0.8)
        let calorieMax = Int(Double(calorieGoal) * 1.15)

        var daysWithFoodLogs = 0
        var proteinTargetHitDays = 0
        var calorieTargetHitDays = 0

        for dayOffset in 0..<daysWindow {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let daily = nutritionByDay[dayStart] ?? (0, 0, 0)
            if daily.entries > 0 {
                daysWithFoodLogs += 1
            }
            if daily.protein >= proteinHitThreshold {
                proteinTargetHitDays += 1
            }
            if daily.entries > 0 && daily.calories >= calorieMin && daily.calories <= calorieMax {
                calorieTargetHitDays += 1
            }
        }

        var lowProteinStreak = 0
        for dayOffset in 0..<daysWindow {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: endDay) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let dailyProtein = nutritionByDay[dayStart]?.protein ?? 0
            if dailyProtein < lowProteinThreshold {
                lowProteinStreak += 1
            } else {
                break
            }
        }

        let workoutDays = combinedWorkoutDays(workouts: workouts, liveWorkouts: liveWorkouts, calendar: calendar)
        let workoutDaysInWindow = workoutDays.filter { $0 >= startDay && $0 < endExclusive }.count
        let daysSinceWorkout = daysSinceLastWorkout(workoutDays: workoutDays, referenceDay: endDay, calendar: calendar)

        return TraiPulseTrendSnapshot(
            daysWindow: daysWindow,
            daysWithFoodLogs: daysWithFoodLogs,
            proteinTargetHitDays: proteinTargetHitDays,
            calorieTargetHitDays: calorieTargetHitDays,
            workoutDays: workoutDaysInWindow,
            lowProteinStreak: lowProteinStreak,
            daysSinceWorkout: daysSinceWorkout
        )
    }

    private struct AdherenceContext {
        let loggingCoverage: Double
        let workoutCoverage: Double
        let notes: [String]
    }

    private static func buildAdherenceContext(
        entries: [FoodEntry],
        workoutsInWindow: [Date],
        proteinGoal: Int?
    ) -> AdherenceContext {
        let calendar = Calendar.current
        let proteinTarget = Double(max(proteinGoal ?? 140, 1))
        let proteinHitThreshold = proteinTarget * 0.8

        var entriesByDay: [Date: [FoodEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.loggedAt)
            entriesByDay[day, default: []].append(entry)
        }

        let uniqueLoggedDays = entriesByDay.keys.count
        let loggingCoverage = clamp(Double(uniqueLoggedDays) / 14.0)
        let workoutCoverage = clamp(Double(Set(workoutsInWindow.map { calendar.startOfDay(for: $0) }).count) / 8.0)

        var weekdayStats: [Int: (hits: Int, total: Int)] = [:]
        var proteinHitDays = 0

        for (day, dayEntries) in entriesByDay {
            let protein = dayEntries.reduce(0.0) { $0 + $1.proteinGrams }
            let weekday = calendar.component(.weekday, from: day)
            var stat = weekdayStats[weekday] ?? (0, 0)
            stat.total += 1
            if protein >= proteinHitThreshold {
                stat.hits += 1
                proteinHitDays += 1
            }
            weekdayStats[weekday] = stat
        }

        var notes: [String] = []
        if loggingCoverage < 0.45 {
            notes.append("Logging is inconsistent lately")
        }

        let proteinHitRate = uniqueLoggedDays > 0 ? Double(proteinHitDays) / Double(uniqueLoggedDays) : 0
        if proteinHitRate < 0.45 && uniqueLoggedDays >= 4 {
            notes.append("Protein target is often missed")
        }

        if let weakWeekday = weakestWeekday(from: weekdayStats) {
            notes.append("\(weakWeekday) tends to be your hardest consistency day")
        }

        return AdherenceContext(
            loggingCoverage: loggingCoverage,
            workoutCoverage: workoutCoverage,
            notes: Array(notes.prefix(2))
        )
    }

    private static func weakestWeekday(from weekdayStats: [Int: (hits: Int, total: Int)]) -> String? {
        var weakest: (day: Int, rate: Double)?
        for (weekday, stat) in weekdayStats where stat.total >= 2 {
            let rate = Double(stat.hits) / Double(stat.total)
            if let current = weakest {
                if rate < current.rate {
                    weakest = (weekday, rate)
                }
            } else {
                weakest = (weekday, rate)
            }
        }

        guard let weakest, weakest.rate <= 0.35 else { return nil }

        switch weakest.day {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return nil
        }
    }

    private static func buildActionAffinity(from suggestionUsage: [SuggestionUsage]) -> [String: Double] {
        let actionScores: [TraiPulseAction.Kind: Double] = suggestionUsage.reduce(into: [:]) { partialResult, usage in
            let mapped = actionKind(for: usage.suggestionType)
            partialResult[mapped, default: 0] += Double(max(usage.tapCount, 0))
        }

        let total = actionScores.values.reduce(0, +)
        guard total > 0 else { return [:] }

        var normalized: [String: Double] = [:]
        for (kind, value) in actionScores {
            normalized[kind.rawValue] = clamp(value / total)
        }
        return normalized
    }

    private static func buildActionAffinity(from behaviorEvents: [BehaviorEvent]) -> [String: Double] {
        guard !behaviorEvents.isEmpty else { return [:] }

        var actionScores: [TraiPulseAction.Kind: Double] = [:]
        for event in behaviorEvents {
            guard let kind = actionKind(forBehaviorActionKey: event.actionKey) else { continue }
            let weight = behaviorOutcomeWeight(event.outcome)
            guard weight != 0 else { continue }
            actionScores[kind, default: 0] += weight
        }

        let followThrough = followThroughRates(from: behaviorEvents)
        var adjustedScores = actionScores.mapValues { max(0, $0) }
        for (kind, rate) in followThrough {
            let multiplier = 0.85 + (rate * 0.45)
            adjustedScores[kind, default: 0] *= multiplier
        }

        let total = adjustedScores.values.reduce(0, +)
        guard total > 0 else { return [:] }

        var normalized: [String: Double] = [:]
        for (kind, value) in adjustedScores where value > 0 {
            normalized[kind.rawValue] = clamp(value / total)
        }
        return normalized
    }

    private static func followThroughRates(
        from behaviorEvents: [BehaviorEvent],
        horizonMinutes: Int = 90
    ) -> [TraiPulseAction.Kind: Double] {
        guard horizonMinutes > 0 else { return [:] }

        var opportunitiesByKind: [TraiPulseAction.Kind: [Date]] = [:]
        var conversionsByKind: [TraiPulseAction.Kind: [Date]] = [:]

        for event in behaviorEvents {
            guard let kind = actionKind(forBehaviorActionKey: event.actionKey) else { continue }
            if isOpportunityOutcome(event.outcome) {
                opportunitiesByKind[kind, default: []].append(event.occurredAt)
            }
            if isConversionOutcome(event.outcome) {
                conversionsByKind[kind, default: []].append(event.occurredAt)
            }
        }

        let horizon = TimeInterval(horizonMinutes * 60)
        var rates: [TraiPulseAction.Kind: Double] = [:]

        for (kind, opportunities) in opportunitiesByKind {
            guard opportunities.count >= 2 else { continue }
            let sortedOpportunities = opportunities.sorted()
            let sortedConversions = (conversionsByKind[kind] ?? []).sorted()
            guard !sortedConversions.isEmpty else {
                rates[kind] = 0
                continue
            }

            var conversionIndex = 0
            var matched = 0

            for opportunity in sortedOpportunities {
                while conversionIndex < sortedConversions.count && sortedConversions[conversionIndex] < opportunity {
                    conversionIndex += 1
                }
                guard conversionIndex < sortedConversions.count else { break }

                let conversion = sortedConversions[conversionIndex]
                if conversion.timeIntervalSince(opportunity) <= horizon {
                    matched += 1
                    conversionIndex += 1
                }
            }

            let rate = Double(matched) / Double(sortedOpportunities.count)
            rates[kind] = clamp(rate)
        }

        return rates
    }

    private static func mergeAffinities(
        primary: [String: Double],
        fallback: [String: Double],
        primaryWeight: Double
    ) -> [String: Double] {
        let clampedPrimaryWeight = clamp(primaryWeight)
        let fallbackWeight = 1 - clampedPrimaryWeight

        var merged: [String: Double] = [:]
        let keys = Set(primary.keys).union(fallback.keys)
        for key in keys {
            let score =
                (primary[key, default: 0] * clampedPrimaryWeight) +
                (fallback[key, default: 0] * fallbackWeight)
            if score > 0 {
                merged[key] = score
            }
        }

        let total = merged.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return merged.mapValues { clamp($0 / total) }
    }

    static func learnedWorkoutTimeWindows(from profile: TraiPulsePatternProfile?, maxWindows: Int = 2, minScore: Double = 0.18) -> [String] {
        guard
            let profile,
            maxWindows > 0
        else { return [] }

        let rankedWindows = profile.workoutWindowScores
            .compactMap { rawWindow, score -> (TraiPulseTimeWindow, Double)? in
                guard
                    let window = TraiPulseTimeWindow(rawValue: rawWindow),
                    score >= minScore
                else { return nil }
                return (window, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.rawValue < rhs.0.rawValue }
                return lhs.1 > rhs.1
            }

        return rankedWindows
            .prefix(maxWindows)
            .map { "\(label(for: $0.0.label))" }
    }

    private static func label(for windowLabel: String) -> String {
        if let window = TraiPulseTimeWindow.allCases.first(where: { $0.label == windowLabel }) {
            return "\(window.label) (\(window.hourRange.start)-\(window.hourRange.end))"
        }
        return windowLabel
    }

    private static func actionKind(for suggestionType: String) -> TraiPulseAction.Kind {
        let suggestion = suggestionType.lowercased()

        if suggestion.contains("reminder") {
            return .completeReminder
        }
        if suggestion.contains("log_") || suggestion.contains("meal") || suggestion.contains("protein") {
            return .logFood
        }
        if suggestion.contains("recovery") {
            return .openRecovery
        }
        if suggestion.contains("review") {
            if suggestion.contains("workout") {
                return .reviewWorkoutPlan
            }
            return .reviewNutritionPlan
        }
        if suggestion.contains("plan") && suggestion.contains("workout") {
            return .reviewWorkoutPlan
        }
        if suggestion.contains("plan") {
            return .reviewNutritionPlan
        }
        if suggestion.contains("workout") || suggestion.contains("train") {
            return .startWorkout
        }
        if suggestion.contains("calorie") {
            return .openCalorieDetail
        }
        if suggestion.contains("macro") {
            return .openMacroDetail
        }
        if suggestion.contains("nutrition") {
            return .openProfile
        }
        if suggestion.contains("profile") || suggestion.contains("setting") {
            return .openProfile
        }
        return .openProfile
    }

    private static func actionKind(forBehaviorActionKey actionKey: String) -> TraiPulseAction.Kind? {
        switch actionKey {
        case BehaviorActionKey.logFood:
            return .logFood
        case BehaviorActionKey.logWeight:
            return .logWeight
        case BehaviorActionKey.startWorkout:
            return .startWorkout
        case BehaviorActionKey.completeReminder:
            return .completeReminder
        case BehaviorActionKey.openCalorieDetail:
            return .openCalorieDetail
        case BehaviorActionKey.openMacroDetail:
            return .openMacroDetail
        case BehaviorActionKey.openWeight:
            return .openWeight
        case BehaviorActionKey.openProfile:
            return .openProfile
        case BehaviorActionKey.openWorkouts:
            return .openWorkouts
        case BehaviorActionKey.openWorkoutPlan:
            return .openWorkoutPlan
        case BehaviorActionKey.openRecovery:
            return .openRecovery
        case BehaviorActionKey.reviewNutritionPlan:
            return .reviewNutritionPlan
        case BehaviorActionKey.reviewWorkoutPlan:
            return .reviewWorkoutPlan
        default:
            break
        }

        if actionKey.hasPrefix("engagement.pulse_action_tap.") {
            let suffix = String(actionKey.dropFirst("engagement.pulse_action_tap.".count))
            return TraiPulseAction.Kind(rawValue: suffix)
        }

        let normalized = actionKey.lowercased()
        if normalized.contains("workout") || normalized.contains("train") {
            return .startWorkout
        }
        if normalized.contains("weight") {
            return .logWeight
        }
        if normalized.contains("food") || normalized.contains("meal") || normalized.contains("protein") {
            return .logFood
        }
        if normalized.contains("reminder") {
            return .completeReminder
        }
        if normalized.contains("macro") {
            return .openMacroDetail
        }
        if normalized.contains("calorie") {
            return .openCalorieDetail
        }
        if normalized.contains("plan") {
            return normalized.contains("workout") ? .reviewWorkoutPlan : .reviewNutritionPlan
        }
        if normalized.contains("profile") {
            return .openProfile
        }
        return nil
    }

    private static func behaviorOutcomeWeight(_ outcome: BehaviorOutcome) -> Double {
        switch outcome {
        case .presented:
            return 0.12
        case .opened:
            return 0.35
        case .suggestedTap:
            return 0.70
        case .performed:
            return 1.0
        case .completed:
            return 1.15
        case .dismissed:
            return -0.40
        }
    }

    private static func isOpportunityOutcome(_ outcome: BehaviorOutcome) -> Bool {
        switch outcome {
        case .presented, .opened, .suggestedTap:
            return true
        case .performed, .completed, .dismissed:
            return false
        }
    }

    private static func isConversionOutcome(_ outcome: BehaviorOutcome) -> Bool {
        switch outcome {
        case .performed, .completed:
            return true
        case .presented, .opened, .suggestedTap, .dismissed:
            return false
        }
    }

    private static func topProteinAnchors(entries: [FoodEntry], proteinGoal: Int?) -> [String] {
        let threshold = max(20.0, Double(proteinGoal ?? 140) * 0.2)

        var stats: [String: (count: Int, proteinTotal: Double)] = [:]
        for entry in entries where entry.proteinGrams >= threshold {
            let key = normalizedMealName(entry.name)
            guard !key.isEmpty else { continue }
            let existing = stats[key] ?? (0, 0)
            stats[key] = (existing.count + 1, existing.proteinTotal + entry.proteinGrams)
        }

        return stats
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.value.proteinTotal > rhs.value.proteinTotal
            }
            .prefix(3)
            .map { titleCase($0.key) }
    }

    private static func normalizedMealName(_ raw: String) -> String {
        let lowercased = raw.lowercased()
        let allowed = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        let cleaned = String(allowed)
            .split(separator: " ")
            .filter { $0.count > 1 }
            .prefix(4)
            .map(String.init)
            .joined(separator: " ")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleCase(_ text: String) -> String {
        text
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func workoutWindow(forHour hour: Int) -> TraiPulseTimeWindow {
        switch hour {
        case 5..<8: .earlyMorning
        case 8..<11: .morning
        case 11..<14: .midday
        case 14..<17: .afternoon
        case 17..<21: .evening
        default: .lateNight
        }
    }

    private static func mealWindow(forHour hour: Int) -> TraiPulseTimeWindow {
        switch hour {
        case 5..<9: .earlyMorning
        case 9..<12: .morning
        case 12..<15: .midday
        case 15..<18: .afternoon
        case 18..<22: .evening
        default: .lateNight
        }
    }

    private static func normalizedScores(from counts: [TraiPulseTimeWindow: Int], total: Int) -> [String: Double] {
        guard total > 0 else { return [:] }

        var result: [String: Double] = [:]
        for window in TraiPulseTimeWindow.allCases {
            let value = Double(counts[window] ?? 0) / Double(total)
            if value > 0 {
                result[window.rawValue] = value
            }
        }
        return result
    }

    private static func combinedWorkoutDays(
        workouts: [WorkoutSession],
        liveWorkouts: [LiveWorkout],
        calendar: Calendar
    ) -> Set<Date> {
        var dates: Set<Date> = []

        for workout in workouts {
            dates.insert(calendar.startOfDay(for: workout.loggedAt))
        }

        for workout in liveWorkouts {
            dates.insert(calendar.startOfDay(for: workout.startedAt))
        }

        return dates
    }

    private static func daysSinceLastWorkout(workoutDays: Set<Date>, referenceDay: Date, calendar: Calendar) -> Int {
        guard let lastWorkoutDay = workoutDays.filter({ $0 <= referenceDay }).max() else {
            return 30
        }
        return max(calendar.dateComponents([.day], from: lastWorkoutDay, to: referenceDay).day ?? 0, 0)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
