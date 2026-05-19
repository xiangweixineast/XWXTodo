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
        VStack(alignment: .leading, spacing: 16) {
            Text("XWXTodo")
                .font(.headline)

            CloudAuthSectionView(authStore: appState.cloudAuthStore)

            if let startupError = appState.startupError {
                ErrorBannerView(title: "启动错误", message: startupError)
            } else {
                if let store = appState.store {
                    TodoStoreCountsView(store: store)
                } else {
                    TodoCountsView(activeCount: 0, completedCount: 0)
                }
            }
        }
        .frame(minWidth: 360, alignment: .leading)
        .padding(20)
    }
}

private struct CloudAuthSectionView: View {
    @ObservedObject var authStore: CloudAuthStore
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("云端账号", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                CloudAuthPhaseBadge(phase: authStore.phase)
            }

            if let message = authStore.errorMessage {
                ErrorBannerView(title: "云端连接", message: message)
            }

            switch authStore.phase {
            case .signedOut, .signingIn:
                loginForm
            case .restoring:
                progressRow(text: "正在验证登录状态")
            case .signedIn:
                signedInView
            case .connectionFailed:
                connectionFailedView
            }
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
                .disabled(authStore.phase.isBusy)

            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .disabled(authStore.phase.isBusy)
                .onSubmit(signIn)

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if authStore.phase == .signingIn {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(authStore.phase == .signingIn ? "登录中" : "登录")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isLoginDisabled)
        }
    }

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let user = authStore.currentUser {
                Text(user.username)
                    .font(.title3.weight(.semibold))
            }

            if let lastConnectedAt = authStore.lastConnectedAt {
                Text("上次连接 \(lastConnectedAt.formatted(date: .numeric, time: .standard))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                Task {
                    await authStore.logout()
                }
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var connectionFailedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("云端连接异常")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Button {
                    Task {
                        await authStore.restoreSavedSession()
                    }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive) {
                    Task {
                        await authStore.logout()
                    }
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func progressRow(text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var isLoginDisabled: Bool {
        authStore.phase.isBusy ||
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        password.isEmpty
    }

    private func signIn() {
        guard !isLoginDisabled else { return }
        Task {
            await authStore.login(username: username, password: password)
            if authStore.phase == .signedIn {
                password = ""
            }
        }
    }
}

private struct CloudAuthPhaseBadge: View {
    let phase: CloudAuthPhase

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch phase {
        case .signedOut:
            return "未登录"
        case .restoring:
            return "验证中"
        case .signingIn:
            return "登录中"
        case .signedIn:
            return "已连接"
        case .connectionFailed:
            return "连接异常"
        }
    }

    private var icon: String {
        switch phase {
        case .signedOut:
            return "person.crop.circle"
        case .restoring, .signingIn:
            return "clock"
        case .signedIn:
            return "checkmark.circle.fill"
        case .connectionFailed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch phase {
        case .signedOut:
            return .secondary
        case .restoring, .signingIn:
            return .orange
        case .signedIn:
            return .green
        case .connectionFailed:
            return .red
        }
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
    ContentView(appState: AppState(store: nil))
}
