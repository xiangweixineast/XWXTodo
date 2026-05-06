//
//  ContentView.swift
//  XWXTodo
//
//  Created by xwx on 2026/5/6.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let startupError = appState.startupError {
                ErrorBannerView(title: "Startup error", message: startupError)
            } else {
                Text("XWXTodo is running")
                    .font(.headline)

                if let store = appState.store {
                    TodoStoreCountsView(store: store)
                } else {
                    TodoCountsView(activeCount: 0, completedCount: 0)
                }
            }
        }
        .frame(minWidth: 280, alignment: .leading)
        .padding(20)
    }
}

private struct TodoStoreCountsView: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        TodoCountsView(
            activeCount: store.activeTodos.count,
            completedCount: store.completedTodos.count
        )
    }
}

private struct TodoCountsView: View {
    let activeCount: Int
    let completedCount: Int

    init(activeCount: Int, completedCount: Int) {
        self.activeCount = activeCount
        self.completedCount = completedCount
    }

    var body: some View {
        HStack(spacing: 18) {
            CountLabel(title: "Active", count: activeCount)
            CountLabel(title: "Completed", count: completedCount)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct CountLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}
