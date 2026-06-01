import SwiftUI

/// Sheet presenting the snippets library with list, add/edit/delete functionality.
struct SnippetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SnippetStore

    @State private var editingSnippet: Snippet?
    @State private var isAddingNew = false

    let onSelect: (Snippet) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if store.snippets.isEmpty {
                        Text("No snippets yet. Tap + to add one.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(store.snippets) { snippet in
                            snippetRow(snippet)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Snippets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add snippet")
                }
            }
            .sheet(item: $editingSnippet) { snippet in
                SnippetEditorSheet(snippet: snippet) { updated in
                    store.update(updated)
                }
            }
            .sheet(isPresented: $isAddingNew) {
                SnippetEditorSheet(snippet: nil) { newSnippet in
                    store.add(newSnippet)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                onSelect(snippet)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snippet.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(snippet.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    editingSnippet = snippet
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                if let idx = store.snippets.firstIndex(of: snippet) {
                    if idx > 0 {
                        Button {
                            store.move(from: IndexSet(integer: idx), to: idx - 1)
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                    }
                    if idx < store.snippets.count - 1 {
                        Button {
                            store.move(from: IndexSet(integer: idx), to: idx + 2)
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                    }
                }
                Button(role: .destructive) {
                    store.delete(snippet)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Snippet options")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.panelRaised)
        )
        .contextMenu {
            Button {
                editingSnippet = snippet
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.delete(snippet)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Editor form for creating or editing a snippet.
struct SnippetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var text: String
    private let existingSnippet: Snippet?

    let onSave: (Snippet) -> Void

    init(snippet: Snippet?, onSave: @escaping (Snippet) -> Void) {
        self.existingSnippet = snippet
        self.onSave = onSave
        _title = State(initialValue: snippet?.title ?? "")
        _text = State(initialValue: snippet?.text ?? "")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Explain selection", text: $title)
                }
                Section("Prompt Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(existingSnippet == nil ? "New Snippet" : "Edit Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        var snippet = existingSnippet ?? Snippet(title: "", text: "")
        snippet.title = title.trimmingCharacters(in: .whitespaces)
        snippet.text = text.trimmingCharacters(in: .whitespaces)
        onSave(snippet)
        dismiss()
    }
}
