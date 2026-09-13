import Foundation
import Observation

enum UsageOutcome: String, Codable, Sendable {
    case completed
    case empty
    case cancelled
    case failed
}

struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    var day: Date
    var providerID: String
    var audioSeconds: Double
    var sessions: Int
    var completed: Int
    var empty: Int
    var cancelled: Int
    var failed: Int
    var words: Int
    var characters: Int

    var id: String {
        "\(day.timeIntervalSinceReferenceDate)-\(providerID)"
    }
}

struct UsageSummary: Equatable, Sendable {
    var audioSeconds: Double = 0
    var sessions: Int = 0
    var completed: Int = 0
    var empty: Int = 0
    var cancelled: Int = 0
    var failed: Int = 0
    var words: Int = 0
    var characters: Int = 0

    var successRate: Double {
        guard sessions > 0 else { return 0 }
        return Double(completed) / Double(sessions)
    }
}

struct UsageDayBucket: Identifiable, Sendable {
    var day: Date
    var audioSeconds: Double
    var id: Date { day }
}

@MainActor
@Observable
final class UsageStore {
    private(set) var days: [DailyUsage]

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let storageKey = "usage.daily.v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([DailyUsage].self, from: data) {
            days = stored
        } else {
            days = []
        }
    }

    func record(
        providerID: String,
        audioSeconds: Double,
        outcome: UsageOutcome,
        transcript: String = "",
        at date: Date = .now
    ) {
        let day = calendar.startOfDay(for: date)
        let words = transcript.split(whereSeparator: { $0.isWhitespace }).count
        let characters = transcript.count

        if let index = days.firstIndex(where: {
            calendar.isDate($0.day, inSameDayAs: day) && $0.providerID == providerID
        }) {
            days[index].audioSeconds += max(0, audioSeconds)
            days[index].sessions += 1
            days[index].words += words
            days[index].characters += characters
            apply(outcome, to: &days[index])
        } else {
            var entry = DailyUsage(
                day: day,
                providerID: providerID,
                audioSeconds: max(0, audioSeconds),
                sessions: 1,
                completed: 0,
                empty: 0,
                cancelled: 0,
                failed: 0,
                words: words,
                characters: characters
            )
            apply(outcome, to: &entry)
            days.append(entry)
        }

        days.sort { $0.day < $1.day }
        save()
    }

    func summary(since startDate: Date) -> UsageSummary {
        days
            .filter { $0.day >= calendar.startOfDay(for: startDate) }
            .reduce(into: UsageSummary()) { result, entry in
                result.add(entry)
            }
    }

    func currentMonthSummary(at date: Date = .now) -> UsageSummary {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return summary(since: start)
    }

    func providerSummaries(since startDate: Date) -> [(providerID: String, summary: UsageSummary)] {
        var grouped: [String: UsageSummary] = [:]
        for entry in days where entry.day >= calendar.startOfDay(for: startDate) {
            grouped[entry.providerID, default: UsageSummary()].add(entry)
        }
        return grouped
            .map { (providerID: $0.key, summary: $0.value) }
            .sorted { $0.summary.audioSeconds > $1.summary.audioSeconds }
    }

    func lastSevenDays(ending date: Date = .now) -> [UsageDayBucket] {
        let end = calendar.startOfDay(for: date)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let seconds = days
                .filter { calendar.isDate($0.day, inSameDayAs: day) }
                .reduce(0) { $0 + $1.audioSeconds }
            return UsageDayBucket(day: day, audioSeconds: seconds)
        }
    }

    func reset() {
        days = []
        defaults.removeObject(forKey: storageKey)
    }

    private func apply(_ outcome: UsageOutcome, to entry: inout DailyUsage) {
        switch outcome {
        case .completed: entry.completed += 1
        case .empty: entry.empty += 1
        case .cancelled: entry.cancelled += 1
        case .failed: entry.failed += 1
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private extension UsageSummary {
    mutating func add(_ entry: DailyUsage) {
        audioSeconds += entry.audioSeconds
        sessions += entry.sessions
        completed += entry.completed
        empty += entry.empty
        cancelled += entry.cancelled
        failed += entry.failed
        words += entry.words
        characters += entry.characters
    }
}

final class UsageSessionMeter: @unchecked Sendable {
    let providerID: String
    private let bytesPerSecond: Double
    private let lock = NSLock()
    private var audioBytes = 0

    init(providerID: String, sampleRate: Int) {
        self.providerID = providerID
        bytesPerSecond = Double(sampleRate * MemoryLayout<Int16>.size)
    }

    func addAudioBytes(_ count: Int) {
        lock.withLock {
            audioBytes += max(0, count)
        }
    }

    var audioSeconds: Double {
        lock.withLock {
            guard bytesPerSecond > 0 else { return 0 }
            return Double(audioBytes) / bytesPerSecond
        }
    }
}
