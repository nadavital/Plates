//
//  WorkoutPlanSetupSteps.swift
//  Plates
//
//  Individual step views for workout plan setup flow
//

import SwiftUI

// MARK: - Workout Type Step

struct WorkoutTypeStepView: View {
    @Binding var selection: Set<WorkoutPlanGenerationRequest.WorkoutType>
    @Binding var customText: String

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var showingCustomInput = false
    @FocusState private var isCustomFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "figure.mixed.cardio")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("What kind of training?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Select all that interest you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.WorkoutType.allCases.filter { $0 != .mixed }) { type in
                        WorkoutTypeOptionCard(
                            type: type,
                            isSelected: selection.contains(type)
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selection.contains(type) {
                                    selection.remove(type)
                                } else {
                                    selection.insert(type)
                                    // Clear custom if selecting predefined
                                    if !customText.isEmpty {
                                        customText = ""
                                        showingCustomInput = false
                                    }
                                }
                            }
                        }
                    }

                    // Other/Custom option - full width
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your training style...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        // Clear predefined selections when using custom
                        if !selection.isEmpty {
                            selection.removeAll()
                        }
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
            // If custom text exists, show the input
            if !customText.isEmpty {
                showingCustomInput = true
            }
        }
    }
}

private struct WorkoutTypeOptionCard: View {
    let type: WorkoutPlanGenerationRequest.WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: type.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Experience Step

struct ExperienceStepView: View {
    @Binding var selection: WorkoutPlanGenerationRequest.ExperienceLevel?
    @Binding var customText: String

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var showingCustomInput = false
    @FocusState private var isCustomFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("Your experience level?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("This helps us tailor your plan")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.ExperienceLevel.allCases) { level in
                        ExperienceOptionCard(
                            level: level,
                            isSelected: selection == level && customText.isEmpty
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection = level
                                customText = ""
                                showingCustomInput = false
                            }
                        }
                    }

                    // Custom option
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your experience level...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        selection = nil
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
        }
    }
}

private struct ExperienceOptionCard: View {
    let level: WorkoutPlanGenerationRequest.ExperienceLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: level.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44, alignment: .leading)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding()
            .frame(minHeight: 76)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Equipment Step

struct EquipmentStepView: View {
    @Binding var selection: WorkoutPlanGenerationRequest.EquipmentAccess?
    @Binding var customText: String

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var showingCustomInput = false
    @FocusState private var isCustomFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("What equipment?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("We'll pick exercises that work for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.EquipmentAccess.allCases) { equipment in
                        EquipmentOptionCard(
                            equipment: equipment,
                            isSelected: selection == equipment && customText.isEmpty
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection = equipment
                                customText = ""
                                showingCustomInput = false
                            }
                        }
                    }

                    // Custom option
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your equipment setup...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        selection = nil
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
        }
    }
}

private struct EquipmentOptionCard: View {
    let equipment: WorkoutPlanGenerationRequest.EquipmentAccess
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: equipment.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(equipment.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(equipment.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule Step

struct ScheduleStepView: View {
    @Binding var daysPerWeek: Int?
    @Binding var timePerSession: Int

    @State private var headerVisible = false
    @State private var contentVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "calendar")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("Your schedule?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("How much time can you commit?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Days per week
                VStack(spacing: 16) {
                    Text("Days per week")
                        .font(.headline)

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            ForEach(2...6, id: \.self) { days in
                                DayButton(
                                    days: days,
                                    isSelected: daysPerWeek == days
                                ) {
                                    HapticManager.lightTap()
                                    withAnimation(.spring(response: 0.3)) {
                                        daysPerWeek = days
                                    }
                                }
                            }
                        }

                        // Flexible option
                        Button {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3)) {
                                daysPerWeek = nil
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Flexible / As Available")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(daysPerWeek == nil ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(daysPerWeek == nil ? .white : .primary)
                            .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 30)

                // Time per session
                VStack(spacing: 16) {
                    Text("Typical session length")
                        .font(.headline)

                    VStack(spacing: 12) {
                        Text("\(timePerSession) min")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.accent)

                        Slider(value: Binding(
                            get: { Double(timePerSession) },
                            set: { timePerSession = Int($0) }
                        ), in: 20...90, step: 5)
                        .tint(.accent)
                        .padding(.horizontal)

                        HStack {
                            Text("20 min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("90 min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                contentVisible = true
            }
        }
    }
}

private struct DayButton: View {
    let days: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(days)")
                .font(.title2)
                .bold()
                .frame(width: 50, height: 50)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Split Step

struct SplitStepView: View {
    @Binding var selection: WorkoutPlanGenerationRequest.PreferredSplit?

    @State private var headerVisible = false
    @State private var optionsVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("Preferred training split?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("How do you like to organize your workouts?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options
                VStack(spacing: 12) {
                    ForEach(WorkoutPlanGenerationRequest.PreferredSplit.allCases) { split in
                        SplitOptionCard(
                            split: split,
                            isSelected: selection == split
                        ) {
                            HapticManager.lightTap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection = split
                            }
                        }
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
        }
    }
}

private struct SplitOptionCard: View {
    let split: WorkoutPlanGenerationRequest.PreferredSplit
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: split.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .accent : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(split.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(split.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accent : .secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cardio Step

struct CardioStepView: View {
    @Binding var selection: Set<WorkoutPlanGenerationRequest.CardioType>
    @Binding var customText: String

    @State private var headerVisible = false
    @State private var optionsVisible = false
    @State private var showingCustomInput = false
    @FocusState private var isCustomFocused: Bool

    /// Cardio types excluding anyCardio (replaced with custom)
    private var cardioOptions: [WorkoutPlanGenerationRequest.CardioType] {
        WorkoutPlanGenerationRequest.CardioType.allCases.filter { $0 != .anyCardio }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.accent)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.8)
                    .opacity(headerVisible ? 1 : 0)

                    Text("What cardio do you enjoy?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Select all that apply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -20)
                .padding(.top, 20)

                // Options in grid (even number for clean layout)
                VStack(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(cardioOptions) { cardio in
                            CardioOptionCard(
                                cardio: cardio,
                                isSelected: selection.contains(cardio) && customText.isEmpty
                            ) {
                                HapticManager.lightTap()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selection.contains(cardio) {
                                        selection.remove(cardio)
                                    } else {
                                        selection.insert(cardio)
                                        // Clear custom when selecting predefined
                                        customText = ""
                                        showingCustomInput = false
                                    }
                                }
                            }
                        }
                    }

                    // Custom option - full width
                    CustomInputCard(
                        title: "Other",
                        placeholder: "Describe your preferred cardio...",
                        customText: $customText,
                        isExpanded: $showingCustomInput,
                        isFocused: $isCustomFocused
                    ) {
                        selection.removeAll()
                    }
                }
                .opacity(optionsVisible ? 1 : 0)
                .offset(y: optionsVisible ? 0 : 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                optionsVisible = true
            }
        }
    }
}

private struct CardioOptionCard: View {
    let cardio: WorkoutPlanGenerationRequest.CardioType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: cardio.iconName)
                    .font(.title)
                    .foregroundStyle(isSelected ? .accent : .secondary)

                Text(cardio.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generating Step

struct GeneratingStepView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }

                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(.accent)
            }

            VStack(spacing: 12) {
                Text("Creating your plan...")
                    .font(.title2)
                    .bold()

                Text("Trai is designing a personalized workout program just for you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }
}

// MARK: - Review Step

struct ReviewStepView: View {
    let plan: WorkoutPlan
    let onCustomize: () -> Void
    let onRestart: () -> Void

    @State private var headerVisible = false
    @State private var contentVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Success header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    .scaleEffect(headerVisible ? 1 : 0.5)
                    .opacity(headerVisible ? 1 : 0)

                    Text("Your Plan is Ready!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Review your personalized workout program")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(headerVisible ? 1 : 0)
                .padding(.top, 20)

                // Plan summary
                planSummaryCard
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 20)

                // Templates preview
                templatesPreview
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 20)

                // Rationale
                rationaleCard
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 20)

                // Action buttons
                actionButtons
                    .opacity(contentVisible ? 1 : 0)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerVisible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2)) {
                contentVisible = true
            }
        }
    }

    private var planSummaryCard: some View {
        VStack(spacing: 16) {
            Image(systemName: plan.splitType.iconName)
                .font(.largeTitle)
                .foregroundStyle(.accent)

            Text(plan.splitType.displayName)
                .font(.title2)
                .bold()

            HStack(spacing: 24) {
                VStack {
                    Text("\(plan.daysPerWeek)")
                        .font(.title)
                        .bold()
                    Text("days/week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("\(plan.templates.count)")
                        .font(.title)
                        .bold()
                    Text("workouts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text("~\(plan.templates.first?.estimatedDurationMinutes ?? 45)")
                        .font(.title)
                        .bold()
                    Text("min each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var templatesPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Workouts")
                .font(.headline)

            ForEach(plan.templates) { template in
                HStack {
                    Circle()
                        .fill(.accent)
                        .frame(width: 8, height: 8)

                    Text(template.name)
                        .font(.subheadline)

                    Spacer()

                    Text("\(template.exerciseCount) exercises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private var rationaleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why This Plan?")
                .font(.headline)

            Text(plan.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onCustomize) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                    Text("Customize with Trai")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.accent)

            Button(action: onRestart) {
                Label("Start Over", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Custom Input Card (Reusable)

private struct CustomInputCard: View {
    let title: String
    let placeholder: String
    @Binding var customText: String
    @Binding var isExpanded: Bool
    var isFocused: FocusState<Bool>.Binding
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                HapticManager.lightTap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    if isExpanded {
                        onExpand()
                        isFocused.wrappedValue = true
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "pencil.line")
                        .font(.title2)
                        .foregroundStyle(isExpanded || !customText.isEmpty ? .accent : .secondary)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text("Describe something not listed above")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(isExpanded || !customText.isEmpty ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: isExpanded ? 16 : 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                TextField(placeholder, text: $customText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .focused(isFocused)
                    .padding()
                    .background(Color(.tertiarySystemFill))
                    .clipShape(.rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
            }
        }
        .overlay {
            if isExpanded || !customText.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}

// MARK: - Previews

#Preview("Workout Type") {
    WorkoutTypeStepView(selection: .constant([]), customText: .constant(""))
}

#Preview("Experience") {
    ExperienceStepView(selection: .constant(nil), customText: .constant(""))
}

#Preview("Schedule") {
    ScheduleStepView(daysPerWeek: .constant(3), timePerSession: .constant(45))
}

#Preview("Cardio") {
    CardioStepView(selection: .constant([]), customText: .constant(""))
}
