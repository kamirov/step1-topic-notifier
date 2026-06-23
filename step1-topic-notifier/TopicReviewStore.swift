import Foundation

enum TopicReviewRating: String, Codable {
    case again
    case soSo
    case good

    var opensSearch: Bool {
        switch self {
        case .again, .soSo:
            return true
        case .good:
            return false
        }
    }
}

struct TopicReviewRecord: Codable {
    var lastReviewedAt: TimeInterval
    var nextDueAt: TimeInterval
    var reviewCount: Int
    var easeFactor: Double
    var intervalSeconds: TimeInterval
    var lastRating: TopicReviewRating
}

struct TroubleTopic: Identifiable {
    let topic: String
    let score: Int
    let lastRating: TopicReviewRating
    let reviewCount: Int
    let nextDueAt: TimeInterval

    var id: String {
        topic
    }
}

final class TopicReviewStore {
    private enum Constants {
        static let defaultsKey = "topicReviewRecords"
        static let minimumEaseFactor = 1.3
        static let defaultEaseFactor = 2.5
        static let againInterval: TimeInterval = 5 * 60
        static let soSoBaseInterval: TimeInterval = 24 * 60 * 60
        static let goodBaseInterval: TimeInterval = 3 * 24 * 60 * 60
        static let oneDay: TimeInterval = 24 * 60 * 60
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func nextTopic(from topics: [String], now: Date = Date()) -> String {
        guard !topics.isEmpty else {
            return "Cardiac action potentials"
        }

        let records = reviewRecords()
        let nowInterval = now.timeIntervalSince1970
        let topicSet = Set(topics)

        let dueTopics = records
            .filter { topicSet.contains($0.key) && $0.value.nextDueAt <= nowInterval }
            .sorted { lhs, rhs in
                if lhs.value.nextDueAt == rhs.value.nextDueAt {
                    return lhs.key < rhs.key
                }
                return lhs.value.nextDueAt < rhs.value.nextDueAt
            }

        if let dueTopic = dueTopics.first?.key {
            return dueTopic
        }

        let unseenTopics = topics.filter { records[$0] == nil }
        if let unseenTopic = unseenTopics.randomElement() {
            return unseenTopic
        }

        let earliestScheduledTopic = records
            .filter { topicSet.contains($0.key) }
            .sorted { lhs, rhs in
                if lhs.value.nextDueAt == rhs.value.nextDueAt {
                    return lhs.key < rhs.key
                }
                return lhs.value.nextDueAt < rhs.value.nextDueAt
            }
            .first?
            .key

        return earliestScheduledTopic ?? topics.randomElement() ?? topics[0]
    }

    func recordReview(for topic: String, rating: TopicReviewRating, now: Date = Date()) {
        var records = reviewRecords()
        let currentRecord = records[topic]
        let updatedRecord = updatedRecord(from: currentRecord, rating: rating, now: now)

        records[topic] = updatedRecord
        save(records: records)
    }

    func troubleTopics(from topics: [String], limit: Int, now: Date = Date()) -> [TroubleTopic] {
        guard limit > 0 else { return [] }

        let records = reviewRecords()
        let topicSet = Set(topics)

        return records
            .filter { topicSet.contains($0.key) }
            .map { topic, record in
                TroubleTopic(
                    topic: topic,
                    score: weaknessScore(for: record, now: now),
                    lastRating: record.lastRating,
                    reviewCount: record.reviewCount,
                    nextDueAt: record.nextDueAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    if lhs.nextDueAt == rhs.nextDueAt {
                        return lhs.topic < rhs.topic
                    }
                    return lhs.nextDueAt < rhs.nextDueAt
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func updatedRecord(
        from record: TopicReviewRecord?,
        rating: TopicReviewRating,
        now: Date
    ) -> TopicReviewRecord {
        let nowInterval = now.timeIntervalSince1970
        let previousEase = record?.easeFactor ?? Constants.defaultEaseFactor
        let previousInterval = record?.intervalSeconds ?? 0
        let nextReviewCount = (record?.reviewCount ?? 0) + 1

        let nextEase: Double
        let nextInterval: TimeInterval

        switch rating {
        case .again:
            nextEase = max(Constants.minimumEaseFactor, previousEase - 0.25)
            nextInterval = Constants.againInterval

        case .soSo:
            nextEase = max(Constants.minimumEaseFactor, previousEase - 0.1)
            nextInterval = max(Constants.soSoBaseInterval, previousInterval * 1.2)

        case .good:
            nextEase = previousEase + 0.05
            if previousInterval > 0 {
                nextInterval = max(Constants.goodBaseInterval, previousInterval * nextEase)
            } else {
                nextInterval = Constants.goodBaseInterval
            }
        }

        return TopicReviewRecord(
            lastReviewedAt: nowInterval,
            nextDueAt: nowInterval + nextInterval,
            reviewCount: nextReviewCount,
            easeFactor: nextEase,
            intervalSeconds: nextInterval,
            lastRating: rating
        )
    }

    private func weaknessScore(for record: TopicReviewRecord, now: Date) -> Int {
        let ratingScore: Double
        switch record.lastRating {
        case .again:
            ratingScore = 55
        case .soSo:
            ratingScore = 35
        case .good:
            ratingScore = 10
        }

        let easeRange = Constants.defaultEaseFactor - Constants.minimumEaseFactor
        let easePenalty = ((Constants.defaultEaseFactor - record.easeFactor) / easeRange) * 25
        let overdueSeconds = max(0, now.timeIntervalSince1970 - record.nextDueAt)
        let overduePenalty = min(20, (overdueSeconds / Constants.oneDay) * 10)
        let reviewPenalty = min(10, Double(record.reviewCount))
        let score = ratingScore + easePenalty + overduePenalty + reviewPenalty

        return Int(min(100, max(0, score)).rounded())
    }

    private func reviewRecords() -> [String: TopicReviewRecord] {
        guard let data = defaults.data(forKey: Constants.defaultsKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: TopicReviewRecord].self, from: data)
        } catch {
            print("Could not load topic review records: \(error.localizedDescription)")
            return [:]
        }
    }

    private func save(records: [String: TopicReviewRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            defaults.set(data, forKey: Constants.defaultsKey)
        } catch {
            print("Could not save topic review records: \(error.localizedDescription)")
        }
    }
}
