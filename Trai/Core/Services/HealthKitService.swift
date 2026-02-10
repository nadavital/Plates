//
//  HealthKitService.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import Foundation
import HealthKit

/// Service for interacting with HealthKit
@MainActor @Observable
final class HealthKitService {
    private let healthStore = HKHealthStore()

    struct ActivitySummary: Sendable {
        let steps: Int
        let activeCalories: Int
        let exerciseMinutes: Int
    }

    var isAuthorized = false
    var authorizationError: String?

    // Heart rate streaming
    var currentHeartRate: Double?
    var lastHeartRateUpdate: Date?
    private var lastWatchHeartRateUpdate: Date?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var heartRateAnchor: HKQueryAnchor?

    // Active calories streaming (during workout)
    var workoutCalories: Double = 0
    var lastCalorieUpdate: Date?
    private var lastWatchCalorieUpdate: Date?
    private var calorieQuery: HKAnchoredObjectQuery?
    private var calorieAnchor: HKQueryAnchor?
    private var workoutStartTime: Date?
    private var hasSeenWatchSamples = false

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .leanBodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            authorizationError = nil
        } catch {
            isAuthorized = false
            authorizationError = error.localizedDescription
            throw error
        }
    }

    func ensureAuthorization() async throws {
        guard !isAuthorized else { return }
        try await requestAuthorization()
    }

    func runAuthorized<T>(_ operation: () async throws -> T) async throws -> T {
        try await ensureAuthorization()
        return try await operation()
    }

    // MARK: - App Policy Helpers

    func fetchTodayActivitySummaryAuthorized() async throws -> ActivitySummary {
        try await runAuthorized {
            async let steps = fetchTodayStepCount()
            async let calories = fetchTodayActiveEnergy()
            async let exercise = fetchTodayExerciseMinutes()

            let (fetchedSteps, fetchedCalories, fetchedExercise) = try await (steps, calories, exercise)
            return ActivitySummary(
                steps: fetchedSteps,
                activeCalories: fetchedCalories,
                exerciseMinutes: fetchedExercise
            )
        }
    }

    func fetchWeightEntriesAuthorized(from startDate: Date, to endDate: Date) async throws -> [WeightEntry] {
        try await runAuthorized {
            try await fetchWeightEntries(from: startDate, to: endDate)
        }
    }

    func saveWeightAuthorized(_ weightKg: Double, date: Date) async throws {
        try await runAuthorized {
            try await saveWeight(weightKg, date: date)
        }
    }

    func fetchWorkoutsAuthorized(from startDate: Date, to endDate: Date) async throws -> [WorkoutSession] {
        try await runAuthorized {
            try await fetchWorkouts(from: startDate, to: endDate)
        }
    }

    func saveDietaryEnergyAuthorized(_ calories: Double, date: Date) async throws {
        try await runAuthorized {
            try await saveDietaryEnergy(calories, date: date)
        }
    }

    func bestOverlappingWorkout(
        for workout: LiveWorkout,
        from healthKitWorkouts: [WorkoutSession],
        searchBufferMinutes: Int = 0
    ) -> WorkoutSession? {
        let buffer = Double(searchBufferMinutes) * 60
        let ourStart = workout.startedAt.addingTimeInterval(-buffer)
        let ourEnd = (workout.completedAt ?? Date()).addingTimeInterval(buffer)

        let overlapping = healthKitWorkouts.filter { hkWorkout in
            let hkStart = hkWorkout.loggedAt
            let hkEnd = healthKitEndDate(for: hkWorkout)
            return hkStart <= ourEnd && hkEnd >= ourStart
        }

        let strengthWorkouts = overlapping.filter {
            $0.healthKitWorkoutType?.lowercased().contains("strength") == true ||
            $0.healthKitWorkoutType?.lowercased().contains("weight") == true
        }

        return strengthWorkouts.first ?? overlapping.first
    }

    // MARK: - Weight

    func fetchWeightEntries(from startDate: Date, to endDate: Date) async throws -> [WeightEntry] {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let samples = try await fetchSamples(type: weightType, from: startDate, to: endDate)

        return samples.map { sample in
            let entry = WeightEntry()
            entry.weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            entry.loggedAt = sample.startDate
            entry.sourceIsHealthKit = true
            entry.healthKitSampleID = sample.uuid.uuidString
            return entry
        }
    }

    func saveWeight(_ weightKg: Double, date: Date) async throws {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let weightQuantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg)
        let sample = HKQuantitySample(type: weightType, quantity: weightQuantity, start: date, end: date)
        try await healthStore.save(sample)
    }

    // MARK: - Body Composition

    func fetchBodyFatPercentage(from startDate: Date, to endDate: Date) async throws -> [(date: Date, percentage: Double)] {
        let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
        let samples = try await fetchSamples(type: bodyFatType, from: startDate, to: endDate)
        return samples.map { (date: $0.startDate, percentage: $0.quantity.doubleValue(for: .percent()) * 100) }
    }

    func fetchLeanBodyMass(from startDate: Date, to endDate: Date) async throws -> [(date: Date, massKg: Double)] {
        let leanMassType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass)!
        let samples = try await fetchSamples(type: leanMassType, from: startDate, to: endDate)
        return samples.map { (date: $0.startDate, massKg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    // MARK: - Workouts

    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [WorkoutSession] {
        // Don't use strictStartDate - we want any workout that overlaps with the time range
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sessions = (samples as? [HKWorkout])?.map { workout -> WorkoutSession in
                    let session = WorkoutSession()
                    session.healthKitWorkoutID = workout.uuid.uuidString
                    session.healthKitWorkoutType = workout.workoutActivityType.name
                    session.exerciseName = workout.workoutActivityType.name
                    session.durationMinutes = workout.duration / 60
                    session.loggedAt = workout.startDate
                    session.sourceIsHealthKit = true

                    if let energy = workout.totalEnergyBurned {
                        session.caloriesBurned = Int(energy.doubleValue(for: .kilocalorie()))
                    }
                    if let distance = workout.totalDistance {
                        session.distanceMeters = distance.doubleValue(for: .meter())
                    }
                    return session
                } ?? []

                continuation.resume(returning: sessions)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch workouts for merging - uses a wider time window to catch overlapping workouts
    func fetchWorkoutsForMerge(around date: Date, windowMinutes: Int = 30) async throws -> [WorkoutSession] {
        // Expand the search window to catch workouts that started before or ended after
        let startDate = date.addingTimeInterval(-Double(windowMinutes) * 60)
        let endDate = date.addingTimeInterval(Double(windowMinutes) * 60)
        return try await fetchWorkouts(from: startDate, to: endDate)
    }

    /// Save a completed workout to HealthKit
    func saveWorkout(
        type: HKWorkoutActivityType,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        totalEnergyBurned: Double? = nil,
        metadata: [String: Any]? = nil
    ) async throws -> HKWorkout {
        // Create workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .indoor

        // Build the workout
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        try await builder.beginCollection(at: startDate)

        // Add energy burned sample if provided
        if let calories = totalEnergyBurned, calories > 0 {
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            let energySample = HKQuantitySample(
                type: energyType,
                quantity: energyQuantity,
                start: startDate,
                end: endDate
            )
            try await builder.addSamples([energySample])
        }

        try await builder.endCollection(at: endDate)

        // Finalize with metadata
        let finalMetadata = metadata ?? [:]
        let workout = try await builder.finishWorkout()

        return workout!
    }

    /// Save a LiveWorkout to HealthKit
    func saveLiveWorkout(_ workout: LiveWorkout) async throws {
        guard let completedAt = workout.completedAt else { return }

        // Map workout type to HealthKit activity type
        let activityType: HKWorkoutActivityType
        switch workout.type {
        case .strength:
            activityType = .traditionalStrengthTraining
        case .cardio:
            activityType = .mixedCardio
        case .mixed:
            activityType = .functionalStrengthTraining
        }

        // Calculate estimated calories (rough estimate based on duration and intensity)
        let durationMinutes = workout.duration / 60
        let estimatedCalories = durationMinutes * 5.0 // ~5 cal/min for strength training

        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "Trai",
            "workout_name": workout.name,
            "muscle_groups": workout.muscleGroups.map(\.rawValue).joined(separator: ","),
            "total_volume_kg": workout.totalVolume,
            "total_sets": workout.totalSets
        ]

        _ = try await saveWorkout(
            type: activityType,
            startDate: workout.startedAt,
            endDate: completedAt,
            duration: workout.duration,
            totalEnergyBurned: estimatedCalories,
            metadata: metadata
        )
    }

    // MARK: - Nutrition

    func saveDietaryEnergy(_ calories: Double, date: Date) async throws {
        let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(type: energyType, quantity: energyQuantity, start: date, end: date)
        try await healthStore.save(sample)
    }

    /// Save all macros from a food entry to HealthKit
    func saveFoodMacros(
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double?,
        sugarGrams: Double?,
        date: Date
    ) async throws {
        var samples: [HKQuantitySample] = []

        // Calories
        if calories > 0 {
            let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
            let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories))
            samples.append(HKQuantitySample(type: energyType, quantity: energyQuantity, start: date, end: date))
        }

        // Protein
        if proteinGrams > 0 {
            let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!
            let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: proteinGrams)
            samples.append(HKQuantitySample(type: proteinType, quantity: proteinQuantity, start: date, end: date))
        }

        // Carbs
        if carbsGrams > 0 {
            let carbsType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!
            let carbsQuantity = HKQuantity(unit: .gram(), doubleValue: carbsGrams)
            samples.append(HKQuantitySample(type: carbsType, quantity: carbsQuantity, start: date, end: date))
        }

        // Fat
        if fatGrams > 0 {
            let fatType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!
            let fatQuantity = HKQuantity(unit: .gram(), doubleValue: fatGrams)
            samples.append(HKQuantitySample(type: fatType, quantity: fatQuantity, start: date, end: date))
        }

        // Fiber (optional)
        if let fiber = fiberGrams, fiber > 0 {
            let fiberType = HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!
            let fiberQuantity = HKQuantity(unit: .gram(), doubleValue: fiber)
            samples.append(HKQuantitySample(type: fiberType, quantity: fiberQuantity, start: date, end: date))
        }

        // Sugar (optional)
        if let sugar = sugarGrams, sugar > 0 {
            let sugarType = HKQuantityType.quantityType(forIdentifier: .dietarySugar)!
            let sugarQuantity = HKQuantity(unit: .gram(), doubleValue: sugar)
            samples.append(HKQuantitySample(type: sugarType, quantity: sugarQuantity, start: date, end: date))
        }

        // Save all samples at once
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
    }

    // MARK: - Activity

    func fetchTodayStepCount() async throws -> Int {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        return try await fetchTodaySum(type: stepType, unit: .count())
    }

    func fetchTodayActiveEnergy() async throws -> Int {
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        return try await fetchTodaySum(type: energyType, unit: .kilocalorie())
    }

    func fetchTodayExerciseMinutes() async throws -> Int {
        let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
        return try await fetchTodaySum(type: exerciseType, unit: .minute())
    }

    // MARK: - Heart Rate Streaming

    /// Start streaming heart rate updates from Apple Watch
    /// Uses HKAnchoredObjectQuery to receive updates as they sync from Watch
    func startHeartRateStreaming(from workoutStart: Date? = nil) {
        guard isHealthKitAvailable else { return }

        // Stop any existing query
        stopHeartRateStreaming()
        heartRateAnchor = nil

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        // Include a short pre-workout buffer to catch already-running Watch workouts.
        // Clamp to a 2-hour window to avoid unnecessarily broad scans.
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        let requestedStart = workoutStart?.addingTimeInterval(-20 * 60) ?? Date().addingTimeInterval(-3600)
        let startDate = max(twoHoursAgo, requestedStart)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            Task { @MainActor in
                if let error {
                    print("Heart rate query error: \(error.localizedDescription)")
                    return
                }
                self?.heartRateAnchor = newAnchor
                self?.processHeartRateSamples(samples)
            }
        }

        // Update handler for continuous monitoring
        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            Task { @MainActor in
                if let error {
                    print("Heart rate update error: \(error.localizedDescription)")
                    return
                }
                self?.heartRateAnchor = newAnchor
                self?.processHeartRateSamples(samples)
            }
        }

        heartRateQuery = query
        healthStore.execute(query)
    }

    /// Stop streaming heart rate updates
    func stopHeartRateStreaming() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        heartRateAnchor = nil
        currentHeartRate = nil
        lastHeartRateUpdate = nil
        lastWatchHeartRateUpdate = nil
        hasSeenWatchSamples = false
    }

    /// Get the most recent heart rate from the last few minutes (one-time fetch)
    func fetchRecentHeartRate() async -> (bpm: Double, date: Date)? {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        // Look back 5 minutes
        let startDate = Date().addingTimeInterval(-300)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: (bpm: bpm, date: sample.startDate))
            }
            self.healthStore.execute(query)
        }
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let allHeartRateSamples = samples as? [HKQuantitySample], !allHeartRateSamples.isEmpty else {
            return
        }

        let watchHeartRateSamples = allHeartRateSamples.filter { isLikelyFromAppleWatch($0) }
        if !watchHeartRateSamples.isEmpty {
            hasSeenWatchSamples = true
        }
        let heartRateSamples = watchHeartRateSamples.isEmpty ? allHeartRateSamples : watchHeartRateSamples
        guard let mostRecent = heartRateSamples.max(by: { $0.startDate < $1.startDate }) else { return }

        let bpm = mostRecent.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        currentHeartRate = bpm
        lastHeartRateUpdate = mostRecent.startDate
        if isLikelyFromAppleWatch(mostRecent) {
            lastWatchHeartRateUpdate = mostRecent.startDate
        }
    }

    // MARK: - Calorie Streaming

    /// Start streaming active energy (calories) from Apple Watch during workout
    /// Tracks cumulative calories since workout start time
    func startCalorieStreaming(from startTime: Date) {
        guard isHealthKitAvailable else { return }

        // Stop any existing query
        stopCalorieStreaming()

        workoutStartTime = startTime
        workoutCalories = 0

        let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        // Only look at calories since workout started
        let predicate = HKQuery.predicateForSamples(withStart: startTime, end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: calorieType,
            predicate: predicate,
            anchor: calorieAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            Task { @MainActor in
                if let error {
                    print("Calorie query error: \(error.localizedDescription)")
                    return
                }
                self?.calorieAnchor = newAnchor
                self?.processCalorieSamples(samples)
            }
        }

        // Update handler for continuous monitoring
        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            Task { @MainActor in
                if let error {
                    print("Calorie update error: \(error.localizedDescription)")
                    return
                }
                self?.calorieAnchor = newAnchor
                self?.processCalorieSamples(samples)
            }
        }

        calorieQuery = query
        healthStore.execute(query)
    }

    /// Stop streaming calorie updates
    func stopCalorieStreaming() {
        if let query = calorieQuery {
            healthStore.stop(query)
            calorieQuery = nil
        }
        calorieAnchor = nil
        workoutStartTime = nil
        lastWatchCalorieUpdate = nil
        // Don't reset workoutCalories - keep final value for summary
    }

    private func processCalorieSamples(_ samples: [HKSample]?) {
        guard let allCalorieSamples = samples as? [HKQuantitySample], !allCalorieSamples.isEmpty else {
            return
        }

        let watchCalorieSamples = allCalorieSamples.filter { isLikelyFromAppleWatch($0) }
        if !watchCalorieSamples.isEmpty {
            hasSeenWatchSamples = true
        }
        let calorieSamples = watchCalorieSamples.isEmpty ? allCalorieSamples : watchCalorieSamples

        // Sum all new calorie samples
        let newCalories = calorieSamples.reduce(0.0) { total, sample in
            total + sample.quantity.doubleValue(for: .kilocalorie())
        }

        workoutCalories += newCalories

        if let mostRecent = calorieSamples.max(by: { $0.endDate < $1.endDate }) {
            lastCalorieUpdate = mostRecent.endDate
            if isLikelyFromAppleWatch(mostRecent) {
                lastWatchCalorieUpdate = mostRecent.endDate
            }
        }
    }

    /// Check if we're receiving data from Apple Watch (either heart rate or calories)
    var isWatchConnected: Bool {
        // Consider connected if we've received any data in the last 30 seconds
        let threshold: TimeInterval = 30
        let now = Date()

        if hasSeenWatchSamples {
            if let hrUpdate = lastWatchHeartRateUpdate, now.timeIntervalSince(hrUpdate) < threshold {
                return true
            }
            if let calUpdate = lastWatchCalorieUpdate, now.timeIntervalSince(calUpdate) < threshold {
                return true
            }
            return false
        }

        // Fallback when HealthKit does not expose Watch device metadata.
        if let hrUpdate = lastHeartRateUpdate, now.timeIntervalSince(hrUpdate) < threshold {
            return true
        }
        if let calUpdate = lastCalorieUpdate, now.timeIntervalSince(calUpdate) < threshold {
            return true
        }
        return false
    }

    // MARK: - Private Helpers

    private func fetchSamples(type: HKQuantityType, from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodaySum(type: HKQuantityType, unit: HKUnit) async throws -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                // Return 0 if no data or error (common when no activity recorded yet)
                if error != nil || statistics == nil {
                    continuation.resume(returning: 0)
                } else {
                    let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                    continuation.resume(returning: Int(value))
                }
            }
            healthStore.execute(query)
        }
    }

    private func isLikelyFromAppleWatch(_ sample: HKSample) -> Bool {
        if let productType = sample.sourceRevision.productType?.lowercased(), productType.hasPrefix("watch") {
            return true
        }
        if let model = sample.device?.model?.lowercased(), model.contains("watch") {
            return true
        }
        if let name = sample.device?.name?.lowercased(), name.contains("watch") {
            return true
        }
        return false
    }

    private func healthKitEndDate(for workout: WorkoutSession) -> Date {
        guard let duration = workout.durationMinutes, duration > 0 else {
            return workout.loggedAt.addingTimeInterval(60 * 60)
        }
        return workout.loggedAt.addingTimeInterval(duration * 60)
    }
}
