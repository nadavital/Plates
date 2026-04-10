//
//  ProfileView.swift
//  Trai
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    let onSelectTab: ((AppTab) -> Void)?
    @Query var profiles: [UserProfile]
    @Query private var activeWorkouts: [LiveWorkout]
    @Query private var historicalWorkouts: [WorkoutSession]
    @Query private var loggedFoodEntries: [FoodEntry]
    @Query private var loggedChatMessages: [ChatMessage]
    @Query private var todaysWorkouts: [WorkoutSession]

    @Environment(\.appTabSelection) private var appTabSelection
    @Environment(\.modelContext) var modelContext
    @Environment(AccountSessionService.self) private var accountSessionService: AccountSessionService?
    @Environment(MonetizationService.self) private var monetizationService: MonetizationService?
    @Environment(ProUpsellCoordinator.self) var proUpsellCoordinator: ProUpsellCoordinator?
    @State var showPlanSheet = false
    @State var showSettingsSheet = false
    @State var customRemindersCount = 0

    // Workout plan management sheets
    @State var showPlanSetupSheet = false
    @State var showPlanEditSheet = false
    @State private var lastOpenTrackedAt: Date?
    @State private var latestWeightKg: Double?
    @State private var activeMemoriesCount = 0
    @State private var chatConversationCount = 0
    @State private var profileMetricsRefreshTask: Task<Void, Never>?
    @State private var remindersCountTask: Task<Void, Never>?
    @State private var hasPendingProfileMetricsRefresh = false
    @State private var hasPendingRemindersCountRefresh = false
    @State private var hasExecutedInitialHeavyRefresh = false
    @State private var isProfileTabVisible = false
    @State private var latencyProbeEntries: [String] = []
    @State private var tabActivationPolicy = TabActivationPolicy(minimumDwellMilliseconds: 0)
    @State private var presentedAccountSetupContext: AccountSetupContext?

    // For navigating to Trai tab with plan review
    @AppStorage("pendingPlanReviewRequest") var pendingPlanReviewRequest = false
    @AppStorage("pendingWorkoutPlanReviewRequest") var pendingWorkoutPlanReviewRequest = false
    @AppStorage("profile_cached_latest_weight_kg") private var cachedLatestWeightKg: Double = -1
    @AppStorage("profile_cached_active_memories_count") private var cachedActiveMemoriesCount = 0
    @AppStorage("profile_cached_chat_conversation_count") private var cachedChatConversationCount = 0
    @AppStorage("profile_cached_custom_reminders_count") private var cachedCustomRemindersCount = 0
    @AppStorage("profile_cached_owner_id") private var cachedOwnerProfileID = ""
    @AppStorage("profile_metrics_last_refresh_at") private var profileMetricsLastRefreshAt: Double = 0
    @AppStorage("profile_reminders_last_refresh_at") private var remindersCountLastRefreshAt: Double = 0
    @AppStorage("account_setup_prompt_last_dismissed_at") private var accountSetupPromptLastDismissedAt: Double = 0
    private static let profileChatWindowDays = 90
    private static let profileMetricsStaleAfterSeconds: Double = 24 * 60 * 60
    private static let profileRemindersStaleAfterSeconds: Double = 24 * 60 * 60
    private static let accountSetupPromptCooldownSeconds: Double = 14 * 24 * 60 * 60
    private static var profileHeavyMetricsDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 4200 : 420
    }
    private static var profileReactivationHeavyDelayMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 5200 : 540
    }
    private static var profileHeavyRefreshMinimumDwellMilliseconds: Int {
        AppLaunchArguments.shouldAggressivelyDeferHeavyTabWork ? 2200 : 320
    }

    init(onSelectTab: ((AppTab) -> Void)? = nil) {
        self.onSelectTab = onSelectTab
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)

        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        _profiles = Query(profileDescriptor)

        var activeWorkoutDescriptor = FetchDescriptor<LiveWorkout>(
            predicate: #Predicate<LiveWorkout> { workout in
                workout.completedAt == nil
            }
        )
        activeWorkoutDescriptor.fetchLimit = 1
        _activeWorkouts = Query(activeWorkoutDescriptor)

        var historicalWorkoutDescriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        historicalWorkoutDescriptor.fetchLimit = 1
        _historicalWorkouts = Query(historicalWorkoutDescriptor)

        var foodEntriesDescriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\FoodEntry.loggedAt, order: .reverse)]
        )
        foodEntriesDescriptor.fetchLimit = 1
        _loggedFoodEntries = Query(foodEntriesDescriptor)

        var chatMessagesDescriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\ChatMessage.timestamp, order: .reverse)]
        )
        chatMessagesDescriptor.fetchLimit = 1
        _loggedChatMessages = Query(chatMessagesDescriptor)

        var todaysWorkoutDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { workout in
                workout.loggedAt >= startOfToday
            },
            sortBy: [SortDescriptor(\WorkoutSession.loggedAt, order: .reverse)]
        )
        todaysWorkoutDescriptor.fetchLimit = 1
        _todaysWorkouts = Query(todaysWorkoutDescriptor)
    }

    var profile: UserProfile? { profiles.first }

    var hasWorkoutToday: Bool {
        !todaysWorkouts.isEmpty
    }

    private var isProfileTabActive: Bool {
        isProfileTabVisible && appTabSelection.wrappedValue == .profile
    }

    private var isActiveWorkoutInProgress: Bool {
        !activeWorkouts.isEmpty
    }

    private var currentProfileID: String {
        profile?.id.uuidString ?? ""
    }

    var latestWeightForPlanPrompt: Double? { latestWeightKg }
    var memoryCount: Int { activeMemoriesCount }
    var conversationCount: Int { chatConversationCount }
    var canAccessAIFeatures: Bool { monetizationService?.canAccessAIFeatures ?? true }
    private var hasClaimableLocalProgress: Bool {
        guard let profile else { return false }
        return profile.hasWorkoutPlan
            || !historicalWorkouts.isEmpty
            || !loggedFoodEntries.isEmpty
            || !loggedChatMessages.isEmpty
            || latestWeightKg != nil
            || customRemindersCount > 0
    }

    private var shouldShowAccountCompletionCard: Bool {
        guard hasClaimableLocalProgress else { return false }
        guard accountSessionService?.isAuthenticated != true else { return false }
        let secondsSinceDismissal = Date().timeIntervalSince1970 - accountSetupPromptLastDismissedAt
        return secondsSinceDismissal >= Self.accountSetupPromptCooldownSeconds
    }

    private var shouldShowProUpsellCard: Bool {
        monetizationService?.canAccessAIFeatures == false
    }

    var body: some View {
        let currentProfile = profile

        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let currentProfile {
                        if shouldShowAccountCompletionCard {
                            accountCompletionCard
                        }
                        headerCard(currentProfile)
                        planCard(currentProfile)
                        workoutPlanCard(currentProfile)
                        memoriesCard()
                        chatHistoryCard()
                        exercisesCard()
                        remindersCard(currentProfile, customRemindersCount: customRemindersCount)
                    }
                }
                .id(currentProfile?.id)
                .padding()
            }
            .refreshable {
                refreshProfileMetrics()
                fetchCustomRemindersCount()
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(TraiColors.brandAccent)
                    }
                }
            }
            .sheet(isPresented: $showPlanSheet) {
                if let currentProfile {
                    PlanAdjustmentSheet(profile: currentProfile)
                        .traiSheetBranding()
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                if let currentProfile {
                    NavigationStack {
                        SettingsView(profile: currentProfile)
                    }
                    .traiSheetBranding()
                }
            }
            .sheet(isPresented: $showPlanSetupSheet) {
                WorkoutPlanChatFlow()
                    .traiSheetBranding()
            }
            .sheet(isPresented: $showPlanEditSheet) {
                if let plan = currentProfile?.workoutPlan {
                    WorkoutPlanEditSheet(currentPlan: plan)
                        .traiSheetBranding()
                }
            }
            .sheet(item: $presentedAccountSetupContext) { context in
                AccountSetupView(context: context)
                    .traiSheetBranding()
            }
            .onAppear {
                handleProfileTabSelectionChange(to: appTabSelection.wrappedValue, trackOpen: true)
            }
            .onChange(of: appTabSelection.wrappedValue) { _, selectedTab in
                handleProfileTabSelectionChange(to: selectedTab, trackOpen: true)
            }
            .onChange(of: activeWorkouts.count) {
                markProfileMetricsRefreshNeeded(delayMilliseconds: 180)
            }
            .proUpsellPresenter()
            .onChange(of: showPlanSheet) { _, isShowing in
                if !isShowing {
                    markProfileMetricsRefreshNeeded(delayMilliseconds: 180)
                }
            }
            .onChange(of: showPlanSetupSheet) { _, isShowing in
                if !isShowing {
                    markProfileMetricsRefreshNeeded(delayMilliseconds: 180)
                }
            }
            .onChange(of: showPlanEditSheet) { _, isShowing in
                if !isShowing {
                    markProfileMetricsRefreshNeeded(delayMilliseconds: 180)
                }
            }
            .onChange(of: showSettingsSheet) { _, isShowing in
                if !isShowing {
                    markRemindersCountRefreshNeeded(delayMilliseconds: 160)
                    markProfileMetricsRefreshNeeded(delayMilliseconds: 220)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutCompleted)) { _ in
                markProfileMetricsRefreshNeeded(delayMilliseconds: 220)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weightLogged)) { _ in
                markProfileMetricsRefreshNeeded(delayMilliseconds: 140)
            }
            .onReceive(NotificationCenter.default.publisher(for: .coachMemoriesChanged)) { _ in
                markProfileMetricsRefreshNeeded(delayMilliseconds: 60)
            }
            .onDisappear {
                isProfileTabVisible = false
                tabActivationPolicy.deactivate()
                profileMetricsRefreshTask?.cancel()
                remindersCountTask?.cancel()
            }
        }
        .traiBackground()
        .overlay(alignment: .topLeading) {
            Text("ready")
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("profileRootReady")
        }
        .overlay(alignment: .topLeading) {
            Text(profileLatencyProbeLabel)
                .font(.system(size: 1))
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(profileLatencyProbeLabel)
                .accessibilityIdentifier("profileLatencyProbe")
        }
    }

    private var accountCompletionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finish setting up your Trai account")
                .font(.traiHeadline(20))

            Text("Your local profile and history stay on this device. Adding an account now gives billing, restore behavior, and future multi-device support a stable home.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    presentedAccountSetupContext = .secureExistingData
                } label: {
                    Text("Set Up Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.traiPrimary(color: .accentColor, fullWidth: true))

                Button("Not Now") {
                    accountSetupPromptLastDismissedAt = Date().timeIntervalSince1970
                }
                .buttonStyle(.traiTertiary(size: .compact, width: 96, height: 44))
            }
        }
        .padding(20)
        .traiCard(cornerRadius: 20, contentPadding: 0)
    }

    private var profileLatencyProbeLabel: String {
        guard AppLaunchArguments.shouldEnableLatencyProbe else { return "disabled" }
        return latencyProbeEntries.isEmpty ? "pending" : latencyProbeEntries.joined(separator: " | ")
    }

    private func recordProfileLatencyProbe(
        _ operation: String,
        startedAt: UInt64,
        counts: [String: Int] = [:]
    ) {
        guard AppLaunchArguments.shouldEnableLatencyProbe else { return }
        let entry = LatencyProbe.makeEntry(
            operation: operation,
            durationMilliseconds: LatencyProbe.elapsedMilliseconds(since: startedAt),
            counts: counts
        )
        LatencyProbe.append(entry: entry, to: &latencyProbeEntries)
    }

    private func fetchCustomRemindersCount() {
        let startedAt = LatencyProbe.timerStart()
        let descriptor = FetchDescriptor<CustomReminder>(
            predicate: #Predicate { $0.isEnabled }
        )
        customRemindersCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        cachedOwnerProfileID = currentProfileID
        cachedCustomRemindersCount = customRemindersCount
        remindersCountLastRefreshAt = Date().timeIntervalSince1970
        hasPendingRemindersCountRefresh = false
        recordProfileLatencyProbe(
            "fetchCustomRemindersCount",
            startedAt: startedAt,
            counts: [
                "enabledCustomReminders": customRemindersCount
            ]
        )
    }

    private func handleProfileTabSelectionChange(to selectedTab: AppTab, trackOpen: Bool) {
        let shouldBeActive = selectedTab == .profile

        guard shouldBeActive else {
            guard isProfileTabVisible else { return }
            isProfileTabVisible = false
            tabActivationPolicy.deactivate()
            profileMetricsRefreshTask?.cancel()
            remindersCountTask?.cancel()
            return
        }

        let wasVisible = isProfileTabVisible
        if tabActivationPolicy.activeSince == nil || !wasVisible {
            tabActivationPolicy = TabActivationPolicy(
                minimumDwellMilliseconds: Self.profileHeavyRefreshMinimumDwellMilliseconds
            )
            tabActivationPolicy.activate()
        }
        isProfileTabVisible = true
        let hydratedFromCache = hydrateCachedProfileMetricsIfNeeded()
        if hydratedFromCache {
            // Always reconcile hydrated cache with source-of-truth shortly after first paint.
            markProfileMetricsRefreshNeeded(delayMilliseconds: 320)
            markRemindersCountRefreshNeeded(delayMilliseconds: 280)
        }
        schedulePendingRefreshesIfNeeded()
        if trackOpen && !wasVisible {
            trackOpenProfileIfNeeded()
        }
    }

    private func scheduleRemindersCountRefresh(delayMilliseconds: Int = 300) {
        remindersCountTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: delayMilliseconds
        )
        remindersCountTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isProfileTabActive, hasPendingRemindersCountRefresh else { return }
                fetchCustomRemindersCount()
            }
        }
    }

    private func trackOpenProfileIfNeeded() {
        let now = Date()
        if let lastOpenTrackedAt, now.timeIntervalSince(lastOpenTrackedAt) < 8 * 60 {
            return
        }
        lastOpenTrackedAt = now
        BehaviorTracker(modelContext: modelContext).record(
            actionKey: BehaviorActionKey.openProfile,
            domain: .profile,
            surface: .profile,
            outcome: .opened,
            metadata: ["source": "profile_tab"],
            saveImmediately: false
        )
    }

    private func scheduleProfileMetricsRefresh(delayMilliseconds: Int = 300) {
        profileMetricsRefreshTask?.cancel()
        let activationToken = tabActivationPolicy.activationToken
        let effectiveDelayMilliseconds = tabActivationPolicy.effectiveDelayMilliseconds(
            requested: delayMilliseconds
        )
        profileMetricsRefreshTask = Task(priority: .utility) {
            if effectiveDelayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(effectiveDelayMilliseconds))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard tabActivationPolicy.shouldRunHeavyRefresh(for: activationToken) else { return }
                guard isProfileTabActive, hasPendingProfileMetricsRefresh else { return }
                guard !isActiveWorkoutInProgress else { return }
                refreshProfileMetrics()
            }
        }
    }

    private func refreshProfileMetrics() {
        let startedAt = LatencyProbe.timerStart()
        guard let profile else {
            latestWeightKg = nil
            activeMemoriesCount = 0
            chatConversationCount = 0
            cachedOwnerProfileID = ""
            cachedLatestWeightKg = -1
            cachedActiveMemoriesCount = 0
            cachedChatConversationCount = 0
            profileMetricsLastRefreshAt = Date().timeIntervalSince1970
            hasPendingProfileMetricsRefresh = false
            return
        }

        var weightDescriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\WeightEntry.loggedAt, order: .reverse)]
        )
        weightDescriptor.fetchLimit = 1
        latestWeightKg = ((try? modelContext.fetch(weightDescriptor))?.first)?.weightKg

        let activeMemoriesDescriptor = FetchDescriptor<CoachMemory>(
            predicate: #Predicate<CoachMemory> { $0.isActive }
        )
        activeMemoriesCount = (try? modelContext.fetchCount(activeMemoriesDescriptor)) ?? 0

        let now = Date()
        let chatCutoff = Calendar.current.date(
            byAdding: .day,
            value: -Self.profileChatWindowDays,
            to: now
        ) ?? .distantPast
        let chatDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { message in
                message.timestamp >= chatCutoff && message.sessionId != nil
            }
        )
        let messages = (try? modelContext.fetch(chatDescriptor)) ?? []
        chatConversationCount = Set(messages.compactMap(\.sessionId)).count
        cachedOwnerProfileID = profile.id.uuidString
        cachedLatestWeightKg = latestWeightKg ?? -1
        cachedActiveMemoriesCount = activeMemoriesCount
        cachedChatConversationCount = chatConversationCount
        profileMetricsLastRefreshAt = now.timeIntervalSince1970
        hasPendingProfileMetricsRefresh = false
        recordProfileLatencyProbe(
            "refreshProfileMetrics",
            startedAt: startedAt,
            counts: [
                "activeMemories": activeMemoriesCount,
                "chatMessages": messages.count,
                "chatSessions": chatConversationCount,
                "hasWeight": latestWeightKg == nil ? 0 : 1
            ]
        )
    }

    private func markProfileMetricsRefreshNeeded(delayMilliseconds: Int = 220) {
        hasPendingProfileMetricsRefresh = true
        guard isProfileTabActive else { return }
        scheduleProfileMetricsRefresh(delayMilliseconds: delayMilliseconds)
    }

    private func markRemindersCountRefreshNeeded(delayMilliseconds: Int = 220) {
        hasPendingRemindersCountRefresh = true
        guard isProfileTabActive else { return }
        scheduleRemindersCountRefresh(delayMilliseconds: delayMilliseconds)
    }

    private func schedulePendingRefreshesIfNeeded() {
        guard isProfileTabActive else { return }
        var scheduledHeavyRefresh = false

        let shouldRefreshProfileMetrics = hasPendingProfileMetricsRefresh || isProfileMetricsRefreshStale
        if shouldRefreshProfileMetrics {
            hasPendingProfileMetricsRefresh = true
            scheduleProfileMetricsRefresh(
                delayMilliseconds: hasExecutedInitialHeavyRefresh
                    ? Self.profileReactivationHeavyDelayMilliseconds
                    : Self.profileHeavyMetricsDelayMilliseconds
            )
            scheduledHeavyRefresh = true
        }

        let shouldRefreshRemindersCount = hasPendingRemindersCountRefresh || isRemindersCountRefreshStale
        if shouldRefreshRemindersCount {
            hasPendingRemindersCountRefresh = true
            scheduleRemindersCountRefresh(
                delayMilliseconds: hasExecutedInitialHeavyRefresh
                    ? Self.profileReactivationHeavyDelayMilliseconds
                    : Self.profileHeavyMetricsDelayMilliseconds
            )
            scheduledHeavyRefresh = true
        }

        if scheduledHeavyRefresh {
            hasExecutedInitialHeavyRefresh = true
        }
    }

    private var isProfileMetricsRefreshStale: Bool {
        guard profileMetricsLastRefreshAt > 0 else { return true }
        return Date().timeIntervalSince1970 - profileMetricsLastRefreshAt > Self.profileMetricsStaleAfterSeconds
    }

    private var isRemindersCountRefreshStale: Bool {
        guard remindersCountLastRefreshAt > 0 else { return true }
        return Date().timeIntervalSince1970 - remindersCountLastRefreshAt > Self.profileRemindersStaleAfterSeconds
    }

    @discardableResult
    private func hydrateCachedProfileMetricsIfNeeded() -> Bool {
        guard !currentProfileID.isEmpty else { return false }
        guard cachedOwnerProfileID == currentProfileID else { return false }

        var hydrated = false
        if latestWeightKg == nil, cachedLatestWeightKg >= 0 {
            latestWeightKg = cachedLatestWeightKg
            hydrated = true
        }
        if activeMemoriesCount == 0, cachedActiveMemoriesCount > 0 {
            activeMemoriesCount = cachedActiveMemoriesCount
            hydrated = true
        }
        if chatConversationCount == 0, cachedChatConversationCount > 0 {
            chatConversationCount = cachedChatConversationCount
            hydrated = true
        }
        if customRemindersCount == 0, cachedCustomRemindersCount > 0 {
            customRemindersCount = cachedCustomRemindersCount
            hydrated = true
        }
        return hydrated
    }

    // MARK: - Header Card

    @ViewBuilder
    private func headerCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [TraiColors.brandAccent, TraiColors.brandAccent.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 90, height: 90)

                Circle()
                    .fill(TraiColors.brandAccent.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Text(profile.name.prefix(1).uppercased())
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(TraiColors.brandAccent)
                    }
            }

            VStack(spacing: 4) {
                Text(profile.name.isEmpty ? "Welcome" : profile.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Image(systemName: profile.goal.iconName)
                        .font(.caption)
                    Text(profile.goal.displayName)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            if shouldShowProUpsellCard {
                HStack {
                    Button {
                        proUpsellCoordinator?.present(source: .settings)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.hexagongrid.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TraiColors.brandAccent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unlock Trai Pro")
                                    .font(.traiHeadline(15))
                                    .foregroundStyle(.primary)

                                Text("Coaching, food analysis, and personalized plans.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(TraiColors.brandAccent.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(TraiColors.brandAccent.opacity(0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
            }

            HStack(spacing: 8) {
                profileTintBadge(
                    title: hasWorkoutToday ? "Training Day" : "Rest Day",
                    icon: nil,
                    tint: hasWorkoutToday ? .green : .orange
                )

                if canAccessAIFeatures {
                    profileProBadge()
                } else {
                    profileFreeBadge()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .traiCard(cornerRadius: 24, contentPadding: 0)
    }

    private func profileTintBadge(title: String, icon: String?, tint: Color) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.15))
        )
    }

    private func profileFreeBadge() -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.caption.weight(.semibold))

            Text("Free Plan")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(TraiColors.brandAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            Capsule()
                .stroke(TraiColors.brandAccent.opacity(0.16), lineWidth: 1)
        )
    }

    private func profileProBadge() -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle.hexagongrid.circle.fill")
                .font(.caption.weight(.bold))

            Text("Trai Pro")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            TraiGradient.actionVibrant(TraiColors.ember, TraiColors.blaze),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: TraiColors.ember.opacity(0.24), radius: 8, y: 3)
    }

}

#Preview {
    ProfileView()
        .modelContainer(for: [
            UserProfile.self,
            WorkoutSession.self,
            WeightEntry.self
        ], inMemory: true)
}
