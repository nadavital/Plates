//
//  WatchHeartRateCard.swift
//  Trai
//
//  Displays real-time data from Apple Watch during workouts
//

import SwiftUI

/// Card showing live Apple Watch data during workout
struct WatchHeartRateCard: View {
    let heartRate: Double?
    let lastUpdate: Date?
    var calories: Double = 0
    var isConnected: Bool = false

    private var isStale: Bool {
        guard let lastUpdate else { return true }
        // Consider data stale if older than 30 seconds
        return Date().timeIntervalSince(lastUpdate) > 30
    }

    private var heartRateText: String {
        guard let heartRate else { return "--" }
        return "\(Int(heartRate))"
    }

    private var connectionStatus: (text: String, color: Color) {
        if isConnected && !isStale {
            return ("Connected", .green)
        } else if lastUpdate != nil {
            let seconds = Int(Date().timeIntervalSince(lastUpdate!))
            if seconds < 60 {
                return ("Updated \(seconds)s ago", .orange)
            } else {
                return ("Updated \(seconds / 60)m ago", .orange)
            }
        }
        return ("Waiting for Apple Watch...", .secondary)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with connection status
            HStack {
                Image(systemName: "applewatch")
                    .font(.subheadline)
                    .foregroundStyle(isConnected ? .green : .secondary)

                Text("Apple Watch")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // Connection indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectionStatus.color)
                        .frame(width: 6, height: 6)
                    Text(connectionStatus.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Data row
            HStack(spacing: 16) {
                // Heart rate
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "heart.fill")
                            .font(.body)
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating, isActive: heartRate != nil && !isStale)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(heartRateText)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .contentTransition(.numericText())

                            Text("bpm")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Calories
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "flame.fill")
                            .font(.body)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(calories > 0 ? "\(Int(calories))" : "--")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .contentTransition(.numericText())

                            Text("kcal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .animation(.easeInOut(duration: 0.3), value: heartRate)
        .animation(.easeInOut(duration: 0.3), value: calories)
    }
}

// MARK: - Preview

#Preview("Apple Watch Card") {
    VStack(spacing: 16) {
        WatchHeartRateCard(
            heartRate: 142,
            lastUpdate: Date(),
            calories: 234,
            isConnected: true
        )

        WatchHeartRateCard(
            heartRate: 156,
            lastUpdate: Date().addingTimeInterval(-45),
            calories: 180,
            isConnected: false
        )

        WatchHeartRateCard(
            heartRate: nil,
            lastUpdate: nil,
            calories: 0,
            isConnected: false
        )
    }
    .padding()
}
