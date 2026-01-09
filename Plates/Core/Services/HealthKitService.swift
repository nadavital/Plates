//
//  HealthKitService.swift
//  Plates
//
//  Created by Nadav Avital on 12/25/25.
//

import Foundation
import HealthKit

/// Service for interacting with HealthKit
@MainActor @Observable
final class HealthKitService {
    private let healthStore = HKHealthStore()

    var isAuthorized = false
    var authorizationError: String?

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
            HKObjectType.workoutType()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        ]

        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        isAuthorized = true
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

    // MARK: - Nutrition

    func saveDietaryEnergy(_ calories: Double, date: Date) async throws {
        let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(type: energyType, quantity: energyQuantity, start: date, end: date)
        try await healthStore.save(sample)
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
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                    continuation.resume(returning: Int(value))
                }
            }
            healthStore.execute(query)
        }
    }
}
