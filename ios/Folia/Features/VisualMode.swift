import Foundation

// Folia/Features/VisualMode.swift — generated renderer manifest is the picker source of truth.
struct VisualMode: Decodable, Identifiable {
    var mode: String
    var label: String
    var id: String { mode }
    static var bundled: [VisualMode] {
        guard let url = Bundle.main.url(forResource: "visualizers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([VisualMode].self, from: data), !entries.isEmpty else {
            return [VisualMode(mode: "classic", label: "Classic")]
        }
        return entries
    }
}
