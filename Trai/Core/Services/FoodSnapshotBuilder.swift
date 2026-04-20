import Foundation

struct FoodSnapshotBuilder {
    private let normalizationService = FoodNormalizationService()
    private let snapshotVersion = 2

    func buildAcceptedSnapshot(
        from suggestion: SuggestedFoodEntry,
        source: AcceptedFoodSource,
        loggedAt: Date,
        mealLabel: String? = nil,
        userEditedFields: Set<String> = []
    ) -> AcceptedFoodSnapshot {
        let components = acceptedComponents(from: suggestion)
        let inferredKind = inferKind(mealKind: suggestion.mealKind, componentCount: components.count)
        let serving = normalizationService.normalizeServing(
            quantity: nil,
            unit: nil,
            text: suggestion.servingSize
        )

        return AcceptedFoodSnapshot(
            version: snapshotVersion,
            source: source,
            kind: inferredKind,
            displayName: suggestion.name,
            emoji: suggestion.emoji,
            normalizedDisplayName: normalizationService.normalizeFoodName(suggestion.name),
            nameAliases: normalizationService.aliasCandidates(for: suggestion.name),
            mealLabel: mealLabel,
            servingText: suggestion.servingSize,
            servingQuantity: serving.quantity,
            servingUnit: serving.unit,
            totalCalories: suggestion.calories,
            totalProteinGrams: suggestion.proteinGrams,
            totalCarbsGrams: suggestion.carbsGrams,
            totalFatGrams: suggestion.fatGrams,
            totalFiberGrams: suggestion.fiberGrams,
            totalSugarGrams: suggestion.sugarGrams,
            components: components,
            notes: suggestion.notes,
            confidence: normalizationService.confidence(from: suggestion.confidence),
            loggedAt: loggedAt,
            mealTimeBucket: normalizationService.mealTimeBucket(for: loggedAt),
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: Array(userEditedFields).sorted(),
            wasUserEdited: !userEditedFields.isEmpty
        )
    }

    func buildAcceptedSnapshot(
        from analysis: FoodAnalysis,
        source: AcceptedFoodSource,
        loggedAt: Date,
        mealLabel: String? = nil,
        userEditedFields: Set<String> = []
    ) -> AcceptedFoodSnapshot {
        let components = acceptedComponents(from: analysis)
        let inferredKind = inferKind(mealKind: analysis.mealKind, componentCount: components.count)
        let serving = normalizationService.normalizeServing(
            quantity: nil,
            unit: nil,
            text: analysis.servingSize
        )

        return AcceptedFoodSnapshot(
            version: snapshotVersion,
            source: source,
            kind: inferredKind,
            displayName: analysis.name,
            emoji: analysis.emoji,
            normalizedDisplayName: normalizationService.normalizeFoodName(analysis.name),
            nameAliases: normalizationService.aliasCandidates(for: analysis.name),
            mealLabel: mealLabel,
            servingText: analysis.servingSize,
            servingQuantity: serving.quantity,
            servingUnit: serving.unit,
            totalCalories: analysis.calories,
            totalProteinGrams: analysis.proteinGrams,
            totalCarbsGrams: analysis.carbsGrams,
            totalFatGrams: analysis.fatGrams,
            totalFiberGrams: analysis.fiberGrams,
            totalSugarGrams: analysis.sugarGrams,
            components: components,
            notes: analysis.notes,
            confidence: normalizationService.confidence(from: analysis.confidence),
            loggedAt: loggedAt,
            mealTimeBucket: normalizationService.mealTimeBucket(for: loggedAt),
            weekdayBucket: Calendar.current.component(.weekday, from: loggedAt),
            userEditedFields: Array(userEditedFields).sorted(),
            wasUserEdited: !userEditedFields.isEmpty
        )
    }

    func buildAcceptedSnapshot(
        from entry: FoodEntry,
        source: AcceptedFoodSource,
        userEditedFields: Set<String> = []
    ) -> AcceptedFoodSnapshot {
        entry.bootstrapLoggedComponentsIfNeeded()
        let normalizedName = normalizationService.normalizeFoodName(entry.name)
        let serving = normalizationService.normalizeServing(
            quantity: entry.servingQuantity > 0 ? entry.servingQuantity : nil,
            unit: nil,
            text: entry.servingSize
        )
        let components = acceptedComponents(from: entry)
        let inferredKind = components.count > 1 ? FoodMemoryKind.meal : .food

        return AcceptedFoodSnapshot(
            version: snapshotVersion,
            source: source,
            kind: inferredKind,
            displayName: entry.name,
            emoji: entry.emoji,
            normalizedDisplayName: normalizedName,
            nameAliases: normalizationService.aliasCandidates(for: entry.name),
            mealLabel: entry.mealType,
            servingText: entry.servingSize,
            servingQuantity: serving.quantity,
            servingUnit: serving.unit,
            totalCalories: entry.calories,
            totalProteinGrams: entry.proteinGrams,
            totalCarbsGrams: entry.carbsGrams,
            totalFatGrams: entry.fatGrams,
            totalFiberGrams: entry.fiberGrams,
            totalSugarGrams: entry.sugarGrams,
            components: components,
            notes: entry.aiAnalysis,
            confidence: nil,
            loggedAt: entry.loggedAt,
            mealTimeBucket: normalizationService.mealTimeBucket(for: entry.loggedAt),
            weekdayBucket: Calendar.current.component(.weekday, from: entry.loggedAt),
            userEditedFields: Array(userEditedFields).sorted(),
            wasUserEdited: !userEditedFields.isEmpty
        )
    }

    private func inferKind(mealKind: String?, componentCount: Int) -> FoodMemoryKind {
        if mealKind?.lowercased() == "meal" || componentCount > 1 {
            return .meal
        }
        return .food
    }

    private func acceptedComponents(from suggestion: SuggestedFoodEntry) -> [AcceptedFoodComponent] {
        if suggestion.components.isEmpty {
            return [derivedComponent(
                displayName: suggestion.name,
                calories: suggestion.calories,
                proteinGrams: suggestion.proteinGrams,
                carbsGrams: suggestion.carbsGrams,
                fatGrams: suggestion.fatGrams,
                fiberGrams: suggestion.fiberGrams,
                sugarGrams: suggestion.sugarGrams
            )]
        }

        return suggestion.components.map { component in
            let normalizedName = normalizationService.normalizeFoodName(component.displayName)
            return AcceptedFoodComponent(
                id: component.id,
                displayName: component.displayName,
                normalizedName: normalizedName,
                role: normalizationService.componentRole(from: component.role),
                quantity: component.quantity,
                unit: component.unit,
                calories: component.calories,
                proteinGrams: component.proteinGrams,
                carbsGrams: component.carbsGrams,
                fatGrams: component.fatGrams,
                fiberGrams: component.fiberGrams,
                sugarGrams: component.sugarGrams,
                preparation: nil,
                confidence: normalizationService.confidence(from: component.confidence),
                source: .ai
            )
        }
    }

    private func acceptedComponents(from analysis: FoodAnalysis) -> [AcceptedFoodComponent] {
        guard let components = analysis.components, !components.isEmpty else {
            return [derivedComponent(
                displayName: analysis.name,
                calories: analysis.calories,
                proteinGrams: analysis.proteinGrams,
                carbsGrams: analysis.carbsGrams,
                fatGrams: analysis.fatGrams,
                fiberGrams: analysis.fiberGrams,
                sugarGrams: analysis.sugarGrams
            )]
        }

        return components.map { component in
            let normalizedName = normalizationService.normalizeFoodName(component.displayName)
            return AcceptedFoodComponent(
                id: component.id ?? UUID().uuidString,
                displayName: component.displayName,
                normalizedName: normalizedName,
                role: normalizationService.componentRole(from: component.role),
                quantity: component.quantity,
                unit: component.unit,
                calories: component.calories,
                proteinGrams: component.proteinGrams,
                carbsGrams: component.carbsGrams,
                fatGrams: component.fatGrams,
                fiberGrams: component.fiberGrams,
                sugarGrams: component.sugarGrams,
                preparation: nil,
                confidence: normalizationService.confidence(from: component.confidence),
                source: .ai
            )
        }
    }

    private func derivedComponent(
        displayName: String,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double?,
        sugarGrams: Double?
    ) -> AcceptedFoodComponent {
        let normalizedName = normalizationService.normalizeFoodName(displayName)
        return AcceptedFoodComponent(
            id: normalizedName.isEmpty ? UUID().uuidString : normalizedName,
            displayName: displayName,
            normalizedName: normalizedName,
            role: .other,
            quantity: nil,
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

    private func acceptedComponents(from entry: FoodEntry) -> [AcceptedFoodComponent] {
        let activeComponents = entry.activeLoggedComponents
        guard !activeComponents.isEmpty else {
            return [derivedComponent(
                displayName: entry.name,
                calories: entry.calories,
                proteinGrams: entry.proteinGrams,
                carbsGrams: entry.carbsGrams,
                fatGrams: entry.fatGrams,
                fiberGrams: entry.fiberGrams,
                sugarGrams: entry.sugarGrams
            )]
        }

        return activeComponents.map { component in
            AcceptedFoodComponent(
                id: component.id,
                displayName: component.displayName,
                normalizedName: component.normalizedName,
                role: component.role,
                quantity: component.quantity,
                unit: component.unit,
                calories: Int(component.effectiveCalories.rounded()),
                proteinGrams: component.effectiveProteinGrams,
                carbsGrams: component.effectiveCarbsGrams,
                fatGrams: component.effectiveFatGrams,
                fiberGrams: component.effectiveFiberGrams,
                sugarGrams: component.effectiveSugarGrams,
                preparation: component.preparation,
                confidence: component.confidence,
                source: component.source
            )
        }
    }
}
