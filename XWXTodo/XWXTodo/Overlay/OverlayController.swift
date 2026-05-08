import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class OverlayController {
    private enum PresentationState {
        case collapsed
        case expanding
        case expanded
        case collapsing
    }

    private enum LayoutState {
        case collapsed
        case expanded
    }

    private static let transitionDuration: TimeInterval = 0.30
    private static let collapseDelay: TimeInterval = 0.15

    private let store: TodoStore?
    private let fallbackTitle: String
    private let panel: OverlayPanel
    private let hostingController: NSHostingController<AnyView>
    private var screenObserver: NSObjectProtocol?
    private var todosCancellable: AnyCancellable?
    private var presentationState = PresentationState.collapsed
    private var animationGeneration = 0
    private var animationTimer: Timer?
    private var pendingCollapseWorkItem: DispatchWorkItem?
    private var shouldCollapseAfterExpansion = false

    init(store: TodoStore) {
        self.store = store
        self.fallbackTitle = "XWXTodo"
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
        observeScreenChanges()

        todosCancellable = store.$todos
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.presentationState == .collapsed else { return }
                    self.renderContent(positionIfVisible: true)
                }
            }
    }

    init(fallbackTitle: String = "XWXTodo") {
        self.store = nil
        self.fallbackTitle = fallbackTitle
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
        observeScreenChanges()
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.positionPanel()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }

        pendingCollapseWorkItem?.cancel()
        animationTimer?.invalidate()
    }

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        hostingController.sizingOptions = []
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
        if shouldShowPanelContent, let store {
            hostingController.rootView = AnyView(
                TodoPanelView(store: store) { [weak self] isHovering in
                    if isHovering {
                        self?.cancelPendingCollapse()
                        return
                    }

                    self?.collapseAfterMouseExit()
                }
            )
        } else {
            let title = store?.notchTitle ?? fallbackTitle
            hostingController.rootView = AnyView(
                NotchView(title: title) { [weak self] isHovering in
                    guard isHovering, self?.store != nil else { return }

                    self?.expand()
                }
            )
        }

        if positionIfVisible, panel.isVisible {
            positionPanel()
        }
    }

    private func positionPanel() {
        guard let frame = targetFrame(for: currentLayoutState) else { return }

        animationTimer?.invalidate()
        animationTimer = nil
        applyPanelFrame(frame)
    }

    private func targetFrame(for layoutState: LayoutState) -> NSRect? {
        guard let screen = NSScreen.main else { return nil }

        let size: NSSize
        switch layoutState {
        case .collapsed:
            size = collapsedSize()
        case .expanded:
            size = NSSize(
                width: OverlayMetrics.panelWidth,
                height: OverlayMetrics.panelHeight
            )
        }

        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func collapsedSize() -> NSSize {
        let title = store?.notchTitle ?? fallbackTitle
        let measuringView = NSHostingView(
            rootView: NotchView(title: title) { _ in }
        )
        measuringView.layoutSubtreeIfNeeded()
        let fittingSize = measuringView.fittingSize

        return NSSize(
            width: max(OverlayMetrics.notchMinWidth, fittingSize.width),
            height: OverlayMetrics.notchHeight
        )
    }

    private func expand() {
        guard store != nil else { return }
        guard presentationState == .collapsed else { return }
        guard let collapsedFrame = targetFrame(for: .collapsed),
              let expandedFrame = targetFrame(for: .expanded) else { return }

        cancelPendingCollapse()
        presentationState = .expanding
        animationGeneration += 1
        let generation = animationGeneration

        applyPanelFrame(collapsedFrame)
        renderContent(positionIfVisible: false)

        animatePanel(to: expandedFrame, generation: generation) { [weak self] in
            guard let self else { return }

            self.presentationState = .expanded
            self.hostingController.view.frame = NSRect(origin: .zero, size: expandedFrame.size)

            guard self.shouldCollapseAfterExpansion else { return }

            self.shouldCollapseAfterExpansion = false
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.collapse()
        }
    }

    private func collapse() {
        guard presentationState == .expanded else { return }
        guard let collapsedFrame = targetFrame(for: .collapsed) else { return }

        cancelPendingCollapse()
        presentationState = .collapsing
        animationGeneration += 1
        let generation = animationGeneration

        animatePanel(to: collapsedFrame, generation: generation) { [weak self] in
            guard let self else { return }

            self.presentationState = .collapsed
            self.hostingController.view.frame = NSRect(origin: .zero, size: collapsedFrame.size)
            self.renderContent(positionIfVisible: false)
            self.panel.setFrame(collapsedFrame, display: true)
        }
    }

    private func collapseAfterMouseExit() {
        pendingCollapseWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCollapseWorkItem = nil
            guard !self.panel.frame.contains(NSEvent.mouseLocation) else { return }

            if self.presentationState == .expanding {
                self.shouldCollapseAfterExpansion = true
                return
            }

            self.collapse()
        }

        pendingCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.collapseDelay,
            execute: workItem
        )
    }

    private func cancelPendingCollapse() {
        pendingCollapseWorkItem?.cancel()
        pendingCollapseWorkItem = nil
        shouldCollapseAfterExpansion = false
    }

    private func animatePanel(
        to targetFrame: NSRect,
        generation: Int,
        completion: @escaping @MainActor () -> Void
    ) {
        animationTimer?.invalidate()

        let startFrame = panel.frame
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == generation else {
                    timer.invalidate()
                    return
                }

                let elapsed = CACurrentMediaTime() - startTime
                let linearProgress = min(1, elapsed / Self.transitionDuration)
                let easedProgress = Self.easeInOut(linearProgress)
                let frame = Self.interpolate(
                    from: startFrame,
                    to: targetFrame,
                    progress: easedProgress
                )

                self.applyPanelFrame(frame)

                guard linearProgress >= 1 else { return }

                timer.invalidate()
                if self.animationTimer === timer {
                    self.animationTimer = nil
                }
                self.applyPanelFrame(targetFrame)
                completion()
            }
        }

        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func applyPanelFrame(_ frame: NSRect) {
        hostingController.view.frame = NSRect(origin: .zero, size: frame.size)
        panel.setFrame(frame, display: true)
    }

    private static func interpolate(from start: NSRect, to end: NSRect, progress: Double) -> NSRect {
        let progress = CGFloat(progress)

        return NSRect(
            x: start.origin.x + (end.origin.x - start.origin.x) * progress,
            y: start.origin.y + (end.origin.y - start.origin.y) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    private static func easeInOut(_ progress: Double) -> Double {
        progress * progress * (3 - 2 * progress)
    }

    private var shouldShowPanelContent: Bool {
        switch presentationState {
        case .collapsed:
            return false
        case .expanding, .expanded, .collapsing:
            return true
        }
    }

    private var currentLayoutState: LayoutState {
        switch presentationState {
        case .collapsed, .collapsing:
            return .collapsed
        case .expanding, .expanded:
            return .expanded
        }
    }
}
