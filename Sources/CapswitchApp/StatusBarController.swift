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
    private let tapStatusItem = NSMenuItem(
        title: "",
        action: nil,
        keyEquivalent: ""
    )
    private let hidMappingItem = NSMenuItem(
        title: "",
        action: nil,
        keyEquivalent: ""
    )
    private let reapplyMappingItem = NSMenuItem(
        title: "Reapply Caps → F19 mapping",
        action: #selector(reapplyMapping),
        keyEquivalent: ""
    )
    private let permissionItem = NSMenuItem(
        title: "",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )
    private let inputMonitoringItem = NSMenuItem(
        title: "",
        action: #selector(openInputMonitoringSettings),
        keyEquivalent: ""
    )
    private let systemSwitchItem = NSMenuItem(
        title: "",
        action: #selector(openKeyboardSettings),
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
        menu.addItem(tapStatusItem)
        menu.addItem(hidMappingItem)
        menu.addItem(errorItem)
        menu.addItem(reapplyMappingItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(pauseItem)
        menu.addItem(permissionItem)
        menu.addItem(inputMonitoringItem)
        menu.addItem(systemSwitchItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Capswitch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        for item in [
            pauseItem,
            permissionItem,
            inputMonitoringItem,
            systemSwitchItem,
            reapplyMappingItem,
            quitItem,
        ] {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.toolTip = "Capswitch"
    }

    private func refreshController() {
        let now = Date()

        if !inputController.accessibilityTrusted,
           inputController.isTapEnabled {
            inputController.stop()
        }

        inputController.repairEventTapIfNeeded()

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

        tapStatusItem.title = "Event tap: \(inputController.isTapEnabled ? "Enabled" : "Inactive")"
        tapStatusItem.isEnabled = false

        hidMappingItem.title = inputController.hidMappingConfigured
            ? "HID Caps → F19: configured (verify physical keyboard)"
            : "HID Caps → F19: not configured"
        hidMappingItem.isEnabled = false
        reapplyMappingItem.isEnabled = inputController.isRunning

        errorItem.isHidden = inputController.lastError == nil
        errorItem.title = "Error: \(inputController.lastError ?? "")"
        errorItem.toolTip = inputController.lastError
        errorItem.isEnabled = false

        pauseItem.title = inputController.isPaused
            ? "Resume switching (restore F19)"
            : "Pause switching (restore Caps)"
        pauseItem.state = inputController.isPaused ? .on : .off

        permissionItem.title = inputController.accessibilityTrusted
            ? "Accessibility: Granted"
            : "Grant Accessibility permission…"

        inputMonitoringItem.title = inputController.inputMonitoringTrusted
            ? "Input Monitoring: Granted"
            : "Input Monitoring: Not granted (may be needed)…"

        systemSwitchItem.title =
            "System Caps input switch: \(inputController.nativeCapsSwitchState)"
        systemSwitchItem.toolTip =
            "Keyboard → Text Input → Edit → disable 'Use Caps Lock to switch input sources'."

        for item in [
            currentLayoutItem,
            permissionItem,
            inputMonitoringItem,
            systemSwitchItem,
            pauseItem,
        ] {
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

    @objc private func openInputMonitoringSettings() {
        inputController.requestInputMonitoringPermission()
    }

    @objc private func openKeyboardSettings() {
        inputController.openKeyboardSettings()
    }

    @objc private func reapplyMapping() {
        inputController.reapplyHIDMapping()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
