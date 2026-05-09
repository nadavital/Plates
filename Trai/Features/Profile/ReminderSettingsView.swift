//
//  ReminderSettingsView.swift
//  Trai
//
//  Settings view for configuring meal, workout, and weight reminders.
//

import SwiftUI
import SwiftData

struct ReminderSettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext

    @State private var notificationService: NotificationService?
    @State private var showAddReminderSheet = false
    @State private var customReminders: [CustomReminder] = []
    @State private var reminderSaveErrorMessage: String?

    var body: some View {
        Form {
            // Authorization section
            if let service = notificationService, !service.isAuthorized {
                Section {
                    Button {
                        Task {
                            let granted = await service.requestAuthorization()
                            if granted {
                                await syncBuiltInReminderSchedules()
                            }
                        }
                    } label: {
                        Label("Enable Notifications", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Allow notifications to receive reminders.")
                }
            }

            // Meal Reminders
            Section("Meals") {
                Toggle("Meal Reminders", isOn: $profile.mealRemindersEnabled)

                if profile.mealRemindersEnabled {
                    ForEach(MealReminderTime.allMeals) { meal in
                        Toggle(meal.displayName, isOn: mealBinding(for: meal.id))
                    }
                }
            }

            // Workout Reminders
            Section("Workouts") {
                Toggle("Workout Reminders", isOn: $profile.workoutRemindersEnabled)

                if profile.workoutRemindersEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminder Days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 7], ["S", "M", "T", "W", "T", "F", "S"])), id: \.0) { day, label in
                                dayButton(day: day, label: label)
                            }
                        }
                    }

                    DatePicker(
                        "Reminder Time",
                        selection: workoutTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            // Weight Reminder
            Section("Weight Tracking") {
                Toggle("Weekly Weight Check", isOn: $profile.weightReminderEnabled)

                if profile.weightReminderEnabled {
                    Picker("Day", selection: $profile.weightReminderWeekday) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }

                    DatePicker(
                        "Time",
                        selection: weightTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            // Custom Reminders
            Section {
                ForEach(customReminders) { reminder in
                    NavigationLink {
                        ReminderHabitView(reminder: reminder)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title)
                                    .font(.body)
                                    .foregroundStyle(reminder.isEnabled ? .primary : .secondary)

                                HStack(spacing: 4) {
                                    Text(reminder.formattedTime)
                                    Text("•")
                                    Text(reminder.scheduleDescription)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !reminder.isEnabled {
                                Text("Off")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteReminder(reminder)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showAddReminderSheet = true
                } label: {
                    Label("Add Reminder", systemImage: "plus")
                }
            } header: {
                Text("Custom Reminders")
            } footer: {
                if customReminders.isEmpty {
                    Text("Create custom reminders for anything you want to track.")
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddReminderSheet) {
                CustomReminderSheet(notificationService: notificationService)
            }
            .alert("Reminder Not Updated", isPresented: Binding(
                get: { reminderSaveErrorMessage != nil },
                set: { if !$0 { reminderSaveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reminderSaveErrorMessage ?? "Please try again.")
            }
        .onAppear {
            // Lazily create NotificationService on appear
            if notificationService == nil {
                notificationService = NotificationService()
            }
            Task {
                await notificationService?.updateAuthorizationStatus()
                await syncBuiltInReminderSchedules()
            }
            // Fetch custom reminders
            fetchCustomReminders()
        }
        .onChange(of: showAddReminderSheet) { _, isShowing in
            if !isShowing { fetchCustomReminders() }
        }
        .onChange(of: profile.mealRemindersEnabled) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.enabledMealReminders) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.workoutRemindersEnabled) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.workoutReminderDays) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.workoutReminderHour) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.workoutReminderMinute) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.weightReminderEnabled) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.weightReminderWeekday) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
        .onChange(of: profile.weightReminderHour) { _, _ in
            Task { await syncBuiltInReminderSchedules() }
        }
    }

    // MARK: - Bindings

    private func mealBinding(for mealId: String) -> Binding<Bool> {
        Binding(
            get: {
                profile.enabledMealReminders.contains(mealId)
            },
            set: { isEnabled in
                var meals = Set(profile.enabledMealReminders.split(separator: ",").map(String.init))
                if isEnabled {
                    meals.insert(mealId)
                } else {
                    meals.remove(mealId)
                }
                profile.enabledMealReminders = meals.sorted().joined(separator: ",")
            }
        )
    }

    private var workoutDays: Set<Int> {
        Set(profile.workoutReminderDays.split(separator: ",").compactMap { Int($0) })
    }

    private func dayButton(day: Int, label: String) -> some View {
        Button {
            var days = workoutDays
            if days.contains(day) {
                days.remove(day)
            } else {
                days.insert(day)
            }
            profile.workoutReminderDays = days.sorted().map(String.init).joined(separator: ",")
        } label: {
            Text(label)
                .font(.caption)
                .bold()
                .frame(width: 32, height: 32)
                .background(workoutDays.contains(day) ? Color.accentColor : Color(.tertiarySystemFill))
                .foregroundStyle(workoutDays.contains(day) ? .white : .primary)
                .clipShape(.circle)
        }
        .buttonStyle(.plain)
    }

    private var workoutTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: profile.workoutReminderHour, minute: profile.workoutReminderMinute)
                ) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                profile.workoutReminderHour = components.hour ?? 17
                profile.workoutReminderMinute = components.minute ?? 0
            }
        )
    }

    private var weightTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: profile.weightReminderHour, minute: 0)
                ) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour], from: newDate)
                profile.weightReminderHour = components.hour ?? 8
            }
        )
    }

    // MARK: - Actions

    private func fetchCustomReminders() {
        let descriptor = FetchDescriptor<CustomReminder>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        customReminders = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteReminder(_ reminder: CustomReminder) {
        Task {
            await notificationService?.cancelCustomReminder(id: reminder.id)
        }
        modelContext.delete(reminder)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            reminderSaveErrorMessage = "We couldn’t delete this reminder. Please try again."
            HapticManager.error()
            fetchCustomReminders()
            return
        }
        fetchCustomReminders()
        HapticManager.lightTap()
    }

    @MainActor
    private func syncBuiltInReminderSchedules() async {
        guard let service = notificationService else { return }
        let completedTodayReminderIDs = fetchCompletedReminderIDsForToday()

        await service.updateAuthorizationStatus()
        guard service.isAuthorized else {
            await service.cancelNotifications(category: .mealReminder)
            await service.cancelNotifications(category: .workoutReminder)
            await service.cancelNotifications(category: .weightReminder)
            return
        }

        if profile.mealRemindersEnabled {
            let enabledMeals = Set(profile.enabledMealReminders.split(separator: ",").map(String.init))
            let mealTimes = MealReminderTime.allMeals.filter { enabledMeals.contains($0.id) }
            await service.scheduleMealReminders(
                times: mealTimes,
                skippingTodayReminderIDs: completedTodayReminderIDs
            )
        } else {
            await service.cancelNotifications(category: .mealReminder)
        }

        if profile.workoutRemindersEnabled {
            let workoutDays = Set(profile.workoutReminderDays.split(separator: ",").compactMap { Int($0) })
            await service.scheduleWorkoutReminders(
                days: workoutDays.sorted(),
                hour: profile.workoutReminderHour,
                minute: profile.workoutReminderMinute,
                skippingTodayReminderIDs: completedTodayReminderIDs
            )
        } else {
            await service.cancelNotifications(category: .workoutReminder)
        }

        if profile.weightReminderEnabled {
            await service.scheduleWeightReminder(
                weekday: profile.weightReminderWeekday,
                hour: profile.weightReminderHour,
                minute: 0,
                skippingTodayReminderIDs: completedTodayReminderIDs
            )
        } else {
            await service.cancelNotifications(category: .weightReminder)
        }
    }

    private func fetchCompletedReminderIDsForToday() -> Set<UUID> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ReminderCompletion>(
            predicate: #Predicate { completion in
                completion.completedAt >= startOfDay
            }
        )
        let completions = (try? modelContext.fetch(descriptor)) ?? []
        return Set(completions.map(\.reminderId))
    }
}

#Preview {
    NavigationStack {
        ReminderSettingsView(profile: UserProfile())
    }
}
