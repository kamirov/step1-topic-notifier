import Foundation

struct TopicStore {
    let topics: [String]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "topics", withExtension: "json") else {
            print("Missing bundled topics.json; using fallback topic.")
            topics = Self.fallbackTopics
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decodedTopics = try JSONDecoder().decode([String].self, from: data)
            topics = decodedTopics.isEmpty ? Self.fallbackTopics : decodedTopics
        } catch {
            print("Could not load topics.json: \(error.localizedDescription)")
            topics = Self.fallbackTopics
        }
    }

    func randomTopic() -> String {
        topics.randomElement() ?? Self.fallbackTopics[0]
    }

    private static let fallbackTopics = [
        "Cardiac action potentials",
        "DiGeorge syndrome",
        "Nephron physiology"
    ]
}
