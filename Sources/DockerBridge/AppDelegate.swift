import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = AppSettingsStore()
    private let store = ConnectionStore()
    private lazy var tunnelManager = TunnelManager(settingsStore: settingsStore)
    private var statusBarController: StatusBarController?
    private var connectionWindowController: ConnectionWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var helpWindowController: HelpWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.configure(languageCode: settingsStore.settings.languageCode)
        store.load()

        store.onChange = { [weak self] in
            self?.connectionWindowController?.reload()
            self?.statusBarController?.refresh()
        }

        tunnelManager.onChange = { [weak self] in
            self?.connectionWindowController?.reload()
            self?.statusBarController?.refresh()
        }

        settingsStore.onChange = { [weak self] in
            guard let self else {
                return
            }
            L10n.configure(languageCode: self.settingsStore.settings.languageCode)
            self.connectionWindowController?.applyLocalization()
            self.settingsWindowController?.applyLocalization()
            self.helpWindowController?.applyLocalization()
            self.statusBarController?.refresh()
        }

        statusBarController = StatusBarController(
            store: store,
            tunnelManager: tunnelManager,
            showManager: { [weak self] in
                self?.showConnectionWindow()
            },
            addConnection: { [weak self] in
                self?.showNewConnection()
            },
            showSettings: { [weak self] in
                self?.showSettingsWindow()
            },
            showHelp: { [weak self] in
                self?.showHelpWindow()
            }
        )

        if !ProcessInfo.processInfo.arguments.contains("--background") {
            showConnectionWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tunnelManager.stopAll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let launchAgentInstalled = LoginAgentManager.isInstalled()
        let activeConnectionCount = tunnelManager.activeCount()

        guard launchAgentInstalled || activeConnectionCount > 0 else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = L10n.trf("quit.title", AppConstants.appName)
        alert.informativeText = terminationMessage(
            launchAgentInstalled: launchAgentInstalled,
            activeConnectionCount: activeConnectionCount
        )
        alert.alertStyle = activeConnectionCount > 0 ? .warning : .informational
        alert.addButton(withTitle: L10n.tr("quit.button.quit"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))

        if launchAgentInstalled {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = L10n.trf("quit.disableLaunchAgent", AppConstants.appName)
            alert.suppressionButton?.state = .off
        }

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .terminateCancel
        }

        if launchAgentInstalled, alert.suppressionButton?.state == .on {
            do {
                try LoginAgentManager.uninstall()
            } catch {
                showTerminationError(error)
                return .terminateCancel
            }
        }

        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showConnectionWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showConnectionWindow() {
        let controller = windowController()
        controller.showAndFocus()
    }

    private func showNewConnection() {
        let controller = windowController()
        controller.prepareNewConnection()
    }

    private func showSettingsWindow() {
        let controller = settingsController()
        controller.showAndFocus()
    }

    private func showHelpWindow() {
        let controller = helpController()
        controller.showAndFocus()
    }

    private func terminationMessage(launchAgentInstalled: Bool, activeConnectionCount: Int) -> String {
        var messages: [String] = []

        if activeConnectionCount == 1 {
            messages.append(L10n.tr("quit.activeConnection.one"))
        } else if activeConnectionCount > 1 {
            messages.append(L10n.trf("quit.activeConnection.many", activeConnectionCount))
        }

        if launchAgentInstalled {
            messages.append(L10n.trf("quit.launchAgentConfigured", AppConstants.appName))
        }

        return messages.joined(separator: "\n\n")
    }

    private func showTerminationError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("quit.uninstallError.title")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func windowController() -> ConnectionWindowController {
        if let connectionWindowController {
            return connectionWindowController
        }

        let controller = ConnectionWindowController(store: store, tunnelManager: tunnelManager)
        connectionWindowController = controller
        return controller
    }

    private func settingsController() -> SettingsWindowController {
        if let settingsWindowController {
            return settingsWindowController
        }

        let controller = SettingsWindowController(settingsStore: settingsStore)
        settingsWindowController = controller
        return controller
    }

    private func helpController() -> HelpWindowController {
        if let helpWindowController {
            return helpWindowController
        }

        let controller = HelpWindowController()
        helpWindowController = controller
        return controller
    }
}
