import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settingsStore: AppSettingsStore

    private let logPathField = NSTextField()
    private let connectScriptField = NSTextField()
    private let timeoutField = NSTextField()
    private let aliveIntervalField = NSTextField()
    private let aliveCountField = NSTextField()
    private let languagePopup = NSPopUpButton()
    private let agentStatusIcon = NSImageView()
    private let agentStatusLabel = NSTextField(labelWithString: "")
    private let agentLegendLabel = NSTextField(labelWithString: "")
    private let agentToggleButton = NSButton(title: "", target: nil, action: nil)
    private let chooseLogButton = NSButton(title: "", target: nil, action: nil)
    private let chooseScriptButton = NSButton(title: "", target: nil, action: nil)
    private let bundledScriptButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private var fieldLabels: [String: NSTextField] = [:]

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 426),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("settings.title")
        window.minSize = NSSize(width: 760, height: 426)

        super.init(window: window)
        setupUI()
        applyLocalization()
        populate()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        populate()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        root.addArrangedSubview(row("settings.language", languagePopup))
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage(_:))

        let logRow = row("settings.logLocation", logPathField, trailing: [chooseLogButton])
        chooseLogButton.target = self
        chooseLogButton.action = #selector(chooseLogDirectory(_:))

        let scriptRow = row("settings.connectScript", connectScriptField, trailing: [chooseScriptButton, bundledScriptButton])
        chooseScriptButton.target = self
        chooseScriptButton.action = #selector(chooseConnectScript(_:))
        bundledScriptButton.target = self
        bundledScriptButton.action = #selector(useBundledConnectScript(_:))

        root.addArrangedSubview(logRow)
        root.addArrangedSubview(scriptRow)
        root.addArrangedSubview(separator())
        root.addArrangedSubview(row("settings.timeout", timeoutField))
        root.addArrangedSubview(row("settings.keepAlive", aliveIntervalField))
        root.addArrangedSubview(row("settings.keepAliveAttempts", aliveCountField))
        root.addArrangedSubview(separator())
        root.addArrangedSubview(agentRow())
        root.addArrangedSubview(separator())

        let actionRow = NSStackView(views: [NSView(), saveButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        root.addArrangedSubview(actionRow)

        timeoutField.placeholderString = "15"
        aliveIntervalField.placeholderString = "30"
        aliveCountField.placeholderString = "3"
        connectScriptField.placeholderString = AppPaths.bundledConnectScriptURL.path
    }

    private func populate() {
        let settings = settingsStore.settings
        logPathField.stringValue = settings.logDirectoryPath
        connectScriptField.stringValue = settings.effectiveConnectScriptPath
        timeoutField.stringValue = String(settings.connectTimeoutSeconds)
        aliveIntervalField.stringValue = String(settings.serverAliveIntervalSeconds)
        aliveCountField.stringValue = String(settings.serverAliveCountMax)
        selectLanguage(settings.language)
        updateAgentControls()
    }

    func applyLocalization() {
        window?.title = L10n.tr("settings.title")
        for (key, label) in fieldLabels {
            label.stringValue = L10n.tr(key)
        }

        chooseLogButton.title = L10n.tr("common.choose")
        chooseScriptButton.title = L10n.tr("common.choose")
        bundledScriptButton.title = L10n.tr("settings.useBundledScript")
        saveButton.title = L10n.tr("common.save")
        languagePopup.toolTip = L10n.tr("settings.language.tooltip")
        agentLegendLabel.stringValue = L10n.tr("settings.launchAgent.legend")
        reloadLanguagePopupTitles()
        updateAgentControls()
    }

    private func row(_ labelKey: String, _ control: NSView, trailing: [NSView] = []) -> NSView {
        let labelView = NSTextField(labelWithString: L10n.tr(labelKey))
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 140).isActive = true
        fieldLabels[labelKey] = labelView
        control.heightAnchor.constraint(equalToConstant: 26).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [labelView, control]
        views.append(contentsOf: trailing)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
        return stack
    }

    private func agentRow() -> NSView {
        let labelKey = "settings.launchAgent"
        let labelView = NSTextField(labelWithString: L10n.tr(labelKey))
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 140).isActive = true
        fieldLabels[labelKey] = labelView

        agentStatusIcon.imageScaling = .scaleProportionallyDown
        agentStatusIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        agentStatusIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        agentStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)

        agentToggleButton.target = self
        agentToggleButton.action = #selector(toggleAgent(_:))
        agentToggleButton.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let statusRow = NSStackView(views: [agentStatusIcon, agentStatusLabel, spacer, agentToggleButton])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        agentLegendLabel.textColor = .secondaryLabelColor
        agentLegendLabel.font = .systemFont(ofSize: 12)
        agentLegendLabel.lineBreakMode = .byWordWrapping

        let valueStack = NSStackView(views: [statusRow, agentLegendLabel])
        valueStack.orientation = .vertical
        valueStack.alignment = .leading
        valueStack.spacing = 4

        let stack = NSStackView(views: [labelView, valueStack])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        return stack
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func chooseLogDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: logPathField.stringValue, isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            logPathField.stringValue = url.path
        }
    }

    @objc private func chooseConnectScript(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: connectScriptField.stringValue).deletingLastPathComponent()
        panel.nameFieldStringValue = "connect.sh"

        if panel.runModal() == .OK, let url = panel.url {
            connectScriptField.stringValue = url.path
        }
    }

    @objc private func useBundledConnectScript(_ sender: Any?) {
        connectScriptField.stringValue = AppPaths.bundledConnectScriptURL.path
    }

    @objc private func save(_ sender: Any?) {
        guard
            let timeout = positiveInt(timeoutField.stringValue),
            let aliveInterval = nonNegativeInt(aliveIntervalField.stringValue),
            let aliveCount = positiveInt(aliveCountField.stringValue)
        else {
            showAlert(message: L10n.tr("settings.alert.invalidTimeouts"))
            return
        }

        guard let connectScriptPath = connectScriptPathToStore() else {
            return
        }

        settingsStore.update(
            AppSettings(
                logDirectoryPath: logPathField.stringValue,
                connectScriptPath: connectScriptPath,
                connectTimeoutSeconds: timeout,
                serverAliveIntervalSeconds: aliveInterval,
                serverAliveCountMax: aliveCount,
                languageCode: selectedLanguage().rawValue
            )
        )
        close()
    }

    private func connectScriptPathToStore() -> String? {
        let trimmed = connectScriptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePath = trimmed.isEmpty ? AppPaths.bundledConnectScriptURL.path : trimmed
        let standardizedPath = URL(fileURLWithPath: effectivePath).standardizedFileURL.path

        guard FileManager.default.isReadableFile(atPath: standardizedPath) else {
            showAlert(message: L10n.tr("settings.alert.unreadableScript"))
            return nil
        }

        if standardizedPath == AppPaths.bundledConnectScriptURL.path {
            return ""
        }

        return standardizedPath
    }

    private func reloadLanguagePopupTitles() {
        let selected = selectedLanguage()
        languagePopup.removeAllItems()

        for language in AppLanguage.allCases {
            languagePopup.addItem(withTitle: language.displayName)
            languagePopup.lastItem?.representedObject = language.rawValue
        }

        selectLanguage(selected)
    }

    private func selectLanguage(_ language: AppLanguage) {
        let item = languagePopup.itemArray.first {
            ($0.representedObject as? String) == language.rawValue
        }
        if let item {
            languagePopup.select(item)
        }
    }

    private func selectedLanguage() -> AppLanguage {
        guard let rawValue = languagePopup.selectedItem?.representedObject as? String else {
            return settingsStore.settings.language
        }

        return AppLanguage.normalized(rawValue)
    }

    @objc private func changeLanguage(_ sender: Any?) {
        var settings = settingsStore.settings
        settings.languageCode = selectedLanguage().rawValue
        settingsStore.update(settings)
    }

    @objc private func toggleAgent(_ sender: Any?) {
        do {
            if LoginAgentManager.isInstalled() {
                try LoginAgentManager.uninstall()
            } else {
                try LoginAgentManager.install()
            }
            updateAgentControls()
        } catch {
            showAlert(message: L10n.trf("settings.alert.launchAgentUpdateFailed", error.localizedDescription))
        }
    }

    private func updateAgentControls() {
        let installed = LoginAgentManager.isInstalled()
        agentStatusIcon.image = agentIcon(installed: installed)
        agentStatusLabel.stringValue = installed
            ? L10n.tr("settings.launchAgent.enabled")
            : L10n.tr("settings.launchAgent.disabled")
        agentStatusLabel.textColor = installed ? .labelColor : .secondaryLabelColor
        agentToggleButton.title = installed
            ? L10n.tr("settings.launchAgent.disable")
            : L10n.tr("settings.launchAgent.enable")
        agentToggleButton.toolTip = installed
            ? L10n.tr("settings.launchAgent.disableTooltip")
            : L10n.tr("settings.launchAgent.enableTooltip")
    }

    private func agentIcon(installed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()

        (installed ? NSColor.systemGreen : NSColor.systemRed).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 14, height: 14)).fill()

        NSColor.white.setStroke()
        if installed {
            let check = NSBezierPath()
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: 4.2, y: 8.2))
            check.line(to: NSPoint(x: 6.8, y: 5.6))
            check.line(to: NSPoint(x: 11.8, y: 10.4))
            check.stroke()
        } else {
            let line = NSBezierPath()
            line.lineWidth = 2
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 5, y: 8))
            line.line(to: NSPoint(x: 11, y: 8))
            line.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = installed
            ? L10n.tr("settings.launchAgent.enabledAccessibility")
            : L10n.tr("settings.launchAgent.disabledAccessibility")
        return image
    }

    private func positiveInt(_ value: String) -> Int? {
        guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), intValue > 0 else {
            return nil
        }
        return intValue
    }

    private func nonNegativeInt(_ value: String) -> Int? {
        guard let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), intValue >= 0 else {
            return nil
        }
        return intValue
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
