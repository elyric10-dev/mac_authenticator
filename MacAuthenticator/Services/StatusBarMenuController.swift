import AppKit
import SwiftUI

/// Installs a right-click menu on the menu bar shield without breaking left-click.
final class StatusBarMenuController: NSObject {
    static let shared = StatusBarMenuController()

    private var eventMonitor: Any?
    private var installTimer: Timer?
    private var menu: NSMenu?

    func configure(appController: AppController) {
        _ = appController
        buildMenu()
        startInstallingMenuMonitor()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(makeItem(title: "Manage 2FA", action: #selector(manage2FA), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        self.menu = menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func startInstallingMenuMonitor() {
        installTimer?.invalidate()
        installTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.installEventMonitorIfNeeded()
        }
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        guard Self.findStatusBarButton() != nil else { return }

        installTimer?.invalidate()
        installTimer = nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleContextEvent(event) ?? event
        }
    }

    private func handleContextEvent(_ event: NSEvent) -> NSEvent? {
        let isContextMenuEvent = event.type == .rightMouseDown
            || (event.type == .otherMouseDown && event.buttonNumber == 2)

        guard isContextMenuEvent, isMouseOverStatusBarButton() else {
            return event
        }

        showMenu()
        return nil
    }

    private func showMenu() {
        guard let menu, let button = Self.findStatusBarButton() else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func manage2FA() {
        Task { @MainActor in
            AppController.current?.openManage2FA()
        }
    }

    @objc private func quit() {
        Task { @MainActor in
            AppController.current?.quit()
        }
    }

    static func findStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let button = findStatusBarButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = findStatusBarButton(in: subview) { return found }
        }
        return nil
    }

    private func isMouseOverStatusBarButton() -> Bool {
        guard let button = Self.findStatusBarButton(),
              let window = button.window else {
            return false
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        return buttonFrameOnScreen.contains(NSEvent.mouseLocation)
    }

    static func openMenuBarPanel() {
        findStatusBarButton()?.performClick(nil)
    }

    static func closeMenuBarPanel() {
        guard isMenuBarPanelOpen else { return }
        findStatusBarButton()?.performClick(nil)
    }

    static var isMenuBarPanelOpen: Bool {
        NSApp.windows.contains { window in
            guard window.isVisible else { return false }
            let name = String(describing: type(of: window))
            return name.contains("Popover") || name.contains("StatusBar")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configureAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuController()
    }

    private func configureMenuController() {
        configureAttempts += 1

        Task { @MainActor in
            if let appController = AppController.current {
                StatusBarMenuController.shared.configure(appController: appController)
                return
            }

            guard configureAttempts < 40 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.configureMenuController()
            }
        }
    }
}
