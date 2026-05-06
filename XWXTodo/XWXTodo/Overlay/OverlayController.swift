import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController {
    private let store: TodoStore
    private let panel: OverlayPanel
    private let hostingController: NSHostingController<AnyView>
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
            rootView: AnyView(EmptyView())
        )

        configurePanel()
        renderContent(positionIfVisible: false)

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
                    guard let self, !self.isExpanded else { return }
                    self.renderContent(positionIfVisible: true)
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
        panel.becomesKeyOnlyIfNeeded = true
        // Keep the overlay above the menu bar and full-screen Spaces at the physical top edge.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentViewController = hostingController
    }

    private func renderContent(positionIfVisible: Bool) {
        if isExpanded {
            hostingController.rootView = AnyView(
                TodoPanelView(store: store) { [weak self] isHovering in
                    guard !isHovering else { return }
                    self?.collapseAfterMouseExit()
                }
            )
        } else {
            hostingController.rootView = AnyView(
                NotchView(title: store.notchTitle) { [weak self] isHovering in
                    guard isHovering else {
                        return
                    }

                    self?.expand()
                }
            )
        }

        if positionIfVisible, panel.isVisible {
            positionPanel()
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat
        let height: CGFloat

        if isExpanded {
            width = OverlayMetrics.panelWidth
            height = OverlayMetrics.panelHeight
        } else {
            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            width = max(OverlayMetrics.notchMinWidth, fittingSize.width)
            height = OverlayMetrics.notchHeight
        }

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
        renderContent(positionIfVisible: true)
    }

    private func collapse() {
        guard isExpanded else { return }

        isExpanded = false
        renderContent(positionIfVisible: true)
    }

    private func collapseAfterMouseExit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.collapse()
        }
    }
}
