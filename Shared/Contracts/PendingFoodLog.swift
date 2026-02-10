//
//  PendingFoodLog.swift
//  Shared
//
//  Widget quick-log payload shared between app and widget extension.
//

import Foundation

struct PendingFoodLog: Codable {
    let name: String
    let calories: Int
    let protein: Int
    let loggedAt: Date
    let mealType: String
}
