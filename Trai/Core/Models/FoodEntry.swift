import Foundation
import SwiftData

/// Represents a logged food item with nutritional information
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var name: String = ""

    /// Meal type: "breakfast", "lunch", "dinner", or "snack"
    /// Deprecated: Use sessionId for grouping instead
    var mealType: String = "snack"

    // Session-based grouping (replaces rigid meal types)
    /// Groups items logged together in the same session
    var sessionId: UUID?
    /// Order within the session (0-based)
    var sessionOrder: Int = 0
    /// How the food was logged: "manual", "camera", "photo", "description"
    var inputMethod: String = "manual"

    // Nutritional information
    var calories: Int = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double?
    var sugarGrams: Double?

    var servingSize: String?
    var servingQuantity: Double = 1.0

    /// Local storage key for image data (blob is stored on-device, not in CloudKit).
    var imageStorageKey: String?

    /// Legacy CloudKit-backed image blob. Keep `originalName` so existing rows that still
    /// persist `imageData` hydrate into this field and can migrate to local storage.
    @Attribute(.externalStorage, originalName: "imageData") private var legacyImageData: Data?

    /// Image data from photo taken of the food (local-only).
    @Transient
    var imageData: Data? {
        get {
            if let key = imageStorageKey,
               let data = LocalImageStore.shared.loadData(for: key) {
                return data
            }

            guard migrateLegacyImageToLocalStoreIfNeeded() else { return nil }
            return imageStorageKey.flatMap { LocalImageStore.shared.loadData(for: $0) }
        }
        set {
            guard let data = newValue, !data.isEmpty else {
                if let key = imageStorageKey {
                    LocalImageStore.shared.removeData(for: key)
                }
                imageStorageKey = nil
                legacyImageData = nil
                return
            }

            let key = imageStorageKey ?? localImageKey
            LocalImageStore.shared.storeData(data, for: key)
            imageStorageKey = key
            legacyImageData = nil
        }
    }

    /// User's text description of the food
    var userDescription: String?

    /// AI's analysis response (stored for reference)
    var aiAnalysis: String?

    /// Emoji representing the food (from AI suggestion)
    var emoji: String?

    /// Accepted structured snapshot for food-memory matching.
    var acceptedSnapshotData: Data?

    /// Denormalized component list for quick access without decoding the full snapshot.
    var acceptedComponentsData: Data?

    /// Immutable baseline of the originally accepted meal components for user-facing edits.
    var originalLoggedComponentsData: Data?

    /// Current editable meal composition. Parent macros are recalculated from this when present.
    var loggedComponentsData: Data?

    /// Linked canonical food-memory identifier once resolved.
    var foodMemoryIdString: String?
    var foodMemoryMatchConfidence: Double = 0
    var foodMemoryMatchVersion: Int = 0
    var foodMemoryResolutionStateRaw: String = FoodMemoryResolutionState.unresolved.rawValue
    var foodMemoryResolvedAt: Date?
    var foodMemoryNeedsResolution: Bool = false
    var foodMemoryWasUserEdited: Bool = false
    var foodMemoryResolutionExplanationData: Data?

    var loggedAt: Date = Date()

    init() {}

    init(
        name: String,
        mealType: String,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double
    ) {
        self.name = name
        self.mealType = mealType
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.emoji = FoodEmojiResolver.resolve(preferred: nil, foodName: name)
    }
}

// MARK: - Meal Type Helper

extension FoodEntry {
    enum MealType: String, CaseIterable, Identifiable {
        case breakfast = "breakfast"
        case lunch = "lunch"
        case dinner = "dinner"
        case snack = "snack"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .breakfast: "Breakfast"
            case .lunch: "Lunch"
            case .dinner: "Dinner"
            case .snack: "Snack"
            }
        }

        var iconName: String {
            switch self {
            case .breakfast: "sun.horizon.fill"
            case .lunch: "sun.max.fill"
            case .dinner: "moon.fill"
            case .snack: "carrot.fill"
            }
        }
    }

    var meal: MealType {
        get { MealType(rawValue: mealType) ?? .snack }
        set { mealType = newValue.rawValue }
    }
}

// MARK: - Input Method Helper

extension FoodEntry {
    enum InputMethod: String, CaseIterable, Identifiable {
        case manual = "manual"
        case camera = "camera"
        case photo = "photo"
        case description = "description"
        case memorySuggestion = "memorySuggestion"
        case chat = "chat"
        case appIntent = "appIntent"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .manual: "Manual Entry"
            case .camera: "Camera Capture"
            case .photo: "Photo Library"
            case .description: "Text Description"
            case .memorySuggestion: "Remembered Food"
            case .chat: "Chat Suggestion"
            case .appIntent: "App Intent"
            }
        }

        var iconName: String {
            switch self {
            case .manual: "square.and.pencil"
            case .camera: "camera.fill"
            case .photo: "photo.fill"
            case .description: "text.bubble.fill"
            case .memorySuggestion: "sparkles.rectangle.stack.fill"
            case .chat: "message.fill"
            case .appIntent: "sparkles"
            }
        }
    }

    var input: InputMethod {
        get { InputMethod(rawValue: inputMethod) ?? .manual }
        set { inputMethod = newValue.rawValue }
    }
}

// MARK: - Computed Properties

extension FoodEntry {
    private static let snapshotEncoder = JSONEncoder()
    private static let snapshotDecoder = JSONDecoder()

    private var localImageKey: String {
        "food-\(id.uuidString.lowercased())"
    }

    /// Make sure all entries have a persisted emoji for image-less rendering on other devices.
    func ensureDisplayMetadata() {
        emoji = FoodEmojiResolver.resolve(preferred: emoji, foodName: name)
    }

    @discardableResult
    func migrateLegacyImageToLocalStoreIfNeeded() -> Bool {
        guard let legacyImageData, !legacyImageData.isEmpty else { return false }
        let key = imageStorageKey ?? localImageKey
        LocalImageStore.shared.storeData(legacyImageData, for: key)
        imageStorageKey = key
        self.legacyImageData = nil
        return true
    }

    /// Display emoji with fallback to fork and knife
    var displayEmoji: String {
        FoodEmojiResolver.resolve(preferred: emoji, foodName: name)
    }

    var acceptedSnapshot: AcceptedFoodSnapshot? {
        get {
            guard let acceptedSnapshotData else { return nil }
            return try? Self.snapshotDecoder.decode(AcceptedFoodSnapshot.self, from: acceptedSnapshotData)
        }
        set {
            if let newValue {
                acceptedSnapshotData = try? Self.snapshotEncoder.encode(newValue)
            } else {
                acceptedSnapshotData = nil
            }
        }
    }

    var acceptedComponents: [AcceptedFoodComponent] {
        get {
            if let acceptedComponentsData {
                return (try? Self.snapshotDecoder.decode([AcceptedFoodComponent].self, from: acceptedComponentsData)) ?? []
            }
            return acceptedSnapshot?.components ?? []
        }
        set {
            acceptedComponentsData = newValue.isEmpty ? nil : (try? Self.snapshotEncoder.encode(newValue))
        }
    }

    var originalLoggedComponents: [LoggedFoodComponent] {
        get {
            guard let originalLoggedComponentsData else { return [] }
            return (try? Self.snapshotDecoder.decode([LoggedFoodComponent].self, from: originalLoggedComponentsData)) ?? []
        }
        set {
            originalLoggedComponentsData = newValue.isEmpty ? nil : (try? Self.snapshotEncoder.encode(newValue))
        }
    }

    var loggedComponents: [LoggedFoodComponent] {
        get {
            guard let loggedComponentsData else { return [] }
            return (try? Self.snapshotDecoder.decode([LoggedFoodComponent].self, from: loggedComponentsData)) ?? []
        }
        set {
            loggedComponentsData = newValue.isEmpty ? nil : (try? Self.snapshotEncoder.encode(newValue))
        }
    }

    var activeLoggedComponents: [LoggedFoodComponent] {
        loggedComponents.filter(\.isActive)
    }

    var foodMemoryResolutionState: FoodMemoryResolutionState {
        get { FoodMemoryResolutionState(rawValue: foodMemoryResolutionStateRaw) ?? .unresolved }
        set { foodMemoryResolutionStateRaw = newValue.rawValue }
    }

    var foodMemoryResolutionExplanation: FoodMemoryMatchExplanation? {
        get {
            guard let foodMemoryResolutionExplanationData else { return nil }
            return try? Self.snapshotDecoder.decode(FoodMemoryMatchExplanation.self, from: foodMemoryResolutionExplanationData)
        }
        set {
            if let newValue {
                foodMemoryResolutionExplanationData = try? Self.snapshotEncoder.encode(newValue)
            } else {
                foodMemoryResolutionExplanationData = nil
            }
        }
    }

    func setAcceptedSnapshot(_ snapshot: AcceptedFoodSnapshot, matchVersion: Int = 0) {
        acceptedSnapshot = snapshot
        acceptedComponentsData = nil
        foodMemoryNeedsResolution = true
        foodMemoryWasUserEdited = snapshot.wasUserEdited
        foodMemoryMatchVersion = matchVersion
        foodMemoryIdString = nil
        foodMemoryMatchConfidence = 0
        foodMemoryResolvedAt = nil
        foodMemoryResolutionState = .queued
        foodMemoryResolutionExplanation = nil
    }

    func bootstrapLoggedComponentsIfNeeded(from snapshot: AcceptedFoodSnapshot? = nil) {
        let baseline: [LoggedFoodComponent]
        if let snapshot {
            baseline = snapshot.components.map(LoggedFoodComponent.init(component:))
        } else if let acceptedSnapshot {
            baseline = acceptedSnapshot.components.map(LoggedFoodComponent.init(component:))
        } else if !acceptedComponents.isEmpty {
            baseline = acceptedComponents.map(LoggedFoodComponent.init(component:))
        } else {
            baseline = [derivedLoggedComponent()]
        }

        if originalLoggedComponents.isEmpty {
            originalLoggedComponents = baseline
        }
        if loggedComponents.isEmpty {
            loggedComponents = originalLoggedComponents.isEmpty ? baseline : originalLoggedComponents
        }
    }

    func recalculateNutritionFromLoggedComponents() {
        bootstrapLoggedComponentsIfNeeded()

        let activeComponents = activeLoggedComponents
        guard !activeComponents.isEmpty else {
            calories = 0
            proteinGrams = 0
            carbsGrams = 0
            fatGrams = 0
            fiberGrams = nil
            sugarGrams = nil
            return
        }

        calories = Int(activeComponents.reduce(0.0) { $0 + $1.effectiveCalories }.rounded())
        proteinGrams = activeComponents.reduce(0.0) { $0 + $1.effectiveProteinGrams }
        carbsGrams = activeComponents.reduce(0.0) { $0 + $1.effectiveCarbsGrams }
        fatGrams = activeComponents.reduce(0.0) { $0 + $1.effectiveFatGrams }

        let fiberTotal = activeComponents.reduce(0.0) { partialResult, component in
            partialResult + (component.effectiveFiberGrams ?? 0)
        }
        fiberGrams = fiberTotal > 0 ? fiberTotal : nil

        let sugarTotal = activeComponents.reduce(0.0) { partialResult, component in
            partialResult + (component.effectiveSugarGrams ?? 0)
        }
        sugarGrams = sugarTotal > 0 ? sugarTotal : nil
    }

    func replaceLoggedComponentsWithDerivedCurrentTotals() {
        loggedComponents = [derivedLoggedComponent()]
    }

    private func derivedLoggedComponent() -> LoggedFoodComponent {
        let normalizedName = FoodNormalizationService().normalizeFoodName(name)
        return LoggedFoodComponent(
            id: normalizedName.isEmpty ? id.uuidString.lowercased() : normalizedName,
            originalComponentID: normalizedName.isEmpty ? id.uuidString.lowercased() : normalizedName,
            displayName: name,
            normalizedName: normalizedName,
            role: .other,
            quantity: servingQuantity > 0 ? servingQuantity : nil,
            unit: nil,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            sugarGrams: sugarGrams,
            preparation: nil,
            confidence: nil,
            source: .derived
        )
    }

    /// Total macros in grams
    var totalMacroGrams: Double {
        proteinGrams + carbsGrams + fatGrams
    }

    /// Protein percentage of total calories
    var proteinPercentage: Double {
        guard calories > 0 else { return 0 }
        return (proteinGrams * 4 / Double(calories)) * 100
    }

    /// Carbs percentage of total calories
    var carbsPercentage: Double {
        guard calories > 0 else { return 0 }
        return (carbsGrams * 4 / Double(calories)) * 100
    }

    /// Fat percentage of total calories
    var fatPercentage: Double {
        guard calories > 0 else { return 0 }
        return (fatGrams * 9 / Double(calories)) * 100
    }
}
