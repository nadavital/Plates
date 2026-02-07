//
//  ChatMessageViews.swift
//  Trai
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

// MARK: - Smart Starter Context

struct SmartStarterContext {
    let userName: String
    let todayFoodCount: Int
    let todayCalories: Int
    let calorieGoal: Int
    let todayProtein: Int
    let proteinGoal: Int
    let lastWorkoutDate: Date?
    let hasActiveWorkout: Bool
    let goalType: String
    let hour: Int

    init(
        userName: String = "",
        todayFoodCount: Int = 0,
        todayCalories: Int = 0,
        calorieGoal: Int = 2000,
        todayProtein: Int = 0,
        proteinGoal: Int = 150,
        lastWorkoutDate: Date? = nil,
        hasActiveWorkout: Bool = false,
        goalType: String = "maintenance"
    ) {
        self.userName = userName
        self.todayFoodCount = todayFoodCount
        self.todayCalories = todayCalories
        self.calorieGoal = calorieGoal
        self.todayProtein = todayProtein
        self.proteinGoal = proteinGoal
        self.lastWorkoutDate = lastWorkoutDate
        self.hasActiveWorkout = hasActiveWorkout
        self.goalType = goalType
        self.hour = Calendar.current.component(.hour, from: Date())
    }

    var daysSinceLastWorkout: Int? {
        guard let lastWorkout = lastWorkoutDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day
    }

    var caloriesRemaining: Int {
        max(0, calorieGoal - todayCalories)
    }

    var proteinRemaining: Int {
        max(0, proteinGoal - todayProtein)
    }

    var mealPeriod: String {
        switch hour {
        case 5..<11: return "breakfast"
        case 11..<14: return "lunch"
        case 14..<17: return "snack"
        case 17..<21: return "dinner"
        default: return "snack"
        }
    }

    var timeOfDayGreeting: String {
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }

    var firstName: String {
        userName.components(separatedBy: " ").first ?? ""
    }

    /// Generate a personalized greeting based on context
    func generateGreeting() -> String {
        let greetings: [String]

        // Use first name if available
        let namePrefix = firstName.isEmpty ? "" : "\(firstName), "

        switch hour {
        case 5..<9:
            // Early morning
            if todayFoodCount == 0 {
                greetings = [
                    "\(namePrefix)rise and shine! ☀️",
                    "Good morning\(firstName.isEmpty ? "" : ", \(firstName)")! Ready to fuel up?",
                    "\(namePrefix)let's start the day strong 💪"
                ]
            } else {
                greetings = [
                    "Good morning\(firstName.isEmpty ? "" : ", \(firstName)")!",
                    "\(namePrefix)how's your morning going?"
                ]
            }
        case 9..<12:
            // Late morning
            if let days = daysSinceLastWorkout, days >= 2 {
                greetings = [
                    "\(namePrefix)ready to get after it today? 🔥",
                    "\(namePrefix)feeling strong today?",
                    "Hey\(firstName.isEmpty ? "" : " \(firstName)")! Time to crush it?"
                ]
            } else {
                greetings = [
                    "Hey\(firstName.isEmpty ? "" : " \(firstName)")! What's on your mind?",
                    "\(namePrefix)how can I help today?"
                ]
            }
        case 12..<14:
            // Lunch time
            greetings = [
                "\(namePrefix)lunch time! 🍽️",
                "Hey\(firstName.isEmpty ? "" : " \(firstName)")! Hungry?",
                "\(namePrefix)what are we having for lunch?"
            ]
        case 14..<17:
            // Afternoon
            if proteinRemaining > 0 && proteinRemaining <= 50 {
                greetings = [
                    "\(namePrefix)closing in on that protein goal! 💪",
                    "\(namePrefix)\(proteinRemaining)g protein to go!",
                    "Afternoon\(firstName.isEmpty ? "" : ", \(firstName)")! Let's finish strong"
                ]
            } else {
                greetings = [
                    "Hey\(firstName.isEmpty ? "" : " \(firstName)")! How's the day going?",
                    "\(namePrefix)what's up?",
                    "Afternoon\(firstName.isEmpty ? "" : ", \(firstName)")!"
                ]
            }
        case 17..<21:
            // Evening
            if goalType == "lose_weight" || goalType == "cut" {
                greetings = [
                    "\(namePrefix)staying on track! 🎯",
                    "Evening\(firstName.isEmpty ? "" : ", \(firstName)")! How's the cut going?",
                    "\(namePrefix)\(caloriesRemaining) cal left for dinner"
                ]
            } else {
                greetings = [
                    "Evening\(firstName.isEmpty ? "" : ", \(firstName)")!",
                    "\(namePrefix)how was your day?",
                    "Hey\(firstName.isEmpty ? "" : " \(firstName)")! Dinner time?"
                ]
            }
        default:
            // Night
            greetings = [
                "Hey\(firstName.isEmpty ? "" : " \(firstName)")!",
                "\(namePrefix)burning the midnight oil?",
                "Late night\(firstName.isEmpty ? "" : ", \(firstName)")?"
            ]
        }

        // Pick a consistent greeting based on the day (so it doesn't change on every render)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return greetings[dayOfYear % greetings.count]
    }
}

// MARK: - Smart Starter

struct SmartStarter: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let icon: String
    let title: String
    let prompt: String
    let color: Color
    var score: Int = 0
    var isContextual: Bool = false

    static func == (lhs: SmartStarter, rhs: SmartStarter) -> Bool {
        lhs.id == rhs.id
    }

    /// Generate suggestions sorted by personalization score
    static func generate(from context: SmartStarterContext, usage: [SuggestionUsage] = []) -> [SmartStarter] {
        var starters = generateAll(from: context)

        // Calculate scores for each starter
        for i in starters.indices {
            let usageData = usage.first { $0.suggestionType == starters[i].type }
            starters[i].score = calculateScore(
                starter: starters[i],
                usage: usageData,
                context: context
            )
        }

        // Sort by score descending
        return starters.sorted { $0.score > $1.score }
    }

    /// Generate all available suggestions
    private static func generateAll(from context: SmartStarterContext) -> [SmartStarter] {
        var starters: [SmartStarter] = []

        // Time-based meal suggestions (contextual - high base score)
        if context.todayFoodCount == 0 && context.hour >= 6 && context.hour < 11 {
            starters.append(SmartStarter(
                type: SuggestionType.logBreakfast,
                icon: "sun.horizon.fill",
                title: "Log breakfast",
                prompt: "I want to log my breakfast",
                color: .orange,
                isContextual: true
            ))
        }
        if context.hour >= 11 && context.hour < 14 {
            starters.append(SmartStarter(
                type: SuggestionType.logLunch,
                icon: "fork.knife",
                title: "Log lunch",
                prompt: "I want to log my lunch",
                color: .green,
                isContextual: true
            ))
        }
        if context.hour >= 17 && context.hour < 21 {
            starters.append(SmartStarter(
                type: SuggestionType.logDinner,
                icon: "moon.stars.fill",
                title: "Log dinner",
                prompt: "I want to log my dinner",
                color: .indigo,
                isContextual: true
            ))
        }

        // Protein tracking (contextual)
        if context.proteinRemaining > 0 && context.proteinRemaining <= 50 {
            starters.append(SmartStarter(
                type: SuggestionType.proteinToGo,
                icon: "bolt.fill",
                title: "\(context.proteinRemaining)g protein to go",
                prompt: "I need \(context.proteinRemaining)g more protein today. What are some quick high-protein options?",
                color: .red,
                isContextual: true
            ))
        }

        // Workout suggestions (contextual)
        if let daysSince = context.daysSinceLastWorkout, daysSince >= 2 {
            starters.append(SmartStarter(
                type: SuggestionType.timeTrain,
                icon: "figure.run",
                title: "Time to train?",
                prompt: "What should I work out today based on my recovery?",
                color: .blue,
                isContextual: true
            ))
        }

        // Always available actions
        starters.append(SmartStarter(
            type: SuggestionType.startWorkout,
            icon: "dumbbell.fill",
            title: "Start workout",
            prompt: "Help me start a workout",
            color: .blue
        ))

        starters.append(SmartStarter(
            type: SuggestionType.snapMeal,
            icon: "camera.fill",
            title: "Snap a meal",
            prompt: "I want to log a meal with a photo",
            color: .mint
        ))

        starters.append(SmartStarter(
            type: SuggestionType.checkProgress,
            icon: "chart.line.uptrend.xyaxis",
            title: "My progress",
            prompt: "How am I doing with my goals this week?",
            color: .purple
        ))

        starters.append(SmartStarter(
            type: SuggestionType.checkRecovery,
            icon: "heart.circle.fill",
            title: "Muscle recovery",
            prompt: "Show me my muscle recovery status",
            color: .pink
        ))

        starters.append(SmartStarter(
            type: SuggestionType.onTrack,
            icon: "checkmark.circle.fill",
            title: "Am I on track?",
            prompt: "Am I on track with my nutrition today?",
            color: .teal
        ))

        // Questions and advice
        starters.append(SmartStarter(
            type: SuggestionType.mealIdeas,
            icon: "lightbulb.fill",
            title: "Meal ideas",
            prompt: "Give me some healthy meal ideas for \(context.mealPeriod)",
            color: .yellow
        ))

        starters.append(SmartStarter(
            type: SuggestionType.healthySnacks,
            icon: "leaf.fill",
            title: "Healthy snacks",
            prompt: "Suggest some healthy high-protein snacks",
            color: .green
        ))

        starters.append(SmartStarter(
            type: SuggestionType.logWeight,
            icon: "scalemass.fill",
            title: "Log my weight",
            prompt: "I want to log my weight",
            color: .orange
        ))

        starters.append(SmartStarter(
            type: SuggestionType.reviewPlan,
            icon: "doc.text.fill",
            title: "Review my plan",
            prompt: "Can you review my nutrition plan?",
            color: .cyan
        ))

        starters.append(SmartStarter(
            type: SuggestionType.caloriesLeft,
            icon: "flame.fill",
            title: "Calories left?",
            prompt: "How many calories do I have left today?",
            color: .orange
        ))

        starters.append(SmartStarter(
            type: SuggestionType.myPRs,
            icon: "trophy.fill",
            title: "My PRs",
            prompt: "What are my recent personal records?",
            color: .yellow
        ))

        starters.append(SmartStarter(
            type: SuggestionType.restDayTips,
            icon: "bed.double.fill",
            title: "Rest day tips",
            prompt: "Any tips for my rest day?",
            color: .indigo
        ))

        starters.append(SmartStarter(
            type: SuggestionType.waterIntake,
            icon: "drop.fill",
            title: "Water intake",
            prompt: "How much water should I drink today?",
            color: .cyan
        ))

        starters.append(SmartStarter(
            type: SuggestionType.dailyActivity,
            icon: "figure.walk",
            title: "Daily activity",
            prompt: "How active have I been today?",
            color: .green
        ))

        return starters
    }

    /// Calculate personalization score for a starter
    private static func calculateScore(starter: SmartStarter, usage: SuggestionUsage?, context: SmartStarterContext) -> Int {
        var score = 0

        // Contextual relevance bonus
        if starter.isContextual {
            score += 20
        }

        // Usage frequency (log scale to prevent runaway favorites)
        if let usage {
            score += min(usage.tapCount, 50) // Cap at 50 points

            // Time match: +30 if user usually taps this at current hour
            if usage.tapsAt(hour: context.hour) >= 3 {
                score += 30
            }

            // Recency: +10 if tapped in last 7 days
            if let last = usage.lastTapped,
               Date().timeIntervalSince(last) < 7 * 24 * 3600 {
                score += 10
            }
        }

        return score
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: 160, height: 60)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty Chat View

struct EmptyChatView: View {
    var isLoading: Bool = false
    var isTemporary: Bool = false
    var context: SmartStarterContext = SmartStarterContext()

    private var lensState: TraiLensState {
        isLoading ? .thinking : .idle
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            if isTemporary {
                incognitoContent
                    .transition(.opacity)
            } else {
                greetingContent
                    .transition(.opacity)
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: isTemporary)
    }

    // MARK: - Incognito Content

    private var incognitoContent: some View {
        VStack(spacing: 20) {
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
                Label("Memories won't be created", systemImage: "lightbulb.slash")
                Label("Chat history stays private", systemImage: "lock.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    // MARK: - Greeting Content

    private var greetingContent: some View {
        VStack(spacing: 20) {
            TraiLensView(size: 100, state: lensState, palette: .energy)

            Text(context.generateGreeting())
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.horizontal)
    }
}

// MARK: - Suggestion Rows View

/// Horizontally scrolling suggestion rows for the empty chat state
struct SuggestionRowsView: View {
    let context: SmartStarterContext
    let suggestionUsage: [SuggestionUsage]
    let onSuggestionTapped: (String) -> Void
    var onTrackTap: ((String) -> Void)?

    private var allStarters: [SmartStarter] {
        SmartStarter.generate(from: context, usage: suggestionUsage)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Row 1: first half of suggestions (independently scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allStarters.prefix(allStarters.count / 2)) { starter in
                        SuggestionCard(
                            icon: starter.icon,
                            title: starter.title,
                            color: starter.color
                        ) {
                            onTrackTap?(starter.type)
                            onSuggestionTapped(starter.prompt)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Row 2: second half of suggestions (independently scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allStarters.suffix(allStarters.count - allStarters.count / 2)) { starter in
                        SuggestionCard(
                            icon: starter.icon,
                            title: starter.title,
                            color: starter.color
                        ) {
                            onTrackTap?(starter.type)
                            onSuggestionTapped(starter.prompt)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
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
    var isMealLogging: ((SuggestedFoodEntry) -> Bool)? = nil
    var onEditMeal: ((SuggestedFoodEntry) -> Void)?
    var onDismissMeal: ((SuggestedFoodEntry) -> Void)?
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
    var onAcceptReminder: ((SuggestedReminder) -> Void)?
    var onEditReminder: ((SuggestedReminder) -> Void)?
    var onDismissReminder: (() -> Void)?
    var useExerciseWeightLbs: Bool = false
    var onRetry: (() -> Void)?
    var onImageTapped: ((UIImage) -> Void)?
    var onViewAppliedPlan: ((PlanUpdateSuggestionEntry) -> Void)?

    var body: some View {
        HStack {
            if message.isFromUser { Spacer() }

            if let error = message.errorMessage {
                ErrorBubble(error: error, wasManuallyStopped: message.wasManuallyStopped, onRetry: onRetry)
            } else if message.isFromUser {
                // User messages in a bubble
                VStack(alignment: .trailing, spacing: 8) {
                    // Show image if attached (tappable to enlarge)
                    if let imageData = message.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Button {
                            onImageTapped?(uiImage)
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 200, maxHeight: 200)
                                .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
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

                    // Show meal suggestion cards for all pending meals
                    ForEach(message.pendingMealSuggestions, id: \.meal.id) { _, meal in
                        SuggestedMealCard(
                            meal: meal,
                            enabledMacros: enabledMacros,
                            isLogging: isMealLogging?(meal) ?? false,
                            onAccept: { onAcceptMeal?(meal) },
                            onEdit: { onEditMeal?(meal) },
                            onDismiss: { onDismissMeal?(meal) }
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

                    // Show logged meal badges for all logged meals
                    ForEach(message.loggedMealSuggestions, id: \.meal.id) { _, meal in
                        if let entryId = message.foodEntryId(for: meal.id) {
                            LoggedMealBadge(
                                meal: meal,
                                foodEntryId: entryId,
                                onTap: { onViewLoggedMeal?(entryId) }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
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

                    // Show reminder suggestion card if pending
                    if message.hasPendingReminderSuggestion, let reminder = message.suggestedReminder {
                        ReminderSuggestionCard(
                            suggestion: reminder,
                            onConfirm: { onAcceptReminder?(reminder) },
                            onEdit: { onEditReminder?(reminder) },
                            onDismiss: { onDismissReminder?() }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.95).combined(with: .opacity)
                        ))
                    }

                    // Show reminder created badge
                    if message.hasCreatedReminder, let reminder = message.suggestedReminder {
                        CreatedReminderChip(suggestion: reminder)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Show plan update applied indicator (tappable to view details)
                    if message.planUpdateApplied, let plan = message.suggestedPlan {
                        PlanUpdateAppliedBadge(plan: plan) {
                            onViewAppliedPlan?(plan)
                        }
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
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasPendingReminderSuggestion)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.hasCreatedReminder)
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
    var wasManuallyStopped: Bool = false
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

            // Only show retry button if not manually stopped by user
            if let onRetry, !wasManuallyStopped {
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
