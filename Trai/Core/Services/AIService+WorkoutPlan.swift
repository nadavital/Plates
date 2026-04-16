//
//  AIService+WorkoutPlan.swift
//  Trai
//
//  Workout plan generation and refinement
//

import Foundation
import os

extension AIService {

    // MARK: - Workout Plan Refinement Response

    struct WorkoutPlanRefinementResponse {
        let responseType: ResponseType
        let message: String
        let proposedPlan: WorkoutPlan?
        let updatedPlan: WorkoutPlan?

        enum ResponseType: String {
            case message
            case proposePlan
            case planUpdate
        }
    }

    // MARK: - Workout Plan Generation

    /// Generate a personalized workout plan
    func generateWorkoutPlan(request: WorkoutPlanGenerationRequest) async throws -> WorkoutPlan {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        let requestTicket = try beginAIRequest(for: .workoutPlanGeneration)

        log("🏋️ Starting workout plan generation for: \(request.name)", type: .info)
        log("📊 User data - Age: \(request.age), Goal: \(request.goal.rawValue)", type: .info)
        log("🎯 Workout prefs - Days: \(request.availableDays.map { "\($0)" } ?? "flexible"), Experience: \(request.experienceLevel?.rawValue ?? "unspecified"), Equipment: \(request.equipmentAccess?.rawValue ?? "unspecified")", type: .info)

        let prompt = AIPromptBuilder.buildWorkoutPlanGenerationPrompt(request: request)
        logPrompt(prompt)

        do {
            let plan: WorkoutPlan = try await executePlanGenerationPipeline(
                prompt: prompt,
                schema: AIPromptBuilder.workoutPlanSchema,
                decodeFailureLabel: "workout plan"
            )
            completeAIRequest(requestTicket)
            log("✅ Successfully parsed workout plan - Split: \(plan.splitType.displayName), Templates: \(plan.templates.count)", type: .info)
            return plan
        } catch AIServiceError.parsingError {
            cancelAIRequest(requestTicket)
            log("Falling back to default workout plan after parse failure", type: .error)
            return WorkoutPlan.createDefault(from: request)
        } catch {
            cancelAIRequest(requestTicket)
            log("Failed to generate workout plan: \(error.localizedDescription)", type: .error)
            throw error
        }
    }

    // MARK: - Workout Plan Refinement (Chat)

    /// Refine/discuss the workout plan through chat
    func refineWorkoutPlan(
        currentPlan: WorkoutPlan,
        request: WorkoutPlanGenerationRequest,
        userMessage: String,
        conversationHistory: [WorkoutPlanChatMessage]
    ) async throws -> WorkoutPlanRefinementResponse {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        return try await performAIRequest(for: .workoutPlanRefinement) {
            log("💬 Workout plan refinement request: \(userMessage)", type: .info)

            let prompt = AIPromptBuilder.buildWorkoutPlanRefinementPrompt(
                currentPlan: currentPlan,
                request: request,
                userMessage: userMessage,
                conversationHistory: conversationHistory
            )
            logPrompt(prompt)

            do {
                let envelope: PlanPipelineRefinementEnvelope<WorkoutPlan> = try await executePlanRefinementPipeline(
                    prompt: prompt,
                    schema: AIPromptBuilder.workoutPlanRefinementSchema
                )

                let responseType = WorkoutPlanRefinementResponse.ResponseType(rawValue: envelope.responseType) ?? .message
                return WorkoutPlanRefinementResponse(
                    responseType: responseType,
                    message: envelope.message,
                    proposedPlan: envelope.proposedPlan,
                    updatedPlan: envelope.updatedPlan
                )
            } catch {
                log("Failed to refine workout plan: \(error.localizedDescription)", type: .error)
                throw error
            }
        }
    }
}
