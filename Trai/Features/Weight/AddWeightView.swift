//
//  AddWeightView.swift
//  Trai
//
//  Created by Nadav Avital on 12/25/25.
//

import SwiftUI
import SwiftData

struct AddWeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weight = ""
    @State private var bodyFat = ""
    @State private var notes = ""
    @State private var entryDate = Date()
    @State private var saveToHealthKit = true

    @State private var healthKitService = HealthKitService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("75.0", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Body Fat % (optional)")
                        Spacer()
                        TextField("—", text: $bodyFat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text("Measurements")
                }

                Section {
                    DatePicker("Date", selection: $entryDate, displayedComponents: [.date, .hourAndMinute])

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Toggle("Save to Apple Health", isOn: $saveToHealthKit)
                } footer: {
                    Text("Also save this weight entry to Apple Health")
                }

                Section {
                    Button("Save Entry", systemImage: "checkmark.circle.fill") {
                        saveEntry()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(weight.isEmpty)
                }
            }
            .navigationTitle("Add Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveEntry() {
        guard let weightValue = Double(weight) else { return }

        let entry = WeightEntry(weightKg: weightValue, loggedAt: entryDate)
        entry.bodyFatPercentage = Double(bodyFat)
        entry.notes = notes.isEmpty ? nil : notes

        modelContext.insert(entry)

        // Save to HealthKit if enabled
        if saveToHealthKit {
            Task {
                try? await healthKitService.requestAuthorization()
                try? await healthKitService.saveWeight(weightValue, date: entryDate)
            }
        }

        dismiss()
    }
}

#Preview {
    AddWeightView()
        .modelContainer(for: WeightEntry.self, inMemory: true)
}
