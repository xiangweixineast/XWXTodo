import SwiftUI

struct TodoRowView: View {
    let todo: TodoItem
    let onStart: () -> Void
    let onPause: () -> Void
    let onDone: () -> Void
    let onEdit: (String) -> Bool
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var draftTitle: String

    init(
        todo: TodoItem,
        onStart: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onEdit: @escaping (String) -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self.todo = todo
        self.onStart = onStart
        self.onPause = onPause
        self.onDone = onDone
        self.onEdit = onEdit
        self.onDelete = onDelete
        _draftTitle = State(initialValue: todo.title)
    }

    var body: some View {
        HStack(spacing: 10) {
            statusMarker

            if isEditing {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .colorScheme(.light)
                    .foregroundStyle(.black)
                    .onSubmit(saveEdit)

                Button("Save", action: saveEdit)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedDraftTitle.isEmpty)

                Button("Cancel", action: cancelEdit)
                    .buttonStyle(.bordered)
            } else {
                Text(todo.title)
                    .font(.system(size: 13, weight: todo.status == .doing ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if todo.status == .doing {
                    Button("Pause", action: onPause)
                        .buttonStyle(.bordered)
                } else {
                    Button("Start", action: onStart)
                        .buttonStyle(.bordered)
                }

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)

                Button("Edit") {
                    draftTitle = todo.title
                    isEditing = true
                }
                .buttonStyle(.bordered)

                Button("Delete", action: onDelete)
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
            }
        }
        .controlSize(.small)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(rowBackground)
        .onChange(of: todo.title) { _, newTitle in
            guard !isEditing else { return }
            draftTitle = newTitle
        }
    }

    private var statusMarker: some View {
        Circle()
            .fill(todo.status == .doing ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 8, height: 8)
            .accessibilityLabel(todo.status == .doing ? "Doing" : "Pending")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(todo.status == .doing ? Color.green.opacity(0.10) : Color.white.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(todo.status == .doing ? 0.16 : 0.08), lineWidth: 1)
            }
    }

    private var trimmedDraftTitle: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveEdit() {
        guard !trimmedDraftTitle.isEmpty else { return }
        guard onEdit(trimmedDraftTitle) else { return }

        draftTitle = trimmedDraftTitle
        isEditing = false
    }

    private func cancelEdit() {
        draftTitle = todo.title
        isEditing = false
    }
}
