//
//  XWXTodoApp.swift
//  XWXTodo
//
//  Created by xwx on 2026/5/6.
//

import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let store: TodoStore?
    @Published var startupError: String?

    init(store: TodoStore?, startupError: String? = nil) {
        self.store = store
        self.startupError = startupError
    }

    init() {
        do {
            let repository = try SQLiteTodoRepository()
            self.store = try TodoStore(repository: repository)
        } catch {
            self.store = nil
            self.startupError = error.localizedDescription
        }
    }
}

@main
struct XWXTodoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
    }
}
