import Foundation

struct TopicGroup: Codable, Identifiable {
    let name: String
    let topics: [String]

    var id: String {
        name
    }
}

struct TopicStore {
    let topicGroups: [TopicGroup]
    let topics: [String]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "topics", withExtension: "json") else {
            print("Missing bundled topics.json; using fallback topic.")
            topicGroups = Self.fallbackTopicGroups
            topics = Self.fallbackTopics
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decodedGroups = try Self.decodeTopicGroups(from: data)
            topicGroups = decodedGroups.isEmpty ? Self.fallbackTopicGroups : decodedGroups
            topics = topicGroups.flatMap(\.topics)
        } catch {
            print("Could not load topics.json: \(error.localizedDescription)")
            topicGroups = Self.fallbackTopicGroups
            topics = Self.fallbackTopics
        }
    }

    func topics(in groupName: String?) -> [String] {
        guard let groupName, !groupName.isEmpty else {
            return topics
        }

        return topicGroups.first { $0.name == groupName }?.topics ?? topics
    }

    func randomTopic() -> String {
        topics.randomElement() ?? Self.fallbackTopics[0]
    }

    private static func decodeTopicGroups(from data: Data) throws -> [TopicGroup] {
        let decoder = JSONDecoder()

        if let topicGroups = try? decoder.decode([TopicGroup].self, from: data) {
            return topicGroups.filter { !$0.name.isEmpty && !$0.topics.isEmpty }
        }

        let flatTopics = try decoder.decode([String].self, from: data)
        return [
            TopicGroup(name: "General", topics: flatTopics)
        ]
    }

    private static let fallbackTopics = [
        "Cardiac action potentials",
        "DiGeorge syndrome",
        "Nephron physiology"
    ]

    private static let fallbackTopicGroups = [
        TopicGroup(name: "General", topics: fallbackTopics)
    ]
}
