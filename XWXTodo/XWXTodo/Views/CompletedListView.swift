import SwiftUI

struct CompletedListView: View {
    @ObservedObject var store: TodoStore
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Text("Completed")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(store.completedTodos.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if store.completedTodos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No completed todos")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.completedTodos) { todo in
                            completedRow(todo)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func completedRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(completedTime(for: todo))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        )
    }

    private func completedTime(for todo: TodoItem) -> String {
        guard let completedAt = todo.completedAt else {
            return "Completed time unavailable"
        }

        return Self.completedDateFormatter.string(from: completedAt)
    }

    private static let completedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
