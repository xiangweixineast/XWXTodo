//
//  XWXTodoApp.swift
//  XWXTodo
//
//  Created by xwx on 2026/5/6.
//

import SwiftUI

private let defaultTodoPollingIntervalNanoseconds: UInt64 = 3_000_000_000

@MainActor
final class AppState: ObservableObject {
    let store: TodoStore?
    let cloudAuthStore: CloudAuthStore
    private let cloudTodoClient: CloudTodoClient
    private let todoPollingIntervalNanoseconds: UInt64
    private var overlayController: OverlayController?
    private var todoPollingTask: Task<Void, Never>?
    @Published var startupError: String?
    @Published private(set) var syncErrorMessage: String?
    @Published private(set) var isSyncingTodos: Bool

    init(
        store: TodoStore?,
        startupError: String? = nil,
        cloudAuthStore: CloudAuthStore? = nil,
        cloudTodoClient: CloudTodoClient = CloudAPIClient(),
        todoPollingIntervalNanoseconds: UInt64 = defaultTodoPollingIntervalNanoseconds
    ) {
        self.store = store
        self.cloudAuthStore = cloudAuthStore ?? CloudAuthStore()
        self.cloudTodoClient = cloudTodoClient
        self.todoPollingIntervalNanoseconds = todoPollingIntervalNanoseconds
        self.overlayController = nil
        self.todoPollingTask = nil
        self.startupError = startupError
        self.syncErrorMessage = nil
        self.isSyncingTodos = false
    }

    init() {
        let cloudClient = CloudAPIClient()
        let authStore = CloudAuthStore(client: cloudClient)
        self.cloudAuthStore = authStore
        self.cloudTodoClient = cloudClient
        self.todoPollingIntervalNanoseconds = defaultTodoPollingIntervalNanoseconds
        self.todoPollingTask = nil
        self.startupError = nil
        self.syncErrorMessage = nil
        self.isSyncingTodos = false

        do {
            let repository = try SQLiteTodoRepository()
            let store = try TodoStore(
                repository: repository,
                cloudTodoClient: cloudClient,
                tokenProvider: { authStore.session?.token },
                loadInitialData: false
            )
            self.store = store
            self.overlayController = OverlayController(store: store)
        } catch {
            self.store = nil
            self.overlayController = OverlayController(fallbackTitle: "XWXTodo")
            self.startupError = error.localizedDescription
        }
    }

    deinit {
        todoPollingTask?.cancel()
    }

    func restoreCloudSessionIfNeeded() async {
        stopTodoPolling()
        await cloudAuthStore.restoreSavedSessionIfNeeded()
        await syncTodosAfterAuthIfPossible()
    }

    func restoreCloudSession() async {
        stopTodoPolling()
        await cloudAuthStore.restoreSavedSession()
        await syncTodosAfterAuthIfPossible()
    }

    func login(username: String, password: String) async {
        stopTodoPolling()
        await cloudAuthStore.login(username: username, password: password)
        await syncTodosAfterAuthIfPossible()
    }

    func logout() async {
        stopTodoPolling()
        await cloudAuthStore.logout()
        clearLocalTodos()
    }

    func retryTodoSync() async {
        await syncTodosAfterAuthIfPossible(clearCacheOnFailure: store?.currentRevision == nil)
    }

    func showOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayController?.show()
        }
    }

    private func syncTodosAfterAuthIfPossible(clearCacheOnFailure: Bool = true) async {
        guard cloudAuthStore.phase == .signedIn, let token = cloudAuthStore.session?.token else {
            stopTodoPolling()
            clearLocalTodos()
            return
        }

        await syncTodos(token: token, clearCacheOnFailure: clearCacheOnFailure)
        if cloudAuthStore.phase == .signedIn, cloudAuthStore.session?.token == token {
            startTodoPolling(token: token)
        }
    }

    private func syncTodos(token: String, clearCacheOnFailure: Bool) async {
        guard let store else { return }

        isSyncingTodos = true
        defer { isSyncingTodos = false }

        do {
            let snapshot = try await cloudTodoClient.getTodos(token: token)
            try store.applySnapshot(snapshot)
            syncErrorMessage = nil
        } catch CloudAPIError.unauthorized {
            handleUnauthorizedTodoSync()
        } catch {
            handleTodoSyncFailure(error, clearCacheOnFailure: clearCacheOnFailure)
        }
    }

    private func startTodoPolling(token: String) {
        guard store != nil else { return }

        stopTodoPolling()
        let interval = todoPollingIntervalNanoseconds
        todoPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await self?.pollTodos(token: token)
            }
        }
    }

    private func stopTodoPolling() {
        todoPollingTask?.cancel()
        todoPollingTask = nil
    }

    private func pollTodos(token: String) async {
        guard cloudAuthStore.phase == .signedIn, cloudAuthStore.session?.token == token else {
            stopTodoPolling()
            return
        }

        await syncTodos(token: token, clearCacheOnFailure: false)
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

    private func handleUnauthorizedTodoSync() {
        stopTodoPolling()
        cloudAuthStore.expireCurrentSession()
        clearLocalTodos()
        syncErrorMessage = "同步 TODO 失败：\(CloudAPIError.unauthorized.localizedDescription)"
    }

    private func handleTodoSyncFailure(_ syncError: Error, clearCacheOnFailure: Bool) {
        if clearCacheOnFailure {
            clearTodosAfterSyncFailure(syncError)
            return
        }

        syncErrorMessage = "同步 TODO 失败：\(syncError.localizedDescription)"
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
