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
    let cloudAuthStore: CloudAuthStore
    private let cloudTodoClient: CloudTodoClient
    private var overlayController: OverlayController?
    @Published var startupError: String?
    @Published private(set) var syncErrorMessage: String?
    @Published private(set) var isSyncingTodos: Bool

    init(
        store: TodoStore?,
        startupError: String? = nil,
        cloudAuthStore: CloudAuthStore? = nil,
        cloudTodoClient: CloudTodoClient = CloudAPIClient()
    ) {
        self.store = store
        self.cloudAuthStore = cloudAuthStore ?? CloudAuthStore()
        self.cloudTodoClient = cloudTodoClient
        self.overlayController = nil
        self.startupError = startupError
        self.syncErrorMessage = nil
        self.isSyncingTodos = false
    }

    init() {
        let cloudClient = CloudAPIClient()
        self.cloudAuthStore = CloudAuthStore(client: cloudClient)
        self.cloudTodoClient = cloudClient
        self.syncErrorMessage = nil
        self.isSyncingTodos = false

        do {
            let repository = try SQLiteTodoRepository()
            let store = try TodoStore(repository: repository, loadInitialData: false)
            self.store = store
            self.overlayController = OverlayController(store: store)
        } catch {
            self.store = nil
            self.overlayController = OverlayController(fallbackTitle: "XWXTodo")
            self.startupError = error.localizedDescription
        }
    }

    func restoreCloudSessionIfNeeded() async {
        await cloudAuthStore.restoreSavedSessionIfNeeded()
        await syncTodosAfterAuthIfPossible()
    }

    func restoreCloudSession() async {
        await cloudAuthStore.restoreSavedSession()
        await syncTodosAfterAuthIfPossible()
    }

    func login(username: String, password: String) async {
        await cloudAuthStore.login(username: username, password: password)
        await syncTodosAfterAuthIfPossible()
    }

    func logout() async {
        await cloudAuthStore.logout()
        clearLocalTodos()
    }

    func retryTodoSync() async {
        await syncTodosAfterAuthIfPossible()
    }

    func showOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayController?.show()
        }
    }

    private func syncTodosAfterAuthIfPossible() async {
        guard cloudAuthStore.phase == .signedIn, let token = cloudAuthStore.session?.token else {
            clearLocalTodos()
            return
        }

        await syncTodos(token: token)
    }

    private func syncTodos(token: String) async {
        guard let store else { return }

        isSyncingTodos = true
        syncErrorMessage = nil
        defer { isSyncingTodos = false }

        do {
            let snapshot = try await cloudTodoClient.getTodos(token: token)
            try store.replaceAll(snapshot.todoItems())
            syncErrorMessage = nil
        } catch {
            clearTodosAfterSyncFailure(error)
        }
    }

    private func clearLocalTodos() {
        guard let store else {
            syncErrorMessage = nil
            return
        }

        do {
            try store.clear()
            syncErrorMessage = nil
        } catch {
            syncErrorMessage = "清空本地 TODO 失败：\(error.localizedDescription)"
        }
    }

    private func clearTodosAfterSyncFailure(_ syncError: Error) {
        guard let store else {
            syncErrorMessage = "同步 TODO 失败：\(syncError.localizedDescription)"
            return
        }

        do {
            try store.clear()
            syncErrorMessage = "同步 TODO 失败：\(syncError.localizedDescription)"
        } catch {
            syncErrorMessage = "同步 TODO 失败：\(syncError.localizedDescription)；清空本地缓存失败：\(error.localizedDescription)"
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
                .task {
                    await appState.restoreCloudSessionIfNeeded()
                }
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
