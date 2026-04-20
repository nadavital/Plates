//
//  FoodLogDraft.swift
//  Trai
//
//  Internal draft state for the food logging flow
//

import Foundation
import UIKit

enum FoodLogInputSource: String {
    case camera
    case photo
    case description
    case manual
    case memorySuggestion

    var foodEntryInputMethod: FoodEntry.InputMethod {
        switch self {
        case .camera:
            return .camera
        case .photo:
            return .photo
        case .description:
            return .description
        case .manual:
            return .manual
        case .memorySuggestion:
            return .memorySuggestion
        }
    }

    var behaviorSource: String {
        switch self {
        case .memorySuggestion:
            return "memory_suggestion"
        default:
            return rawValue
        }
    }
}

struct FoodLogDraft {
    var sessionId: UUID?
    var memorySuggestionID: UUID?
    var shownSuggestionIDs: [UUID]
    var image: UIImage?
    var description: String
    var inputSource: FoodLogInputSource
    var analysisResult: FoodAnalysis?
    var refinedSuggestion: SuggestedFoodEntry?

    init(
        sessionId: UUID? = nil,
        image: UIImage? = nil,
        description: String = "",
        inputSource: FoodLogInputSource
    ) {
        self.sessionId = sessionId
        self.memorySuggestionID = nil
        self.shownSuggestionIDs = []
        self.image = image
        self.description = description
        self.inputSource = inputSource
        self.analysisResult = nil
        self.refinedSuggestion = nil
    }
}
