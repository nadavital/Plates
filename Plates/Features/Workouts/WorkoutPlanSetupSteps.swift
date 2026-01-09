//
//  WorkoutPlanSetupSteps.swift
//  Plates
//
//  Schedule and generating step views for workout plan setup, plus shared components
//

import SwiftUI

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

// MARK: - Custom Input Card (Shared Component)

struct CustomInputCard: View {
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

#Preview("Schedule") {
    ScheduleStepView(daysPerWeek: .constant(3), timePerSession: .constant(45))
}

#Preview("Generating") {
    GeneratingStepView()
}
