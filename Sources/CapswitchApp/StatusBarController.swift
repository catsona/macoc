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

        refreshController()
    }

    deinit {
        refreshTimer?.invalidate()
        inputController.stop()
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureMenu() {
        menu.delegate = self
        menu.addItem(currentLayoutItem)
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
        if inputController.accessibilityTrusted {
            if !inputController.isRunning {
                try? inputController.start()
            }
            inputController.refreshInputSources()
        }
        update()
    }

    private func update() {
        let shortName = inputController.currentInputSourceShortName
        statusItem.button?.title = shortName
        statusItem.button?.toolTip = "Capswitch - \(inputController.currentInputSourceName)"

        currentLayoutItem.title =
            "Current layout: \(inputController.currentInputSourceName)"

        pauseItem.title = inputController.isPaused
            ? "Resume switching"
            : "Pause switching"
        pauseItem.state = inputController.isPaused ? .on : .off

        if inputController.accessibilityTrusted {
            permissionItem.title = inputController.isRunning
                ? "Accessibility: Granted"
                : "Accessibility: Granted (tap stopped)"
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

    @objc private func togglePaused() {
        inputController.setPaused(!inputController.isPaused)
        update()
    }

    @objc private func openAccessibilitySettings() {
        inputController.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
