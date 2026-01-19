//
//  NotificationDelegate.swift
//  Trai
//
//  Handles notification actions (long-press complete/snooze) and tap behavior.
//

import Foundation
import UserNotifications
import SwiftData

/// Delegate to handle notification interactions
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let modelContainer: ModelContainer
    private let notificationService: NotificationService

    /// Callback for when a reminder should be shown (notification tapped)
    var onShowReminders: (() -> Void)?

    init(modelContainer: ModelContainer, notificationService: NotificationService) {
        self.modelContainer = modelContainer
        self.notificationService = notificationService
        super.init()

        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when user taps on notification (not an action button)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let categoryIdentifier = response.notification.request.content.categoryIdentifier

        Task { @MainActor in
            switch actionIdentifier {
            case NotificationService.NotificationAction.complete.rawValue:
                await handleCompleteAction(userInfo: userInfo)

            case NotificationService.NotificationAction.snooze.rawValue:
                await handleSnoozeAction(
                    content: response.notification.request.content,
                    categoryIdentifier: categoryIdentifier
                )

            case UNNotificationDefaultActionIdentifier:
                // User tapped on the notification itself - show reminders view
                onShowReminders?()

            default:
                break
            }

            completionHandler()
        }
    }

    /// Called when notification arrives while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound])
    }

    // MARK: - Action Handlers

    private func handleCompleteAction(userInfo: [AnyHashable: Any]) async {
        let context = modelContainer.mainContext

        // Try to get reminder ID from userInfo
        if let reminderIdString = userInfo["reminderId"] as? String,
           let reminderId = UUID(uuidString: reminderIdString) {
            // Custom reminder
            let hour = userInfo["reminderHour"] as? Int ?? 0
            let minute = userInfo["reminderMinute"] as? Int ?? 0
            await completeReminder(id: reminderId, hour: hour, minute: minute, context: context)
        } else if let mealId = userInfo["mealId"] as? String {
            // Meal reminder - use stable UUID matching TodaysRemindersCard
            let reminderId = Self.stableUUID(for: "MEAL-\(mealId)")
            let hour = userInfo["reminderHour"] as? Int ?? 0
            let minute = userInfo["reminderMinute"] as? Int ?? 0
            await completeReminder(id: reminderId, hour: hour, minute: minute, context: context)
        }
    }

    private func completeReminder(id: UUID, hour: Int, minute: Int, context: ModelContext) async {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentMinutes = currentHour * 60 + currentMinute
        let reminderMinutes = hour * 60 + minute

        // We no longer track on-time status meaningfully, just set to true
        let completion = ReminderCompletion(
            reminderId: id,
            completedAt: now,
            wasOnTime: currentMinutes <= reminderMinutes + 30
        )
        context.insert(completion)
        try? context.save()
    }

    private func handleSnoozeAction(
        content: UNNotificationContent,
        categoryIdentifier: String
    ) async {
        guard let category = NotificationService.NotificationCategory(rawValue: categoryIdentifier) else {
            return
        }

        await notificationService.scheduleSnooze(
            title: content.title,
            body: content.body,
            category: category,
            userInfo: content.userInfo
        )
    }

    // MARK: - Helpers

    /// Generate a stable UUID from a string identifier (must match TodaysRemindersCard)
    private static func stableUUID(for identifier: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(identifier)
        let hash = hasher.finalize()

        let bytes = withUnsafeBytes(of: hash) { Array($0) }
        let uuidString = String(format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0 % bytes.count], bytes[1 % bytes.count], bytes[2 % bytes.count], bytes[3 % bytes.count],
            bytes[4 % bytes.count], bytes[5 % bytes.count],
            bytes[6 % bytes.count], bytes[7 % bytes.count],
            bytes[0 % bytes.count], bytes[1 % bytes.count],
            bytes[2 % bytes.count], bytes[3 % bytes.count], bytes[4 % bytes.count], bytes[5 % bytes.count], bytes[6 % bytes.count], bytes[7 % bytes.count])

        return UUID(uuidString: uuidString) ?? UUID()
    }
}
