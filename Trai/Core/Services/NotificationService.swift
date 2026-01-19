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

    private let center = UNUserNotificationCenter.current()

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

    // MARK: - Initialization

    init() {
        registerNotificationCategories()
    }

    /// Register notification categories with actions for long-press menu
    private func registerNotificationCategories() {
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

    // MARK: - Authorization

    /// Request notification authorization
    func requestAuthorization() async -> Bool {
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

    /// Schedule meal reminders based on user preferences
    func scheduleMealReminders(times: [MealReminderTime]) async {
        // Clear existing meal reminders
        await cancelNotifications(category: .mealReminder)

        guard isAuthorized else { return }

        for meal in times {
            await scheduleMealReminder(meal)
        }
    }

    private func scheduleMealReminder(_ meal: MealReminderTime) async {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(meal.displayName)"
        content.body = meal.message
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.mealReminder.rawValue
        content.userInfo = [
            "mealId": meal.id,
            "reminderHour": meal.hour,
            "reminderMinute": meal.minute
        ]

        var dateComponents = DateComponents()
        dateComponents.hour = meal.hour
        dateComponents.minute = meal.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(NotificationCategory.mealReminder.rawValue)_\(meal.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule meal reminder: \(error)")
        }
    }

    // MARK: - Scheduling Workout Reminders

    /// Schedule workout reminders for specific days
    func scheduleWorkoutReminders(days: [Int], hour: Int, minute: Int) async {
        // Clear existing workout reminders
        await cancelNotifications(category: .workoutReminder)

        guard isAuthorized else { return }

        for day in days {
            await scheduleWorkoutReminder(weekday: day, hour: hour, minute: minute)
        }
    }

    private func scheduleWorkoutReminder(weekday: Int, hour: Int, minute: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Workout Time"
        content.body = "Ready to crush your workout? Let's go!"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.workoutReminder.rawValue

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday // 1 = Sunday, 2 = Monday, etc.
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(NotificationCategory.workoutReminder.rawValue)_\(weekday)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule workout reminder: \(error)")
        }
    }

    // MARK: - Weight Reminders

    /// Schedule weekly weight check reminder
    func scheduleWeightReminder(weekday: Int, hour: Int, minute: Int) async {
        await cancelNotifications(category: .weightReminder)

        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Weekly Weigh-In"
        content.body = "Time for your weekly weight check. Track your progress!"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.weightReminder.rawValue

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: NotificationCategory.weightReminder.rawValue,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule weight reminder: \(error)")
        }
    }

    // MARK: - Custom Reminders

    /// Schedule a single custom reminder
    func scheduleCustomReminder(_ reminder: CustomReminder) async {
        // Cancel existing notification for this reminder first
        await cancelCustomReminder(id: reminder.id)

        guard isAuthorized, reminder.isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if !reminder.body.isEmpty {
            content.body = reminder.body
        }
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.customReminder.rawValue
        content.userInfo = [
            "reminderId": reminder.id.uuidString,
            "reminderHour": reminder.hour,
            "reminderMinute": reminder.minute
        ]

        if reminder.isDaily {
            // Schedule daily at the specified time
            var dateComponents = DateComponents()
            dateComponents.hour = reminder.hour
            dateComponents.minute = reminder.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(NotificationCategory.customReminder.rawValue)_\(reminder.id.uuidString)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                print("Failed to schedule custom reminder: \(error)")
            }
        } else {
            // Schedule for each selected day
            for weekday in reminder.repeatDaysSet {
                var dateComponents = DateComponents()
                dateComponents.weekday = weekday
                dateComponents.hour = reminder.hour
                dateComponents.minute = reminder.minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(NotificationCategory.customReminder.rawValue)_\(reminder.id.uuidString)_\(weekday)",
                    content: content,
                    trigger: trigger
                )

                do {
                    try await center.add(request)
                } catch {
                    print("Failed to schedule custom reminder for day \(weekday): \(error)")
                }
            }
        }
    }

    /// Schedule all custom reminders
    func scheduleAllCustomReminders(_ reminders: [CustomReminder]) async {
        // Clear all custom reminders first
        await cancelNotifications(category: .customReminder)

        guard isAuthorized else { return }

        for reminder in reminders where reminder.isEnabled {
            await scheduleCustomReminder(reminder)
        }
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

    // MARK: - Snooze

    /// Schedule a snoozed notification for 10 minutes from now
    func scheduleSnooze(title: String, body: String, category: NotificationCategory, userInfo: [AnyHashable: Any]) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
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
