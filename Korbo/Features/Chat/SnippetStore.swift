import SwiftUI

/// Persisted library of reusable prompt snippets ("magic prompts").
@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    private let storageKey = "korbo.snippets"

    @Published var snippets: [Snippet] = []

    private init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else {
            // Seed defaults on first run
            snippets = Self.defaultSnippets
            save()
            return
        }
        snippets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: CRUD

    func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[idx] = snippet
        save()
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        snippets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Defaults

    private static let defaultSnippets: [Snippet] = [
        Snippet(title: "Explain selection", text: "Explain the selected code in detail."),
        Snippet(title: "Add tests", text: "Write comprehensive unit tests for this code."),
        Snippet(title: "Refactor for readability", text: "Refactor this code to improve readability and maintainability."),
        Snippet(title: "Write commit message", text: "Generate a clear, conventional commit message for the staged changes.")
    ]
}

// MARK: - Snippet Model

struct Snippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var text: String
}
