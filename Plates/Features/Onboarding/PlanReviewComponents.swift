//
//  PlanReviewComponents.swift
//  Plates
//
//  Supporting components for the plan review step
//

import SwiftUI

// MARK: - Macro Edit Field

struct MacroEditField: View {
    @Binding var value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            HStack(spacing: 2) {
                TextField("", text: $value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)

                Text("g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Macro Legend

struct MacroLegend: View {
    let label: String
    let percent: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text("\(label) \(percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Loading Step

struct LoadingStep: View {
    let text: String
    let stepIndex: Int

    @State private var dotCount = 0
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 28, height: 28)

                ProgressView()
                    .scaleEffect(0.7)
            }

            Text(text + String(repeating: ".", count: dotCount))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Spacer()
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -20)
        .onAppear {
            // Staggered appearance
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(stepIndex) * 0.15)) {
                isVisible = true
            }

            // Animate dots
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}
