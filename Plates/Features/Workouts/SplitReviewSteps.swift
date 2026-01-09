//
//  SplitReviewSteps.swift
//  Plates
//
//  Split selection and plan review step views for workout plan setup
//

import SwiftUI

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

// MARK: - Previews

#Preview("Split") {
    SplitStepView(selection: .constant(nil))
}
