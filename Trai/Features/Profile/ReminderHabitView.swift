//
//  ReminderHabitView.swift
//  Trai
//
//  Shows completion history for a custom reminder.
//

import SwiftUI
import SwiftData

struct ReminderHabitView: View {
    let reminder: CustomReminder
    @Environment(\.modelContext) private var modelContext
    @State private var completions: [ReminderCompletion] = []
    @State private var showEditSheet = false
    @State private var notificationService = NotificationService()

    var body: some View {
        List {
            // Reminder details section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if !reminder.body.isEmpty {
                        Text(reminder.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        Label(reminder.formattedTime, systemImage: "clock")
                        Label(reminder.scheduleDescription, systemImage: "repeat")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Details")
                    Spacer()
                    if !reminder.isEnabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Stats section
            Section("Stats") {
                HStack {
                    Text("Total Completions")
                    Spacer()
                    Text("\(completions.count)")
                        .foregroundStyle(.secondary)
                }

                if let firstCompletion = completions.last {
                    HStack {
                        Text("First Completed")
                        Spacer()
                        Text(firstCompletion.completedAt.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastCompletion = completions.first {
                    HStack {
                        Text("Last Completed")
                        Spacer()
                        Text(lastCompletion.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Recent completions
            Section("History") {
                if completions.isEmpty {
                    Text("No completions yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(completions.prefix(20)) { completion in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            Text(completion.completedAt.formatted(date: .abbreviated, time: .shortened))

                            Spacer()

                            Text("Completed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if completions.count > 20 {
                        Text("+\(completions.count - 20) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .navigationTitle(reminder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .onAppear {
            fetchCompletions()
            Task {
                await notificationService.updateAuthorizationStatus()
            }
        }
        .sheet(isPresented: $showEditSheet) {
            CustomReminderSheet(reminder: reminder, notificationService: notificationService)
        }
        .onChange(of: showEditSheet) { _, isShowing in
            if !isShowing { fetchCompletions() }
        }
    }

    private func fetchCompletions() {
        let reminderId = reminder.id
        let descriptor = FetchDescriptor<ReminderCompletion>(
            predicate: #Predicate { $0.reminderId == reminderId },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        completions = (try? modelContext.fetch(descriptor)) ?? []
    }
}

#Preview {
    NavigationStack {
        ReminderHabitView(
            reminder: CustomReminder(
                title: "Drink Water",
                body: "Stay hydrated",
                hour: 10,
                minute: 0,
                repeatDays: "",
                isEnabled: true
            )
        )
    }
}
