import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let store: ConnectionStore
    private let tunnelManager: TunnelManager
    private let statusItem: NSStatusItem
    private let showManager: () -> Void
    private let addConnection: () -> Void
    private let showSettings: () -> Void
    private let showHelp: () -> Void

    init(
        store: ConnectionStore,
        tunnelManager: TunnelManager,
        showManager: @escaping () -> Void,
        addConnection: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        showHelp: @escaping () -> Void
    ) {
        self.store = store
        self.tunnelManager = tunnelManager
        self.showManager = showManager
        self.addConnection = addConnection
        self.showSettings = showSettings
        self.showHelp = showHelp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        refresh()
    }

    func refresh() {
        let menu = NSMenu()

        menu.addItem(disabledItem(AppConstants.appName))
        menu.addItem(.separator())
        menu.addItem(disabledItem(L10n.tr("menu.connections")))

        if store.connections.isEmpty {
            menu.addItem(disabledItem(L10n.tr("menu.noConnections")))
        } else {
            for connection in store.connections {
                let state = tunnelManager.state(for: connection.id)
                let title = "\(connection.name)  \(connection.localEndpoint)"
                let item = NSMenuItem(
                    title: title,
                    action: #selector(toggleConnection(_:)),
                    keyEquivalent: ""
                )
                item.image = statusImage(for: state)
                item.target = self
                item.representedObject = connection.id.uuidString
                item.toolTip = connection.menuDetail
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.tr("menu.openManager"), #selector(openManager), symbolNames: ["macwindow", "list.bullet.rectangle"]))
        menu.addItem(menuItem(L10n.tr("menu.addConnection"), #selector(createConnection), symbolNames: ["plus.circle"]))
        menu.addItem(menuItem(L10n.tr("menu.settings"), #selector(openSettings), symbolNames: ["gearshape"]))
        menu.addItem(menuItem(L10n.tr("menu.help"), #selector(openHelp), symbolNames: ["questionmark.circle"]))

        let stopAllItem = menuItem(L10n.tr("menu.stopAll"), #selector(stopAllConnections), symbolNames: ["stop.circle"])
        stopAllItem.isEnabled = tunnelManager.activeCount() > 0
        menu.addItem(stopAllItem)

        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.tr("menu.quit"), #selector(quit), symbolNames: ["power"]))

        statusItem.menu = menu
        updateButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = statusBarImage(activeCount: 0)
        button.imagePosition = .imageOnly
        button.toolTip = AppConstants.appName
    }

    private func updateButton() {
        guard let button = statusItem.button else {
            return
        }

        let count = tunnelManager.activeCount()
        button.image = statusBarImage(activeCount: count)
        button.title = ""
        if count == 1 {
            button.toolTip = L10n.trf("menu.tooltip.active.one", AppConstants.appName)
        } else if count > 1 {
            button.toolTip = L10n.trf("menu.tooltip.active.many", AppConstants.appName, count)
        } else {
            button.toolTip = AppConstants.appName
        }
    }

    private func statusBarImage(activeCount: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 18, height: 18).fill()

        let arrowColor = activeCount > 0 ? NSColor.systemGreen : NSColor(calibratedRed: 0.16, green: 0.29, blue: 0.58, alpha: 1)
        let dotColor = NSColor(calibratedRed: 0.13, green: 0.65, blue: 0.88, alpha: 1)

        let top = NSBezierPath()
        top.move(to: NSPoint(x: 3.2, y: 8.0))
        top.line(to: NSPoint(x: 3.2, y: 12.0))
        top.curve(to: NSPoint(x: 6.1, y: 14.8), controlPoint1: NSPoint(x: 3.2, y: 13.7), controlPoint2: NSPoint(x: 4.5, y: 14.8))
        top.line(to: NSPoint(x: 10.0, y: 14.8))
        top.lineWidth = 2.4
        top.lineCapStyle = .round
        top.lineJoinStyle = .round
        arrowColor.setStroke()
        top.stroke()

        let topHead = NSBezierPath()
        topHead.move(to: NSPoint(x: 14.3, y: 14.8))
        topHead.line(to: NSPoint(x: 9.8, y: 17.5))
        topHead.line(to: NSPoint(x: 9.8, y: 12.1))
        topHead.close()
        arrowColor.setFill()
        topHead.fill()

        let bottom = NSBezierPath()
        bottom.move(to: NSPoint(x: 14.8, y: 10.0))
        bottom.line(to: NSPoint(x: 14.8, y: 6.0))
        bottom.curve(to: NSPoint(x: 11.9, y: 3.2), controlPoint1: NSPoint(x: 14.8, y: 4.3), controlPoint2: NSPoint(x: 13.5, y: 3.2))
        bottom.line(to: NSPoint(x: 8.0, y: 3.2))
        bottom.lineWidth = 2.4
        bottom.lineCapStyle = .round
        bottom.lineJoinStyle = .round
        arrowColor.setStroke()
        bottom.stroke()

        let bottomHead = NSBezierPath()
        bottomHead.move(to: NSPoint(x: 3.7, y: 3.2))
        bottomHead.line(to: NSPoint(x: 8.2, y: 5.9))
        bottomHead.line(to: NSPoint(x: 8.2, y: 0.5))
        bottomHead.close()
        arrowColor.setFill()
        bottomHead.fill()

        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1.4, y: 0.8, width: 3.4, height: 3.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 13.2, y: 13.8, width: 3.4, height: 3.4)).fill()

        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = AppConstants.appName
        return image
    }

    private func color(for state: TunnelState) -> NSColor {
        switch state {
        case .running:
            return .systemGreen
        case .starting:
            return .systemYellow
        case .stopping:
            return .systemOrange
        case .failed, .stopped:
            return .systemRed
        }
    }

    private func statusImage(for state: TunnelState) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()

        color(for: state).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 14, height: 14)).fill()

        let glyphColor = statusGlyphColor(for: state)
        glyphColor.setFill()
        glyphColor.setStroke()

        switch state {
        case .running:
            let check = NSBezierPath()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: 4.2, y: 8.2))
            check.line(to: NSPoint(x: 6.8, y: 5.6))
            check.line(to: NSPoint(x: 11.8, y: 10.4))
            check.stroke()
        case .starting:
            let play = NSBezierPath()
            play.move(to: NSPoint(x: 6, y: 4.8))
            play.line(to: NSPoint(x: 6, y: 11.2))
            play.line(to: NSPoint(x: 11, y: 8))
            play.close()
            play.fill()
        case .stopping:
            NSBezierPath(roundedRect: NSRect(x: 5.4, y: 5.4, width: 5.2, height: 5.2), xRadius: 1, yRadius: 1).fill()
        case .failed:
            let mark = NSBezierPath()
            mark.lineWidth = 2
            mark.lineCapStyle = .round
            mark.move(to: NSPoint(x: 8, y: 7.3))
            mark.line(to: NSPoint(x: 8, y: 11))
            mark.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 4.3, width: 2, height: 2)).fill()
        case .stopped:
            let line = NSBezierPath()
            line.lineWidth = 2
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 5, y: 8))
            line.line(to: NSPoint(x: 11, y: 8))
            line.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func statusGlyphColor(for state: TunnelState) -> NSColor {
        switch state {
        case .starting:
            return NSColor(calibratedWhite: 0.18, alpha: 0.9)
        case .running, .stopping, .failed, .stopped:
            return .white
        }
    }

    private func disabledItem(_ title: String, symbolNames: [String] = [], image: NSImage? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = image ?? symbolImage(symbolNames)
        return item
    }

    private func menuItem(_ title: String, _ action: Selector, symbolNames: [String] = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = symbolImage(symbolNames)
        return item
    }

    private func symbolImage(_ names: [String]) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    @objc private func toggleConnection(_ sender: NSMenuItem) {
        guard
            let rawID = sender.representedObject as? String,
            let id = UUID(uuidString: rawID),
            let connection = store.connection(id: id)
        else {
            return
        }

        tunnelManager.toggle(connection)
        refresh()
    }

    @objc private func stopAllConnections() {
        tunnelManager.stopAll()
        refresh()
    }

    @objc private func openManager() {
        showManager()
    }

    @objc private func createConnection() {
        addConnection()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openHelp() {
        showHelp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
