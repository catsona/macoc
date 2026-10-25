import AppKit
import Foundation

final class StatusBarController: NSObject, NSMenuDelegate {
    private let inputController: MacOSInputController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let currentLayoutItem = NSMenuItem(
        title: "",
        action: nil,
        keyEquivalent: ""
    )
    private let diagnosticsItem = NSMenuItem(
        title: "",
        action: nil,
        keyEquivalent: ""
    )
    private let errorItem = NSMenuItem(
        title: "",
        action: nil,
        keyEquivalent: ""
    )
    private let permissionItem = NSMenuItem(
        title: "",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )
    private let pauseItem = NSMenuItem(
        title: "",
        action: #selector(togglePaused),
        keyEquivalent: ""
    )

    private var refreshTimer: Timer?
    private var nextStartAttempt = Date.distantPast
    private var lastDeepRefresh = Date.distantPast

    init(inputController: MacOSInputController = MacOSInputController()) {
        self.inputController = inputController
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        configureMenu()
        inputController.onStateChanged = { [weak self] in
            self?.update()
        }

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.refreshController()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        refreshController()
    }

    deinit {
        refreshTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        inputController.stop()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureMenu() {
        menu.delegate = self
        menu.addItem(currentLayoutItem)
        menu.addItem(diagnosticsItem)
        menu.addItem(errorItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(pauseItem)
        menu.addItem(permissionItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Capswitch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        for item in [pauseItem, permissionItem, quitItem] {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.toolTip = "Capswitch"
    }

    private func refreshController() {
        let now = Date()

        if !inputController.accessibilityTrusted && inputController.isRunning {
            inputController.stop()
        }

        if inputController.accessibilityTrusted,
           !inputController.isPaused,
           !inputController.isRunning,
           now >= nextStartAttempt {
            nextStartAttempt = now.addingTimeInterval(5)

            do {
                try inputController.start()
            } catch {
                inputController.lastError = error.localizedDescription
            }
        }

        if now.timeIntervalSince(lastDeepRefresh) >= 10 {
            lastDeepRefresh = now
            inputController.refreshInputSources()
            if inputController.isRunning {
                inputController.repairMappingIfNeeded()
            }
        }

        update()
    }

    private func update() {
        let name = inputController.currentInputSourceName
        statusItem.button?.title = inputController.isRunning
            ? inputController.currentInputSourceShortName
            : "Caps!"
        statusItem.button?.toolTip = "Capswitch - \(name)"

        currentLayoutItem.title = "Current layout: \(name)"
        diagnosticsItem.title = inputController.diagnosticsSummary
        diagnosticsItem.isEnabled = false

        errorItem.isHidden = inputController.lastError == nil
        errorItem.title = "Error: \(inputController.lastError ?? "")"
        errorItem.toolTip = inputController.lastError
        errorItem.isEnabled = false

        pauseItem.title = inputController.isPaused
            ? "Resume switching (restore F19)"
            : "Pause switching (restore Caps)"
        pauseItem.state = inputController.isPaused ? .on : .off

        if inputController.accessibilityTrusted {
            permissionItem.title = inputController.isRunning
                ? "Accessibility: Granted · Caps → F19 active"
                : "Accessibility: Granted · switching inactive"
        } else {
            permissionItem.title = "Grant Accessibility permission…"
        }

        for item in [currentLayoutItem, permissionItem, pauseItem] {
            item.target = self
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshController()
    }

    @objc private func didWake(_ notification: Notification) {
        inputController.repairMappingIfNeeded()
        refreshController()
    }

    @objc private func togglePaused() {
        inputController.setPaused(!inputController.isPaused)
        nextStartAttempt = .distantPast
        update()
    }

    @objc private func openAccessibilitySettings() {
        inputController.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
