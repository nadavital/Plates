//
//  StableUUID.swift
//  Trai
//
//  Generates deterministic UUIDs from string identifiers.
//  Uses SHA256 for consistency across app launches (unlike Hasher which is randomly seeded).
//

import Foundation
import CryptoKit

enum StableUUID {
    /// Generate a stable, deterministic UUID from a string identifier.
    /// Uses SHA256 to ensure the same input always produces the same UUID.
    static func from(_ identifier: String) -> UUID {
        let data = Data(identifier.utf8)
        let hash = SHA256.hash(data: data)
        let hashBytes = Array(hash)

        // Use first 16 bytes of SHA256 hash to create UUID
        let uuidString = String(
            format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
            hashBytes[4], hashBytes[5],
            hashBytes[6], hashBytes[7],
            hashBytes[8], hashBytes[9],
            hashBytes[10], hashBytes[11], hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
        )

        return UUID(uuidString: uuidString) ?? UUID()
    }

    /// Generate a stable UUID for a meal reminder
    static func forMeal(_ mealId: String) -> UUID {
        from("MEAL-\(mealId)")
    }

    /// Generate a stable UUID for a workout reminder
    static func forWorkoutReminder() -> UUID {
        from("WORKOUT-REMINDER")
    }
}
