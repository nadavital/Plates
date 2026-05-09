//
//  NotificationService.swift
//  Trai
//
//  Service for managing local notifications for meal and workout reminders.
//

import Foundation
import UserNotifications

@MainActor @Observable
final class NotificationService {
    // MARK: - Properties

    private(set) var isAuthorized = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private var didRegisterCategories = false
    // Keep horizons beyond one week while respecting iOS's 64 pending request limit.
    private let builtInSchedulingWindowDays = 10
    private let customSchedulingWindowDays = 8
    private let maxPendingRequests = 64

    // MARK: - Notification Identifiers

    enum NotificationCategory: String, CaseIterable {
        case mealReminder = "MEAL_REMINDER"
        case workoutReminder = "WORKOUT_REMINDER"
        case weightReminder = "WEIGHT_REMINDER"
        case customReminder = "CUSTOM_REMINDER"

        var title: String {
            switch self {
            case .mealReminder: "Meal Reminder"
            case .workoutReminder: "Workout Reminder"
            case .weightReminder: "Weight Check"
            case .customReminder: "Reminder"
            }
        }
    }

    // MARK: - Notification Actions

    enum NotificationAction: String {
        case complete = "COMPLETE_ACTION"
        case snooze = "SNOOZE_ACTION"
    }

    // MARK: - Request Identifiers

    nonisolated static func occurrenceDateToken(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d%02d%02d", year, month, day)
    }

    nonisolated static func mealRequestIdentifier(mealId: String, date: Date, calendar: Calendar = .current) -> String {
        "\(NotificationCategory.mealReminder.rawValue)_\(mealId)_\(occurrenceDateToken(for: date, calendar: calendar))"
    }

    nonisolated static func workoutRequestIdentifier(weekday: Int, date: Date, calendar: Calendar = .current) -> String {
        "\(NotificationCategory.workoutReminder.rawValue)_\(weekday)_\(occurrenceDateToken(for: date, calendar: calendar))"
    }

    nonisolated static func weightRequestIdentifier(date: Date, calendar: Calendar = .current) -> String {
        "\(NotificationCategory.weightReminder.rawValue)_\(occurrenceDateToken(for: date, calendar: calendar))"
    }

    nonisolated static func customRequestIdentifier(reminderId: UUID, date: Date, calendar: Calendar = .current) -> String {
        "\(NotificationCategory.customReminder.rawValue)_\(reminderId.uuidString)_\(occurrenceDateToken(for: date, calendar: calendar))"
    }

    // MARK: - Initialization

    init() {
        // Register categories early so long-press actions work on cold launch.
        registerNotificationCategoriesIfNeeded()
    }

    /// Register notification categories with actions for long-press menu
    private func registerNotificationCategoriesIfNeeded() {
        guard !didRegisterCategories else { return }
        didRegisterCategories = true

        let completeAction = UNNotificationAction(
            identifier: NotificationAction.complete.rawValue,
            title: "Mark Complete",
            options: []
        )

        let snoozeAction = UNNotificationAction(
            identifier: NotificationAction.snooze.rawValue,
            title: "Snooze 10 min",
            options: []
        )

        // Create categories for each reminder type with actions
        let categories: [UNNotificationCategory] = NotificationCategory.allCases.map { category in
            UNNotificationCategory(
                identifier: category.rawValue,
                actions: [completeAction, snoozeAction],
                intentIdentifiers: [],
                options: []
            )
        }

        center.setNotificationCategories(Set(categories))
    }

    /// Ensure categories are registered before notifications are delivered/handled.
    func ensureNotificationSetup() {
        registerNotificationCategoriesIfNeeded()
    }

    // MARK: - Authorization

    /// Request notification authorization
    func requestAuthorization() async -> Bool {
        registerNotificationCategoriesIfNeeded()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            await updateAuthorizationStatus()
            return granted
        } catch {
            print("Notification authorization failed: \(error)")
            return false
        }
    }

    /// Update current authorization status
    func updateAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Scheduling Meal Reminders

    /// Schedule meal reminders based on user preferences.
    /// Uses one-shot rolling notifications so a single day can be skipped when already completed.
    func scheduleMealReminders(
        times: [MealReminderTime],
        skippingTodayReminderIDs: Set<UUID> = []
    ) async {
        registerNotificationCategoriesIfNeeded()
        // Clear existing meal reminders
        await cancelNotifications(category: .mealReminder)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        var pendingCount = await center.pendingNotificationRequests().count

        for dayOffset in 0..<builtInSchedulingWindowDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            for meal in times {
                let mealReminderID = StableUUID.forMeal(meal.id)
                if dayOffset == 0, skippingTodayReminderIDs.contains(mealReminderID) {
                    continue
                }
                await scheduleMealReminder(
                    meal,
                    on: dayDate,
                    now: now,
                    calendar: calendar,
                    pendingCount: &pendingCount
                )
            }
        }
    }

    private func scheduleMealReminder(
        _ meal: MealReminderTime,
        on dayDate: Date,
        now: Date,
        calendar: Calendar,
        pendingCount: inout Int
    ) async {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        dateComponents.hour = meal.hour
        dateComponents.minute = meal.minute

        guard let fireDate = calendar.date(from: dateComponents), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for \(meal.displayName)"
        content.body = meal.message
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = NotificationCategory.mealReminder.rawValue
        content.userInfo = [
            "mealId": meal.id,
            "reminderHour": meal.hour,
            "reminderMinute": meal.minute,
            "scheduledDate": Self.occurrenceDateToken(for: dayDate, calendar: calendar)
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.mealRequestIdentifier(mealId: meal.id, date: dayDate, calendar: calendar),
            content: content,
            trigger: trigger
        )

        await addRequestIfCapacity(request, pendingCount: &pendingCount)
    }

    // MARK: - Scheduling Workout Reminders

    /// Schedule workout reminders for specific days.
    /// Uses one-shot rolling notifications so today's reminder can be skipped when already completed.
    func scheduleWorkoutReminders(
        days: [Int],
        hour: Int,
        minute: Int,
        skippingTodayReminderIDs: Set<UUID> = []
    ) async {
        registerNotificationCategoriesIfNeeded()
        // Clear existing workout reminders
        await cancelNotifications(category: .workoutReminder)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let scheduledDays = Set(days)
        var pendingCount = await center.pendingNotificationRequests().count

        for dayOffset in 0..<builtInSchedulingWindowDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: dayDate)
            guard scheduledDays.contains(weekday) else { continue }

            if dayOffset == 0, skippingTodayReminderIDs.contains(StableUUID.forWorkoutReminder()) {
                continue
            }

            await scheduleWorkoutReminder(
                weekday: weekday,
                hour: hour,
                minute: minute,
                on: dayDate,
                now: now,
                calendar: calendar,
                pendingCount: &pendingCount
            )
        }
    }

    private func scheduleWorkoutReminder(
        weekday: Int,
        hour: Int,
        minute: Int,
        on dayDate: Date,
        now: Date,
        calendar: Calendar,
        pendingCount: inout Int
    ) async {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        dateComponents.hour = hour
        dateComponents.minute = minute

        guard let fireDate = calendar.date(from: dateComponents), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Workout Time"
        content.body = "Ready to crush your workout? Let's go!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = NotificationCategory.workoutReminder.rawValue
        content.userInfo = [
            "reminderId": StableUUID.forWorkoutReminder().uuidString,
            "reminderHour": hour,
            "reminderMinute": minute,
            "scheduledDate": Self.occurrenceDateToken(for: dayDate, calendar: calendar)
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.workoutRequestIdentifier(weekday: weekday, date: dayDate, calendar: calendar),
            content: content,
            trigger: trigger
        )

        await addRequestIfCapacity(request, pendingCount: &pendingCount)
    }

    // MARK: - Weight Reminders

    /// Schedule weekly weight check reminders.
    /// Uses one-shot rolling notifications so today's reminder can be skipped when already completed.
    func scheduleWeightReminder(
        weekday: Int,
        hour: Int,
        minute: Int,
        skippingTodayReminderIDs: Set<UUID> = []
    ) async {
        registerNotificationCategoriesIfNeeded()
        await cancelNotifications(category: .weightReminder)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        var pendingCount = await center.pendingNotificationRequests().count
        let weightReminderID = StableUUID.forWeightReminder()

        for dayOffset in 0..<builtInSchedulingWindowDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let dayWeekday = calendar.component(.weekday, from: dayDate)
            guard dayWeekday == weekday else { continue }

            if dayOffset == 0, skippingTodayReminderIDs.contains(weightReminderID) {
                continue
            }

            await scheduleWeightReminder(
                hour: hour,
                minute: minute,
                on: dayDate,
                now: now,
                calendar: calendar,
                pendingCount: &pendingCount
            )
        }
    }

    private func scheduleWeightReminder(
        hour: Int,
        minute: Int,
        on dayDate: Date,
        now: Date,
        calendar: Calendar,
        pendingCount: inout Int
    ) async {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        dateComponents.hour = hour
        dateComponents.minute = minute

        guard let fireDate = calendar.date(from: dateComponents), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Weekly Weigh-In"
        content.body = "Time for your weekly weight check. Track your progress!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = NotificationCategory.weightReminder.rawValue
        content.userInfo = [
            "reminderId": StableUUID.forWeightReminder().uuidString,
            "reminderHour": hour,
            "reminderMinute": minute,
            "scheduledDate": Self.occurrenceDateToken(for: dayDate, calendar: calendar)
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.weightRequestIdentifier(date: dayDate, calendar: calendar),
            content: content,
            trigger: trigger
        )

        await addRequestIfCapacity(request, pendingCount: &pendingCount)
    }

    // MARK: - Custom Reminders

    /// Schedule a single custom reminder using one-shot rolling notifications.
    func scheduleCustomReminder(
        _ reminder: CustomReminder,
        skippingTodayReminderIDs: Set<UUID> = []
    ) async {
        registerNotificationCategoriesIfNeeded()
        // Cancel existing notification for this reminder first
        await cancelCustomReminder(id: reminder.id)

        // Check authorization status directly (not cached) to handle edit scenarios
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized, reminder.isEnabled else { return }

        var pendingCount = await center.pendingNotificationRequests().count
        await scheduleCustomReminderOccurrences(
            reminder,
            skippingTodayReminderIDs: skippingTodayReminderIDs,
            pendingCount: &pendingCount
        )
    }

    /// Schedule all custom reminders
    func scheduleAllCustomReminders(
        _ reminders: [CustomReminder],
        skippingTodayReminderIDs: Set<UUID> = []
    ) async {
        // Clear all custom reminders first
        await cancelNotifications(category: .customReminder)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let enabledReminders = reminders.filter { $0.isEnabled }
        guard !enabledReminders.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        var pendingCount = await center.pendingNotificationRequests().count

        // Interleave across reminders by day so later reminders are not starved by the pending cap.
        for dayOffset in 0..<customSchedulingWindowDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: dayDate)

            for reminder in enabledReminders {
                let scheduledForWeekday = reminder.isDaily || reminder.repeatDaysSet.contains(weekday)
                guard scheduledForWeekday else { continue }

                if dayOffset == 0, skippingTodayReminderIDs.contains(reminder.id) {
                    continue
                }

                await scheduleCustomReminderOccurrence(
                    reminder,
                    on: dayDate,
                    now: now,
                    calendar: calendar,
                    pendingCount: &pendingCount
                )
            }
        }
    }

    private func scheduleCustomReminderOccurrences(
        _ reminder: CustomReminder,
        skippingTodayReminderIDs: Set<UUID>,
        pendingCount: inout Int
    ) async {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0..<customSchedulingWindowDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: dayDate)
            let scheduledForWeekday = reminder.isDaily || reminder.repeatDaysSet.contains(weekday)
            guard scheduledForWeekday else { continue }

            if dayOffset == 0, skippingTodayReminderIDs.contains(reminder.id) {
                continue
            }
            await scheduleCustomReminderOccurrence(
                reminder,
                on: dayDate,
                now: now,
                calendar: calendar,
                pendingCount: &pendingCount
            )
        }
    }

    private func scheduleCustomReminderOccurrence(
        _ reminder: CustomReminder,
        on dayDate: Date,
        now: Date,
        calendar: Calendar,
        pendingCount: inout Int
    ) async {
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
        dateComponents.hour = reminder.hour
        dateComponents.minute = reminder.minute

        guard let fireDate = calendar.date(from: dateComponents), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if !reminder.body.isEmpty {
            content.body = reminder.body
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = NotificationCategory.customReminder.rawValue
        content.userInfo = [
            "reminderId": reminder.id.uuidString,
            "reminderHour": reminder.hour,
            "reminderMinute": reminder.minute,
            "scheduledDate": Self.occurrenceDateToken(for: dayDate, calendar: calendar)
        ]

        let request = UNNotificationRequest(
            identifier: Self.customRequestIdentifier(reminderId: reminder.id, date: dayDate, calendar: calendar),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        )

        await addRequestIfCapacity(request, pendingCount: &pendingCount)
    }

    /// Cancel a specific custom reminder by ID
    func cancelCustomReminder(id: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "\(NotificationCategory.customReminder.rawValue)_\(id.uuidString)"
        let toRemove = pending
            .filter { $0.identifier.hasPrefix(prefix) }
            .map { $0.identifier }

        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    /// Cancel a specific pending notification request.
    func cancelPendingRequest(identifier: String?) {
        guard let identifier, !identifier.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Cancellation

    /// Cancel all notifications for a category
    func cancelNotifications(category: NotificationCategory) async {
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { $0.content.categoryIdentifier == category.rawValue }
            .map { $0.identifier }

        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    /// Cancel all reminders
    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
    }

    private func addRequestIfCapacity(_ request: UNNotificationRequest, pendingCount: inout Int) async {
        guard pendingCount < maxPendingRequests else {
            print("Skipping notification schedule due to pending request cap: \(request.identifier)")
            return
        }

        do {
            try await center.add(request)
            pendingCount += 1
        } catch {
            print("Failed to schedule reminder request \(request.identifier): \(error)")
        }
    }

    // MARK: - Snooze

    /// Schedule a snoozed notification for 10 minutes from now
    func scheduleSnooze(title: String, body: String, category: NotificationCategory, userInfo: [AnyHashable: Any]) async {
        registerNotificationCategoriesIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = category.rawValue
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "SNOOZE_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule snoozed notification: \(error)")
        }
    }

    // MARK: - Query

    /// Get count of pending notifications
    func pendingNotificationCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.count
    }
}

// MARK: - Meal Reminder Time

struct MealReminderTime: Identifiable, Equatable {
    let id: String
    let displayName: String
    let message: String
    let hour: Int
    let minute: Int

    static let breakfast = MealReminderTime(
        id: "breakfast",
        displayName: "Breakfast",
        message: "Good morning! What are you having for breakfast?",
        hour: 8,
        minute: 0
    )

    static let lunch = MealReminderTime(
        id: "lunch",
        displayName: "Lunch",
        message: "Lunchtime! Log what you're eating.",
        hour: 12,
        minute: 30
    )

    static let dinner = MealReminderTime(
        id: "dinner",
        displayName: "Dinner",
        message: "Dinner time! Don't forget to log your meal.",
        hour: 18,
        minute: 30
    )

    static let snack = MealReminderTime(
        id: "snack",
        displayName: "Snack",
        message: "Time for a snack? Log it!",
        hour: 15,
        minute: 0
    )

    static let allMeals: [MealReminderTime] = [.breakfast, .lunch, .dinner, .snack]
}
