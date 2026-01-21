//
//  TodaysRemindersCard.swift
//  Trai
//
//  Card showing today's upcoming reminders on the dashboard.
//

import SwiftUI

struct TodaysRemindersCard: View {
    let reminders: [ReminderItem]
    let onReminderTap: (ReminderItem) -> Void
    let onComplete: (ReminderItem) -> Void
    let onViewAll: () -> Void

    /// Simple reminder item for display (only upcoming reminders)
    struct ReminderItem: Identifiable {
        let id: UUID
        let title: String
        let time: String
        let hour: Int
        let minute: Int
        let isCustom: Bool
    }

    /// Track which reminders are in the completing animation state
    @State private var completingIds: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Upcoming Reminders", systemImage: "bell.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    onViewAll()
                } label: {
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(reminders.prefix(3)) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        isCompleting: completingIds.contains(reminder.id),
                        onComplete: {
                            completeWithAnimation(reminder)
                        },
                        onTap: {
                            onReminderTap(reminder)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                }

                if reminders.count > 3 {
                    Text("+\(reminders.count - 3) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: reminders.map(\.id))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func completeWithAnimation(_ reminder: ReminderItem) {
        // Show completing state with checkmark
        withAnimation(.easeInOut(duration: 0.2)) {
            completingIds.insert(reminder.id)
        }

        // After a brief delay, call the actual completion
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            onComplete(reminder)
        }
    }
}

// MARK: - Reminder Row View

private struct ReminderRow: View {
    let reminder: TodaysRemindersCard.ReminderItem
    let isCompleting: Bool
    let onComplete: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Complete button with animated checkmark
            Button {
                onComplete()
            } label: {
                ZStack {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .opacity(isCompleting ? 0 : 1)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .scaleEffect(isCompleting ? 1 : 0.5)
                        .opacity(isCompleting ? 1 : 0)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCompleting)
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)

            Button {
                onTap()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: reminder.isCustom ? "bell.badge" : "bell")
                        .font(.body)
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .font(.subheadline)
                            .foregroundStyle(isCompleting ? .secondary : .primary)
                            .lineLimit(1)
                            .strikethrough(isCompleting)

                        Text(reminder.time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if reminder.isCustom && !isCompleting {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
        }
        .padding(.vertical, 4)
        .opacity(isCompleting ? 0.6 : 1)
    }
}

// MARK: - Helper to build reminder items from various sources

extension TodaysRemindersCard {
    /// Build upcoming reminder items for today (excludes past reminders)
    static func buildReminderItems(
        from customReminders: [CustomReminder],
        mealRemindersEnabled: Bool,
        enabledMeals: Set<String>,
        workoutRemindersEnabled: Bool,
        workoutDays: Set<Int>,
        workoutHour: Int,
        workoutMinute: Int
    ) -> [ReminderItem] {
        var items: [ReminderItem] = []
        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)

        // Helper to check if a time is upcoming
        func isUpcoming(hour: Int, minute: Int) -> Bool {
            hour > currentHour || (hour == currentHour && minute > currentMinute)
        }

        // Add custom reminders scheduled for today (only upcoming)
        for reminder in customReminders where reminder.isEnabled {
            let reminderDays = reminder.repeatDaysSet
            let scheduledForToday = reminderDays.isEmpty || reminderDays.contains(currentWeekday)

            if scheduledForToday && isUpcoming(hour: reminder.hour, minute: reminder.minute) {
                items.append(ReminderItem(
                    id: reminder.id,
                    title: reminder.title,
                    time: reminder.formattedTime,
                    hour: reminder.hour,
                    minute: reminder.minute,
                    isCustom: true
                ))
            }
        }

        // Add meal reminders if enabled (only upcoming)
        if mealRemindersEnabled {
            for meal in MealReminderTime.allMeals where enabledMeals.contains(meal.id) {
                if isUpcoming(hour: meal.hour, minute: meal.minute) {
                    items.append(ReminderItem(
                        id: StableUUID.forMeal(meal.id),
                        title: meal.displayName,
                        time: formatTime(hour: meal.hour, minute: meal.minute),
                        hour: meal.hour,
                        minute: meal.minute,
                        isCustom: false
                    ))
                }
            }
        }

        // Add workout reminder if enabled and scheduled for today (only upcoming)
        if workoutRemindersEnabled && workoutDays.contains(currentWeekday) {
            if isUpcoming(hour: workoutHour, minute: workoutMinute) {
                items.append(ReminderItem(
                    id: StableUUID.forWorkoutReminder(),
                    title: "Workout",
                    time: formatTime(hour: workoutHour, minute: workoutMinute),
                    hour: workoutHour,
                    minute: workoutMinute,
                    isCustom: false
                ))
            }
        }

        // Sort by time
        return items.sorted { $0.time < $1.time }
    }

    private static func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}

#Preview {
    TodaysRemindersCard(
        reminders: [
            .init(id: UUID(), title: "Drink water", time: "10:00 AM", hour: 10, minute: 0, isCustom: true),
            .init(id: UUID(), title: "Lunch", time: "12:00 PM", hour: 12, minute: 0, isCustom: false),
            .init(id: UUID(), title: "Workout", time: "5:00 PM", hour: 17, minute: 0, isCustom: false)
        ],
        onReminderTap: { _ in },
        onComplete: { _ in },
        onViewAll: {}
    )
    .padding()
}
