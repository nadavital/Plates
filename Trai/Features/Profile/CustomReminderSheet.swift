//
//  CustomReminderSheet.swift
//  Trai
//
//  Sheet for creating and editing custom reminders.
//

import SwiftUI
import SwiftData

struct CustomReminderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let reminder: CustomReminder?
    let notificationService: NotificationService?

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var selectedTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var selectedDays: Set<Int> = []
    @State private var isEnabled: Bool = true

    private var isEditing: Bool { reminder != nil }

    init(reminder: CustomReminder? = nil, notificationService: NotificationService?) {
        self.reminder = reminder
        self.notificationService = notificationService
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $bodyText)
                }

                Section("Time") {
                    DatePicker(
                        "Reminder Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                }

                Section {
                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 7], ["S", "M", "T", "W", "T", "F", "S"])), id: \.0) { day, label in
                                dayButton(day: day, label: label)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Text(repeatDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Repeat")
                } footer: {
                    Text("Leave all unselected for daily reminders")
                }

                if isEditing {
                    Section {
                        Toggle("Enabled", isOn: $isEnabled)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let reminder {
                    title = reminder.title
                    bodyText = reminder.body
                    selectedTime = Calendar.current.date(
                        from: DateComponents(hour: reminder.hour, minute: reminder.minute)
                    ) ?? Date()
                    selectedDays = reminder.repeatDaysSet
                    isEnabled = reminder.isEnabled
                }
            }
        }
    }

    // MARK: - Subviews

    private func dayButton(day: Int, label: String) -> some View {
        Button {
            if selectedDays.contains(day) {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
            HapticManager.lightTap()
        } label: {
            Text(label)
                .font(.caption)
                .bold()
                .frame(width: 36, height: 36)
                .background(selectedDays.contains(day) ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(selectedDays.contains(day) ? .white : .primary)
                .clipShape(.circle)
        }
        .buttonStyle(.plain)
    }

    private var repeatDescription: String {
        if selectedDays.isEmpty {
            return "Every day"
        }

        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = selectedDays.sorted().compactMap { dayNames[safe: $0] }

        if selectedDays.count == 7 {
            return "Every day"
        } else if selectedDays == Set([2, 3, 4, 5, 6]) {
            return "Weekdays"
        } else if selectedDays == Set([1, 7]) {
            return "Weekends"
        } else {
            return days.joined(separator: ", ")
        }
    }

    // MARK: - Helpers

    /// Extracts hour and minute from selectedTime, rounding minute to nearest 5
    private var timeComponents: (hour: Int, minute: Int) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        // Round to nearest 5 minutes
        let roundedMinute = ((minute + 2) / 5) * 5 % 60
        return (hour, roundedMinute)
    }

    // MARK: - Actions

    private func save() {
        let (hour, minute) = timeComponents

        if let reminder {
            // Update existing
            reminder.title = title.trimmingCharacters(in: .whitespaces)
            reminder.body = bodyText.trimmingCharacters(in: .whitespaces)
            reminder.hour = hour
            reminder.minute = minute
            reminder.repeatDaysSet = selectedDays
            reminder.isEnabled = isEnabled

            Task {
                await notificationService?.scheduleCustomReminder(reminder)
            }
        } else {
            // Create new
            let newReminder = CustomReminder(
                title: title.trimmingCharacters(in: .whitespaces),
                body: bodyText.trimmingCharacters(in: .whitespaces),
                hour: hour,
                minute: minute,
                repeatDays: selectedDays.sorted().map(String.init).joined(separator: ","),
                isEnabled: true
            )
            modelContext.insert(newReminder)

            Task {
                await notificationService?.scheduleCustomReminder(newReminder)
            }
        }

        HapticManager.lightTap()
        dismiss()
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    CustomReminderSheet(notificationService: nil)
}
