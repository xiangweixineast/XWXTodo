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
    private var overlayController: OverlayController?
    @Published var startupError: String?

    init(store: TodoStore?, startupError: String? = nil) {
        self.store = store
        self.overlayController = nil
        self.startupError = startupError
    }

    init() {
        do {
            let repository = try SQLiteTodoRepository()
            let store = try TodoStore(repository: repository)
            self.store = store
            self.overlayController = OverlayController(store: store)
        } catch {
            self.store = nil
            self.overlayController = OverlayController(fallbackTitle: "XWXTodo")
            self.startupError = error.localizedDescription
        }
    }

    func showOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayController?.show()
        }
    }
}

@main
struct XWXTodoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onAppear {
                    if scenePhase == .active {
                        appState.showOverlay()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appState.showOverlay()
                    }
                }
        }
    }
}
