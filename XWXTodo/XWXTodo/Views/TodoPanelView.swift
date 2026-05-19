import SwiftUI

struct TodoPanelView: View {
    @ObservedObject var store: TodoStore
    let onHoverChanged: (Bool) -> Void

    @State private var newTitle = ""
    @State private var localError: String?
    @State private var isShowingCompleted = false
    @State private var isPerformingAction = false

    var body: some View {
        VStack(spacing: 12) {
            if let message = localError ?? store.errorMessage {
                ErrorBannerView(message: message)
            }

            if isShowingCompleted {
                CompletedListView(store: store) {
                    isShowingCompleted = false
                }
            } else {
                addTodoBar
                activeList
                footer
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: OverlayMetrics.panelWidth, height: OverlayMetrics.panelHeight)
        .background(Color.black)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: OverlayMetrics.notchCornerRadius,
                    bottomTrailing: OverlayMetrics.notchCornerRadius,
                    topTrailing: 0
                )
            )
        )
        .foregroundStyle(.white)
        .onHover(perform: onHoverChanged)
    }

    private var addTodoBar: some View {
        HStack(spacing: 8) {
            TextField("New TODO", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .colorScheme(.light)
                .foregroundStyle(.black)
                .disabled(isPerformingAction)
                .onSubmit(addTodo)

            Button("Add", action: addTodo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isAddDisabled)
        }
    }

    private var activeList: some View {
        Group {
            if store.activeTodos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No active todos")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.activeTodos) { todo in
                            TodoRowView(
                                todo: todo,
                                isBusy: isPerformingAction,
                                onStart: {
                                    await perform {
                                        try await store.startTodo(id: todo.id)
                                    }
                                },
                                onPause: {
                                    await perform {
                                        try await store.pauseTodo(id: todo.id)
                                    }
                                },
                                onDone: {
                                    await perform {
                                        try await store.completeTodo(id: todo.id)
                                    }
                                },
                                onEdit: { title in
                                    await perform {
                                        try await store.editTodo(id: todo.id, title: title)
                                    }
                                },
                                onDelete: {
                                    await perform {
                                        try await store.deleteTodo(id: todo.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(store.activeTodos.count) active")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Completed") {
                isShowingCompleted = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func addTodo() {
        let title = newTitle
        Task {
            let didAdd = await perform {
                try await store.addTodo(title: title)
            }
            if didAdd {
                newTitle = ""
            }
        }
    }

    private var trimmedNewTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAddDisabled: Bool {
        isPerformingAction || trimmedNewTitle.isEmpty
    }

    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        guard !isPerformingAction else { return false }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await action()
            localError = nil
            return true
        } catch {
            localError = error.localizedDescription
            return false
        }
    }
}
