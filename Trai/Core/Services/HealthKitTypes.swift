//
//  HealthKitTypes.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import Foundation
import HealthKit

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access has not been authorized"
        }
    }
}

// MARK: - Workout Activity Type Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .americanFootball: return "American Football"
        case .archery: return "Archery"
        case .australianFootball: return "Australian Football"
        case .badminton: return "Badminton"
        case .barre: return "Barre"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .cardioDance: return "Cardio Dance"
        case .climbing: return "Climbing"
        case .cricket: return "Cricket"
        case .crossCountrySkiing: return "Cross-Country Skiing"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .discSports: return "Disc Sports"
        case .downhillSkiing: return "Downhill Skiing"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .fitnessGaming: return "Fitness Gaming"
        case .flexibility: return "Flexibility"
        case .functionalStrengthTraining: return "Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handCycling: return "Hand Cycling"
        case .handball: return "Handball"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind and Body"
        case .mixedCardio: return "Mixed Cardio"
        case .paddleSports: return "Paddle Sports"
        case .pickleball: return "Pickleball"
        case .play: return "Play"
        case .preparationAndRecovery: return "Recovery"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining: return "Weight Training"
        case .coreTraining: return "Core Training"
        case .pilates: return "Pilates"
        case .racquetball: return "Racquetball"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .sailing: return "Sailing"
        case .skatingSports: return "Skating"
        case .snowboarding: return "Snowboarding"
        case .snowSports: return "Snow Sports"
        case .soccer: return "Soccer"
        case .socialDance: return "Social Dance"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairs: return "Stairs"
        case .stairClimbing: return "Stair Climbing"
        case .stepTraining: return "Step Training"
        case .surfingSports: return "Surfing"
        case .swimBikeRun: return "Swim Bike Run"
        case .tableTennis: return "Table Tennis"
        case .taiChi: return "Tai Chi"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track and Field"
        case .transition: return "Transition"
        case .underwaterDiving: return "Underwater Diving"
        case .volleyball: return "Volleyball"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wheelchairRunPace: return "Wheelchair Run"
        case .wheelchairWalkPace: return "Wheelchair Walk"
        case .wrestling: return "Wrestling"
        case .cooldown: return "Cooldown"
        case .dance, .danceInspiredTraining: return "Dance"
        case .mixedMetabolicCardioTraining: return "Mixed Cardio"
        case .other: return "Other Workout"
        default: return "Workout"
        }
    }
}
