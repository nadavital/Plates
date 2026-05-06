import Foundation

struct FoodObservation: Identifiable, Sendable, Equatable {
    let id: UUID
    let entryID: UUID
    let linkedMemoryID: UUID?
    let displayName: String
    let normalizedName: String
    let emoji: String?
    let kind: FoodMemoryKind
    let source: AcceptedFoodSource
    let inputMethod: FoodEntry.InputMethod
    let loggedAt: Date
    let sessionID: UUID?
    let sessionOrder: Int
    let servingText: String?
    let servingQuantity: Double?
    let servingUnit: String?
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let components: [FoodObservationComponent]
    let wasUserEdited: Bool
    let userEditedFields: Set<String>
}

struct FoodObservationComponent: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let displayName: String
    let normalizedName: String
    let canonicalName: String
    let role: FoodComponentRole
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double?
    let sugarGrams: Double?
    let source: FoodComponentSource
}

struct FoodObservationBuilder {
    private let normalizationService = FoodNormalizationService()

    func observations(from entries: [FoodEntry]) -> [FoodObservation] {
        entries.compactMap(observation(from:)).sorted {
            if $0.loggedAt != $1.loggedAt {
                return $0.loggedAt < $1.loggedAt
            }
            return $0.sessionOrder < $1.sessionOrder
        }
    }

    func observation(from entry: FoodEntry) -> FoodObservation? {
        guard let snapshot = entry.acceptedSnapshot else { return nil }
        let linkedMemoryID = entry.foodMemoryIdString.flatMap(UUID.init(uuidString:))
        let normalizedName = snapshot.normalizedDisplayName.isEmpty
            ? normalizationService.normalizeFoodName(snapshot.displayName)
            : snapshot.normalizedDisplayName
        let components = snapshot.components.map { component in
            FoodObservationComponent(
                id: component.id,
                displayName: component.displayName,
                normalizedName: component.normalizedName,
                canonicalName: normalizationService.normalizeComponentName(component.displayName),
                role: component.role,
                calories: component.calories,
                proteinGrams: component.proteinGrams,
                carbsGrams: component.carbsGrams,
                fatGrams: component.fatGrams,
                fiberGrams: component.fiberGrams,
                sugarGrams: component.sugarGrams,
                source: component.source
            )
        }

        return FoodObservation(
            id: entry.id,
            entryID: entry.id,
            linkedMemoryID: linkedMemoryID,
            displayName: snapshot.displayName,
            normalizedName: normalizedName,
            emoji: snapshot.emoji ?? entry.emoji,
            kind: snapshot.kind,
            source: snapshot.source,
            inputMethod: entry.input,
            loggedAt: snapshot.loggedAt,
            sessionID: entry.sessionId,
            sessionOrder: entry.sessionOrder,
            servingText: snapshot.servingText,
            servingQuantity: snapshot.servingQuantity,
            servingUnit: snapshot.servingUnit,
            calories: snapshot.totalCalories,
            proteinGrams: snapshot.totalProteinGrams,
            carbsGrams: snapshot.totalCarbsGrams,
            fatGrams: snapshot.totalFatGrams,
            fiberGrams: snapshot.totalFiberGrams,
            sugarGrams: snapshot.totalSugarGrams,
            components: components,
            wasUserEdited: snapshot.wasUserEdited,
            userEditedFields: Set(snapshot.userEditedFields)
        )
    }
}
