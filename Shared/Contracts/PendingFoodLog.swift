//
//  PendingFoodLog.swift
//  Shared
//
//  Widget quick-log payload shared between app and widget extension.
//

import Foundation

struct PendingFoodLog: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let calories: Int
    let protein: Int
    let loggedAt: Date
    let mealType: String

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        protein: Int,
        loggedAt: Date,
        mealType: String
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.loggedAt = loggedAt
        self.mealType = mealType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        calories = try container.decode(Int.self, forKey: .calories)
        protein = try container.decode(Int.self, forKey: .protein)
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
        mealType = try container.decode(String.self, forKey: .mealType)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.legacyID(
            name: name,
            calories: calories,
            protein: protein,
            loggedAt: loggedAt,
            mealType: mealType
        )
    }

    private static func legacyID(
        name: String,
        calories: Int,
        protein: Int,
        loggedAt: Date,
        mealType: String
    ) -> UUID {
        let rawValue = [
            name,
            String(calories),
            String(protein),
            String(loggedAt.timeIntervalSinceReferenceDate),
            mealType
        ].joined(separator: "\u{1F}")

        var first = UInt64(14_695_981_039_346_656_037)
        var second = UInt64(1_099_511_628_211)

        for byte in rawValue.utf8 {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211

            second ^= UInt64(byte)
            second &*= 14_695_981_039_346_656_037
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        withUnsafeBytes(of: first.bigEndian) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: second.bigEndian) { bytes.append(contentsOf: $0) }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum PendingFoodLogQueue {
    static func load(from defaults: UserDefaults) -> [PendingFoodLog] {
        guard let data = defaults.data(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs),
              let logs = try? JSONDecoder().decode([PendingFoodLog].self, from: data) else {
            return []
        }
        return logs
    }

    static func append(_ log: PendingFoodLog, to defaults: UserDefaults) throws {
        var logs = load(from: defaults)
        guard !logs.contains(where: { $0.id == log.id }) else { return }
        logs.append(log)
        try save(logs, to: defaults)
    }

    static func remove(ids: Set<UUID>, from defaults: UserDefaults) throws {
        guard !ids.isEmpty else { return }

        let logs = load(from: defaults)
        let remainingLogs = logs.filter { !ids.contains($0.id) }

        guard !remainingLogs.isEmpty else {
            defaults.removeObject(forKey: SharedStorageKeys.AppGroup.pendingFoodLogs)
            return
        }

        try save(remainingLogs, to: defaults)
    }

    static func save(_ logs: [PendingFoodLog], to defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(logs)
        defaults.set(data, forKey: SharedStorageKeys.AppGroup.pendingFoodLogs)
    }
}
