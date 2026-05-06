import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController {
    private let store: TodoStore
    private let panel: OverlayPanel
    private let hostingController: NSHostingController<NotchView>
    private var screenObserver: NSObjectProtocol?
    private var todosCancellable: AnyCancellable?
    private var isExpanded = false

    init(store: TodoStore) {
        self.store = store
        self.panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hostingController = NSHostingController(
            rootView: NotchView(title: store.notchTitle) { _ in }
        )

        configurePanel()
        updateNotchView(positionIfVisible: false)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.positionPanel()
            }
        }

        todosCancellable = store.$todos
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateNotchView(positionIfVisible: true)
                }
            }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // The notch is anchored to the physical top edge, above the menu bar and full-screen spaces.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentViewController = hostingController
    }

    private func updateNotchView(positionIfVisible: Bool) {
        hostingController.rootView = NotchView(title: store.notchTitle) { [weak self] isHovering in
            guard isHovering else {
                self?.isExpanded = false
                return
            }

            self?.expand()
        }

        if positionIfVisible, panel.isVisible {
            positionPanel()
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let width = max(OverlayMetrics.notchMinWidth, fittingSize.width)
        let height = OverlayMetrics.notchHeight
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        let size = NSSize(width: width, height: height)

        hostingController.view.frame = NSRect(origin: .zero, size: size)

        panel.setFrame(
            NSRect(origin: NSPoint(x: x, y: y), size: size),
            display: true
        )
    }

    private func expand() {
        guard !isExpanded else { return }

        isExpanded = true
    }
}
