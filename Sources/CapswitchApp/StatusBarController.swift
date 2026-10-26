import AppKit
import Foundation
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let inputController: MacOSInputController
    private let lifecycle: ApplicationLifecycleController
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
        title: "Retry Caps → F19 mapping",
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
    private let installItem = NSMenuItem(
        title: "Install to ~/Applications…",
        action: #selector(installApplication),
        keyEquivalent: ""
    )
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private let loginSettingsItem = NSMenuItem(
        title: "Open Login Items Settings…",
        action: #selector(openLoginItemsSettings),
        keyEquivalent: ""
    )
    private let restartItem = NSMenuItem(
        title: "Restart macoc",
        action: #selector(restartApplication),
        keyEquivalent: ""
    )

    private var refreshTimer: Timer?
    private var nextStartAttempt = Date.distantPast
    private var lastDeepRefresh = Date.distantPast

    init(inputController: MacOSInputController = MacOSInputController()) {
        self.inputController = inputController
        self.lifecycle = ApplicationLifecycleController(inputController: inputController)
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

        inputController.requestRequiredPermissions()
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
        menu.addItem(installItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(loginSettingsItem)
        menu.addItem(restartItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit macoc",
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
            installItem,
            launchAtLoginItem,
            loginSettingsItem,
            restartItem,
            quitItem,
        ] {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.toolTip = "macoc"
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

            if inputController.isTapEnabled {
                inputController.repairMappingIfNeeded()
            } else {
                do {
                    try inputController.start()
                } catch {
                    inputController.lastError = error.localizedDescription
                }
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
        if let button = statusItem.button {
            let icon = inputController.isRunning ? inputController.currentInputSourceIcon : nil
            button.image = icon
            button.title = inputController.isRunning
                ? (icon == nil ? inputController.currentInputSourceShortName : "")
                : "Caps!"
            button.setAccessibilityLabel("macoc - \(name)")
        }
        statusItem.button?.toolTip = "macoc - \(name)"

        currentLayoutItem.title = "Current layout: \(name)"
        diagnosticsItem.title = inputController.diagnosticsSummary
        diagnosticsItem.isEnabled = false

        tapStatusItem.title = "Event tap: \(inputController.isTapEnabled ? "Enabled" : "Inactive")"
        tapStatusItem.isEnabled = false

        hidMappingItem.title = inputController.hidMappingConfigured
            ? "Native HID: \(inputController.mappingStatus)"
            : "Native HID inactive: \(inputController.mappingStatus)"
        hidMappingItem.isEnabled = false
        reapplyMappingItem.isEnabled = inputController.isTapEnabled

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

        installItem.title = lifecycle.isInstalled
            ? "Installed in ~/Applications"
            : "Install to ~/Applications…"
        installItem.isEnabled = !lifecycle.isInstalled

        launchAtLoginItem.title = lifecycle.loginItemTitle
        launchAtLoginItem.isEnabled = lifecycle.isInstalled
        switch lifecycle.loginItemStatus {
        case .enabled:
            launchAtLoginItem.state = .on
        case .requiresApproval:
            launchAtLoginItem.state = .mixed
        default:
            launchAtLoginItem.state = .off
        }
        loginSettingsItem.isHidden = lifecycle.loginItemStatus != .requiresApproval

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

    @objc private func installApplication() {
        let alert = NSAlert()
        alert.messageText = "Install macoc?"
        alert.informativeText =
            "Copy this version to ~/Applications/macoc.app and launch it from there. " +
            "No administrator privileges are required."
        alert.addButton(withTitle: "Install and Launch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let installedURL: URL
        do {
            installedURL = try lifecycle.install()
        } catch {
            showError("Installation failed", message: error.localizedDescription)
            return
        }

        do {
            try lifecycle.restartInstalledCopy(at: installedURL)
            NSApp.terminate(nil)
        } catch {
            showError(
                "Installed, but could not relaunch",
                message: "macoc was installed to ~/Applications. " +
                    error.localizedDescription
            )
        }
    }

    @objc private func restartApplication() {
        do {
            try lifecycle.restartCurrentCopy()
            NSApp.terminate(nil)
        } catch {
            showError("Restart failed", message: error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try lifecycle.toggleLaunchAtLogin()
        } catch {
            showError("Launch at Login", message: error.localizedDescription)
        }
        update()
    }

    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func showError(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        do {
            try lifecycle.stopForQuit()
            NSApp.terminate(nil)
        } catch {
            showError("Caps Lock could not be restored", message: error.localizedDescription)
        }
    }
}
