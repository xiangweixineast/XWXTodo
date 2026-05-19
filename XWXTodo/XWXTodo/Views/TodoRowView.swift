import SwiftUI

struct TodoRowView: View {
    let todo: TodoItem
    let isBusy: Bool
    let onStart: () async -> Void
    let onPause: () async -> Void
    let onDone: () async -> Void
    let onEdit: (String) async -> Bool
    let onDelete: () async -> Void

    @State private var isEditing = false
    @State private var draftTitle: String

    init(
        todo: TodoItem,
        isBusy: Bool,
        onStart: @escaping () async -> Void,
        onPause: @escaping () async -> Void,
        onDone: @escaping () async -> Void,
        onEdit: @escaping (String) async -> Bool,
        onDelete: @escaping () async -> Void
    ) {
        self.todo = todo
        self.isBusy = isBusy
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
                    .disabled(isBusy)
                    .onSubmit(saveEdit)

                Button("Save", action: saveEdit)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || trimmedDraftTitle.isEmpty)

                Button("Cancel", action: cancelEdit)
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
            } else {
                Text(todo.title)
                    .font(.system(size: 13, weight: todo.status == .doing ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if todo.status == .doing {
                    Button("Pause") {
                        Task { await onPause() }
                    }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                } else {
                    Button("Start") {
                        Task { await onStart() }
                    }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }

                Button("Done") {
                    Task { await onDone() }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)

                Button("Edit") {
                    draftTitle = todo.title
                    isEditing = true
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button("Delete") {
                    Task { await onDelete() }
                }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .disabled(isBusy)
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
        guard !isBusy else { return }
        guard !trimmedDraftTitle.isEmpty else { return }

        let title = trimmedDraftTitle
        Task {
            guard await onEdit(title) else { return }

            draftTitle = title
            isEditing = false
        }
    }

    private func cancelEdit() {
        draftTitle = todo.title
        isEditing = false
    }
}
