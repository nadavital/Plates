//
//  PlanReviewCards.swift
//  Plates
//
//  Card views for displaying plan details
//

import SwiftUI

// MARK: - Daily Targets Card

struct DailyTargetsCard: View {
    @Binding var adjustedCalories: String
    @Binding var adjustedProtein: String
    @Binding var adjustedCarbs: String
    @Binding var adjustedFat: String

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Daily Targets", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                Text("Tap to edit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Calories - big and prominent
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("", text: $adjustedCalories)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 160)

                    Text("kcal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("Daily Calories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            Divider()

            // Macros
            HStack(spacing: 16) {
                MacroEditField(
                    value: $adjustedProtein,
                    label: "Protein",
                    color: .blue,
                    icon: "p.circle.fill"
                )

                MacroEditField(
                    value: $adjustedCarbs,
                    label: "Carbs",
                    color: .green,
                    icon: "c.circle.fill"
                )

                MacroEditField(
                    value: $adjustedFat,
                    label: "Fat",
                    color: .yellow,
                    icon: "f.circle.fill"
                )
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 20))
    }
}

// MARK: - Rationale Card

struct RationaleCard: View {
    let rationale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Why This Plan", systemImage: "lightbulb.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.yellow)

            Text(rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Progress Insights Card

struct ProgressInsightsCard: View {
    let insights: NutritionPlan.ProgressInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Progress Timeline", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

            // Weekly change highlight
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Change")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(insights.estimatedWeeklyChange)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(weeklyChangeColor(insights.calorieDeficitOrSurplus))
                }

                Spacer()

                if let timeToGoal = insights.estimatedTimeToGoal {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Time to Goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(timeToGoal)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))

            // Deficit/Surplus indicator
            HStack(spacing: 8) {
                Image(systemName: deficitSurplusIcon(insights.calorieDeficitOrSurplus))
                    .foregroundStyle(weeklyChangeColor(insights.calorieDeficitOrSurplus))

                Text(deficitSurplusText(insights.calorieDeficitOrSurplus))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Milestones
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("First Month")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Text(insights.shortTermMilestone)
                            .font(.subheadline)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Long-Term Outlook")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Text(insights.longTermOutlook)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }

    private func weeklyChangeColor(_ deficitOrSurplus: Int) -> Color {
        if deficitOrSurplus < -100 {
            return .green // Losing weight
        } else if deficitOrSurplus > 100 {
            return .blue // Gaining (muscle building)
        } else {
            return .primary // Maintenance
        }
    }

    private func deficitSurplusIcon(_ value: Int) -> String {
        if value < 0 {
            return "arrow.down.circle.fill"
        } else if value > 0 {
            return "arrow.up.circle.fill"
        } else {
            return "equal.circle.fill"
        }
    }

    private func deficitSurplusText(_ value: Int) -> String {
        if value < 0 {
            return "\(abs(value)) calorie deficit per day"
        } else if value > 0 {
            return "\(value) calorie surplus per day"
        } else {
            return "Maintenance calories"
        }
    }
}

// MARK: - Macro Visualization Card

struct MacroVisualizationCard: View {
    let split: NutritionPlan.MacroSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Macro Split", systemImage: "chart.pie.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)

            // Visual bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(split.proteinPercent) / 100)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(split.carbsPercent) / 100)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(split.fatPercent) / 100)
                }
            }
            .frame(height: 12)
            .clipShape(.rect(cornerRadius: 6))

            // Legend
            HStack(spacing: 20) {
                MacroLegend(label: "Protein", percent: split.proteinPercent, color: .blue)
                MacroLegend(label: "Carbs", percent: split.carbsPercent, color: .green)
                MacroLegend(label: "Fat", percent: split.fatPercent, color: .yellow)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Guidelines Card

struct GuidelinesCard: View {
    let guidelines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tips for Success", systemImage: "star.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.mint)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(guidelines, id: \.self) { guideline in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Text(guideline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 16))
    }
}

// MARK: - Warnings Card

struct WarningsCard: View {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep in Mind", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

            ForEach(warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
    }
}
