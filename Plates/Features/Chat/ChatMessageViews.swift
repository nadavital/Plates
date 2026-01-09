//
//  ChatMessageViews.swift
//  Plates
//
//  Chat message bubble views, empty state, and loading indicator
//

import SwiftUI

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    var activity: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TraiLensView(size: 36, state: .thinking, palette: .energy)

            Text(activity ?? "Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.2), value: activity)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Empty Chat View

struct EmptyChatView: View {
    let onSuggestionTapped: (String) -> Void
    var isLoading: Bool = false
    var isTemporary: Bool = false

    private var lensState: TraiLensState {
        isLoading ? .thinking : .idle
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isTemporary {
                // Incognito mode content
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "text.bubble.badge.clock.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                }

                Text("Incognito Chat")
                    .font(.title2)
                    .bold()

                Text("This conversation won't be saved. Your messages will disappear when you leave incognito mode or switch chats.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 8) {
                    Label("Messages won't be saved", systemImage: "clock.badge.xmark")
                    Label("Memories won't be created", systemImage: "brain.head.profile.slash")
                    Label("Chat history stays private", systemImage: "lock.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                // Normal mode content
                TraiLensView(size: 100, state: lensState, palette: .energy)

                Text("Meet Trai")
                    .font(.title2)
                    .bold()

                Text("Your personal fitness coach. Ask me anything about nutrition, workouts, or your goals!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Try asking:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(ChatMessage.suggestedPrompts.prefix(4), id: \.title) { prompt in
                        Button {
                            onSuggestionTapped(prompt.prompt)
                        } label: {
                            HStack {
                                Text(prompt.title)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .padding()
            }

            Spacer()
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    var currentCalories: Int?
    var currentProtein: Int?
    var currentCarbs: Int?
    var currentFat: Int?
    var enabledMacros: Set<MacroType> = MacroType.defaultEnabled
    var onAcceptMeal: ((SuggestedFoodEntry) -> Void)?
    var onEditMeal: ((SuggestedFoodEntry) -> Void)?
    var onDismissMeal: (() -> Void)?
    var onViewLoggedMeal: ((UUID) -> Void)?
    var onAcceptPlan: ((PlanUpdateSuggestionEntry) -> Void)?
    var onEditPlan: ((PlanUpdateSuggestionEntry) -> Void)?
    var onDismissPlan: (() -> Void)?
    var onAcceptFoodEdit: ((SuggestedFoodEdit) -> Void)?
    var onDismissFoodEdit: (() -> Void)?
    var onAcceptWorkout: ((SuggestedWorkoutEntry) -> Void)?
    var onDismissWorkout: (() -> Void)?
    var onAcceptWorkoutLog: ((SuggestedWorkoutLog) -> Void)?
    var onDismissWorkoutLog: (() -> Void)?
    var useExerciseWeightLbs: Bool = false
    var onRetry: (() -> Void)?

    var body: some View {
        HStack {
            if message.isFromUser { Spacer() }

            if let error = message.errorMessage {
                ErrorBubble(error: error, onRetry: onRetry)
            } else if message.isFromUser {
                // User messages in a bubble
                VStack(alignment: .trailing, spacing: 8) {
                    // Show image if attached
                    if let imageData = message.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(.rect(cornerRadius: 12))
                    }

                    if !message.content.isEmpty {
                        Text(message.content)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: 16))
                    }
                }
            } else {
                // AI messages - no bubble, just formatted text
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(formattedParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .textSelection(.enabled)
                    }

                    // Show meal suggestion card if pending
                    if message.hasPendingMealSuggestion, let meal = message.suggestedMeal {
                        SuggestedMealCard(
                            meal: meal,
                            enabledMacros: enabledMacros,
                            onAccept: { onAcceptMeal?(meal) },
                            onEdit: { onEditMeal?(meal) },
                            onDismiss: { onDismissMeal?() }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }

                    // Show plan update suggestion card if pending
                    if message.hasPendingPlanSuggestion, let plan = message.suggestedPlan {
                        PlanUpdateSuggestionCard(
                            suggestion: plan,
                            currentCalories: currentCalories,
                            currentProtein: currentProtein,
                            currentCarbs: currentCarbs,
                            currentFat: currentFat,
                            enabledMacros: enabledMacros,
                            onAccept: { onAcceptPlan?(plan) },
                            onEdit: { onEditPlan?(plan) },
                            onDismiss: { onDismissPlan?() }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }

                    // Show logged meal indicator (after message content)
                    if let entryId = message.loggedFoodEntryId {
                        LoggedMealBadge(
                            meal: message.suggestedMeal,
                            foodEntryId: entryId,
                            onTap: { onViewLoggedMeal?(entryId) }
                        )
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Show food edit suggestion card if pending
                    if message.hasPendingFoodEdit, let edit = message.suggestedFoodEdit {
                        SuggestedEditCard(
                            edit: edit,
                            onAccept: { onAcceptFoodEdit?(edit) },
                            onDismiss: { onDismissFoodEdit?() }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }

                    // Show applied edit badge
                    if message.hasAppliedFoodEdit, let edit = message.suggestedFoodEdit {
                        AppliedEditBadge(edit: edit)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Show workout suggestion card if pending
                    if message.hasPendingWorkoutSuggestion, let workout = message.suggestedWorkout {
                        SuggestedWorkoutCard(
                            workout: workout,
                            onAccept: { onAcceptWorkout?(workout) },
                            onDismiss: { onDismissWorkout?() }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }

                    // Show workout started badge
                    if message.hasStartedWorkout, let workout = message.suggestedWorkout {
                        WorkoutStartedBadge(workoutName: workout.name)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Show workout log suggestion card if pending
                    if message.hasPendingWorkoutLogSuggestion, let workoutLog = message.suggestedWorkoutLog {
                        SuggestedWorkoutLogCard(
                            workoutLog: workoutLog,
                            useLbs: useExerciseWeightLbs,
                            onAccept: { onAcceptWorkoutLog?(workoutLog) },
                            onDismiss: { onDismissWorkoutLog?() }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }

                    // Show workout log saved badge
                    if message.hasSavedWorkoutLog, let workoutLog = message.suggestedWorkoutLog {
                        WorkoutLogSavedBadge(workoutType: workoutLog.displayName)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Show plan update applied indicator
                    if message.planUpdateApplied {
                        PlanUpdateAppliedBadge()
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Show memory saved indicator
                    if message.hasSavedMemories {
                        MemorySavedBadge(memories: message.savedMemories)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasPendingMealSuggestion)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasPendingPlanSuggestion)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.loggedFoodEntryId)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.planUpdateApplied)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasSavedMemories)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasPendingFoodEdit)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasAppliedFoodEdit)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasPendingWorkoutSuggestion)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasStartedWorkout)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasPendingWorkoutLogSuggestion)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasSavedWorkoutLog)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !message.isFromUser { Spacer() }
        }
    }

    /// Split content into paragraphs and format each one
    private var formattedParagraphs: [AttributedString] {
        let paragraphs = message.content.components(separatedBy: "\n\n")
        return paragraphs.compactMap { paragraph in
            let processed = processMarkdown(paragraph)
            if let attributed = try? AttributedString(markdown: processed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                return attributed
            }
            return AttributedString(paragraph)
        }
    }

    /// Convert block-level markdown to something more renderable
    private func processMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let processed = lines.map { line in
            if let range = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let headerText = line[range.upperBound...]
                return "**\(headerText)**"
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return "• " + String(line.dropFirst(2))
            }
            return line
        }
        return processed.joined(separator: "\n")
    }
}

// MARK: - Error Bubble

struct ErrorBubble: View {
    let error: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text("Something went wrong")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Suggested Workout Card

struct SuggestedWorkoutCard: View {
    let workout: SuggestedWorkoutEntry
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.accent)
                Text("Start Workout?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Workout details
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label("\(workout.exercises.count) exercises", systemImage: "list.bullet")
                    Label("\(workout.durationMinutes) min", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !workout.targetMuscleGroups.isEmpty {
                    Text(workout.muscleGroupsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !workout.rationale.isEmpty {
                    Text(workout.rationale)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))

            // Action buttons
            HStack(spacing: 12) {
                Button("Dismiss", systemImage: "xmark") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Start Workout", systemImage: "play.fill") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Started Badge

struct WorkoutStartedBadge: View {
    let workoutName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Started: \(workoutName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .clipShape(.capsule)
    }
}

// MARK: - Suggested Workout Log Card

struct SuggestedWorkoutLogCard: View {
    let workoutLog: SuggestedWorkoutLog
    var useLbs: Bool = false
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                    Text("Log this?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(.circle)
                }
            }

            // Workout name and summary
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutLog.displayName)
                    .font(.headline)

                HStack(spacing: 6) {
                    if !workoutLog.exercises.isEmpty {
                        Text("\(workoutLog.exercises.count) exercises")
                    }
                    if workoutLog.totalSets > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(workoutLog.totalSets) sets")
                    }
                    if let duration = workoutLog.durationMinutes, duration > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text("\(duration) min")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Exercise list with set rows
            if !workoutLog.exercises.isEmpty {
                VStack(spacing: 0) {
                    ForEach(workoutLog.exercises) { exercise in
                        WorkoutLogExerciseRow(exercise: exercise, useLbs: useLbs)
                        if exercise.id != workoutLog.exercises.last?.id {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.tertiarySystemBackground))
                .clipShape(.rect(cornerRadius: 10))
            }

            // Notes if any
            if let notes = workoutLog.notes, !notes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Action button
            Button {
                onAccept()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                    Text("Log Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Workout Log Exercise Row

private struct WorkoutLogExerciseRow: View {
    let exercise: SuggestedWorkoutLog.LoggedExercise
    let useLbs: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Exercise name
            Text(exercise.name)
                .font(.subheadline)
                .fontWeight(.medium)

            // Sets as rows (reps on left, weight on right)
            VStack(spacing: 4) {
                ForEach(exercise.sets.indices, id: \.self) { index in
                    let set = exercise.sets[index]
                    HStack {
                        Text("Set \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .leading)

                        Text("\(set.reps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let weight = set.weightKg, weight > 0 {
                            let displayWeight = useLbs ? Int(weight * 2.20462) : Int(weight)
                            let unit = useLbs ? "lbs" : "kg"
                            Text("\(displayWeight) \(unit)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Workout Log Saved Badge

struct WorkoutLogSavedBadge: View {
    let workoutType: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Logged: \(workoutType)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .clipShape(.capsule)
    }
}

