import AppKit

@MainActor
final class ConnectionWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ConnectionStore
    private let tunnelManager: TunnelManager

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    private let nameField = NSTextField()
    private let sshUserField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let hostField = NSTextField()
    private let sshPortField = NSTextField()
    private let remotePortField = NSTextField()
    private let containerField = NSTextField()
    private let networkField = NSTextField()
    private let bindAddressField = NSTextField()
    private let localPortField = NSTextField()
    private let autoStartButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private let newButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private let deleteButton = NSButton(title: "", target: nil, action: nil)
    private let startStopButton = NSButton(title: "", target: nil, action: nil)
    private let openLogButton = NSButton(title: "", target: nil, action: nil)

    private var selectedID: UUID?
    private var formLabels: [String: NSTextField] = [:]

    init(store: ConnectionStore, tunnelManager: TunnelManager) {
        self.store = store
        self.tunnelManager = tunnelManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppConstants.appName
        window.minSize = NSSize(width: 700, height: 480)

        super.init(window: window)
        setupUI()
        applyLocalization()
        reload()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        reload()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func prepareNewConnection() {
        showAndFocus()
        createConnection(nil)
    }

    func reload() {
        tableView.reloadData()

        if let selectedID, let index = store.connections.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            populateFields(with: store.connections[index])
        } else if let first = store.connections.first {
            selectedID = first.id
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            populateFields(with: first)
        } else {
            selectedID = nil
            populateFields(with: BridgeConnection.defaultConnection())
        }

        updateStatusLabels()
        updateButtons()
    }

    func applyLocalization() {
        window?.title = AppConstants.appName
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name"))?.title = L10n.tr("connection.table.name")
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("status"))?.title = L10n.tr("connection.table.status")

        for (key, label) in formLabels {
            label.stringValue = L10n.tr(key)
        }

        newButton.title = L10n.tr("connection.button.new")
        saveButton.title = L10n.tr("common.save")
        deleteButton.title = L10n.tr("connection.button.delete")
        openLogButton.title = L10n.tr("connection.button.openLog")
        autoStartButton.title = L10n.tr("connection.form.autoStart.checkbox")

        configureFieldPlaceholders()
        updateStatusLabels()
        updateButtons()
        tableView.reloadData()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let rootStack = NSStackView()
        rootStack.orientation = .horizontal
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        rootStack.addArrangedSubview(makeSidebar())
        rootStack.addArrangedSubview(makeForm())
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSStackView()
        sidebar.orientation = .vertical
        sidebar.spacing = 10
        sidebar.widthAnchor.constraint(equalToConstant: 280).isActive = true

        tableView.addTableColumn(makeColumn(id: "name", title: L10n.tr("connection.table.name"), width: 170))
        tableView.addTableColumn(makeColumn(id: "status", title: L10n.tr("connection.table.status"), width: 64))
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 28

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        let buttonRow = NSStackView(views: [newButton, deleteButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        newButton.target = self
        newButton.action = #selector(createConnection(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteConnection(_:))

        sidebar.addArrangedSubview(scrollView)
        sidebar.addArrangedSubview(buttonRow)
        return sidebar
    }

    private func makeForm() -> NSView {
        let form = NSStackView()
        form.orientation = .vertical
        form.spacing = 12

        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        form.addArrangedSubview(statusLabel)
        form.addArrangedSubview(detailLabel)
        form.addArrangedSubview(separator())
        form.addArrangedSubview(row("connection.form.name", nameField))
        form.addArrangedSubview(row("connection.form.sshUser", sshUserField))
        form.addArrangedSubview(row("connection.form.password", passwordField))
        form.addArrangedSubview(row("connection.form.host", hostField))
        form.addArrangedSubview(row("connection.form.sshPort", sshPortField))
        form.addArrangedSubview(row("connection.form.container", containerField))
        form.addArrangedSubview(row("connection.form.network", networkField))
        form.addArrangedSubview(row("connection.form.remotePort", remotePortField))
        form.addArrangedSubview(row("connection.form.localIP", bindAddressField))
        form.addArrangedSubview(row("connection.form.localPort", localPortField))
        form.addArrangedSubview(checkboxRow("connection.form.autoStart", autoStartButton))
        form.addArrangedSubview(separator())
        form.addArrangedSubview(actionRow())

        let spacer = NSView()
        form.addArrangedSubview(spacer)

        configureFieldPlaceholders()
        return form
    }

    private func actionRow() -> NSView {
        let row = NSStackView(views: [saveButton, startStopButton, openLogButton])
        row.orientation = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually

        saveButton.target = self
        saveButton.action = #selector(saveConnection(_:))
        startStopButton.target = self
        startStopButton.action = #selector(toggleConnection(_:))
        openLogButton.target = self
        openLogButton.action = #selector(openLog(_:))

        return row
    }

    private func row(_ labelKey: String, _ field: NSTextField) -> NSView {
        let labelView = NSTextField(labelWithString: L10n.tr(labelKey))
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 110).isActive = true
        formLabels[labelKey] = labelView

        field.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let stack = NSStackView(views: [labelView, field])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func checkboxRow(_ labelKey: String, _ checkbox: NSButton) -> NSView {
        let labelView = NSTextField(labelWithString: L10n.tr(labelKey))
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 110).isActive = true
        formLabels[labelKey] = labelView

        checkbox.title = L10n.tr("connection.form.autoStart.checkbox")

        let stack = NSStackView(views: [labelView, checkbox])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeColumn(id: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        return column
    }

    private func configureFieldPlaceholders() {
        nameField.placeholderString = "Example Tunnel"
        sshUserField.placeholderString = "ssh-user"
        passwordField.placeholderString = L10n.tr("connection.password.placeholder.certificate")
        hostField.placeholderString = "server.example.com"
        sshPortField.placeholderString = "22"
        containerField.placeholderString = "app-container"
        networkField.placeholderString = "docker-network"
        remotePortField.placeholderString = "5432"
        bindAddressField.placeholderString = "127.0.0.1"
        localPortField.placeholderString = "15432"
    }

    private func populateFields(with connection: BridgeConnection) {
        nameField.stringValue = connection.name
        sshUserField.stringValue = connection.sshUser
        passwordField.stringValue = ""
        passwordField.placeholderString = PasswordStore.shared.hasPassword(for: connection.id)
            ? L10n.tr("connection.password.placeholder.saved")
            : L10n.tr("connection.password.placeholder.certificate")
        hostField.stringValue = connection.host.lowercased()
        sshPortField.stringValue = String(connection.sshPort)
        remotePortField.stringValue = String(connection.remotePort)
        containerField.stringValue = connection.container
        networkField.stringValue = connection.network
        bindAddressField.stringValue = connection.bindAddress
        localPortField.stringValue = String(connection.localPort)
        autoStartButton.state = connection.autoStartOnLaunch ? .on : .off
        updateStatusLabels()
        updateButtons()
    }

    private func updateStatusLabels() {
        guard let selectedID else {
            statusLabel.stringValue = L10n.tr("connection.status.unsaved")
            detailLabel.stringValue = L10n.tr("connection.detail.unsaved")
            return
        }

        let state = tunnelManager.state(for: selectedID)
        statusLabel.stringValue = L10n.trf("connection.status.format", state.label)

        if let connection = store.connection(id: selectedID) {
            detailLabel.stringValue = "\(connection.localEndpoint) -> \(connection.sshEndpoint)/\(connection.remoteEndpoint)"
        } else {
            detailLabel.stringValue = state.detail
        }
    }

    private func updateButtons() {
        let hasSelection = selectedID != nil
        let isActive = selectedID.map { tunnelManager.state(for: $0).isActive } ?? false
        deleteButton.isEnabled = hasSelection
        startStopButton.title = isActive ? L10n.tr("connection.button.stop") : L10n.tr("connection.button.start")
        openLogButton.isEnabled = selectedID.flatMap { tunnelManager.session(for: $0) } != nil
    }

    @objc private func createConnection(_ sender: Any?) {
        selectedID = nil
        tableView.deselectAll(nil)
        var connection = BridgeConnection.defaultConnection()
        connection.name = uniqueName(base: L10n.tr("connection.defaultNewName"))
        populateFields(with: connection)
        updateStatusLabels()
        updateButtons()
    }

    @objc private func saveConnection(_ sender: Any?) {
        guard let connection = validatedConnectionFromForm() else {
            return
        }

        selectedID = connection.id
        persistPassword(for: connection)
        store.upsert(connection)
        reload()
    }

    @objc private func deleteConnection(_ sender: Any?) {
        guard let selectedID else {
            return
        }

        tunnelManager.forget(id: selectedID)
        store.delete(id: selectedID)
        self.selectedID = nil
        reload()
    }

    @objc private func toggleConnection(_ sender: Any?) {
        guard let connection = validatedConnectionFromForm() else {
            return
        }

        selectedID = connection.id
        persistPassword(for: connection)
        store.upsert(connection)
        tunnelManager.toggle(connection)
        reload()
    }

    @objc private func openLog(_ sender: Any?) {
        guard
            let selectedID,
            let session = tunnelManager.session(for: selectedID)
        else {
            showAlert(message: L10n.tr("connection.alert.noLog"))
            return
        }

        NSWorkspace.shared.open(session.logURL)
    }

    private func validatedConnectionFromForm() -> BridgeConnection? {
        let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = sshUserField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedContainer = containerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNetwork = networkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBind = bindAddressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            showAlert(message: L10n.tr("connection.alert.nameRequired"))
            return nil
        }

        guard !trimmedUser.isEmpty, !trimmedHost.isEmpty else {
            showAlert(message: L10n.tr("connection.alert.sshRequired"))
            return nil
        }

        guard !trimmedContainer.isEmpty, !trimmedNetwork.isEmpty else {
            showAlert(message: L10n.tr("connection.alert.dockerRequired"))
            return nil
        }

        guard
            let sshPort = port(from: sshPortField.stringValue),
            let remotePort = port(from: remotePortField.stringValue),
            let localPort = port(from: localPortField.stringValue)
        else {
            showAlert(message: L10n.tr("connection.alert.invalidPorts"))
            return nil
        }

        let id = selectedID ?? UUID()
        return BridgeConnection(
            id: id,
            name: trimmedName,
            sshUser: trimmedUser,
            host: trimmedHost,
            sshPort: sshPort,
            remotePort: remotePort,
            container: trimmedContainer,
            network: trimmedNetwork,
            bindAddress: trimmedBind.isEmpty ? "127.0.0.1" : trimmedBind,
            localPort: localPort,
            autoStartOnLaunch: autoStartButton.state == .on,
            createdAt: store.connection(id: id)?.createdAt ?? Date()
        )
    }

    private func persistPassword(for connection: BridgeConnection) {
        let password = passwordField.stringValue
        if password.isEmpty {
            PasswordStore.shared.delete(for: connection.id)
            return
        }

        do {
            try PasswordStore.shared.save(password, for: connection.id)
            passwordField.stringValue = ""
        } catch {
            showAlert(message: L10n.tr("connection.alert.passwordSaveFailed"))
        }
    }

    private func port(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private func uniqueName(base: String) -> String {
        var candidate = base
        var suffix = 2
        let names = Set(store.connections.map { $0.name })

        while names.contains(candidate) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.connections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < store.connections.count else {
            return nil
        }

        let connection = store.connections[row]
        if tableColumn?.identifier.rawValue == "status" {
            let state = tunnelManager.state(for: connection.id)
            let id = NSUserInterfaceItemIdentifier("StatusCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
                ?? makeStatusCell(identifier: id)
            cell.imageView?.image = statusIcon(for: state)
            let tooltip = L10n.trf("connection.status.tooltip", state.label)
            cell.toolTip = tooltip
            cell.imageView?.toolTip = tooltip
            return cell
        }

        let id = NSUserInterfaceItemIdentifier("NameCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
            ?? makeNameCell(identifier: id)
        cell.textField?.stringValue = connection.name
        cell.textField?.textColor = .labelColor
        cell.toolTip = connection.name
        return cell
    }

    private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    private func makeStatusCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18)
        ])

        return cell
    }

    private func statusIcon(for state: TunnelState) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        statusColor(for: state).setFill()
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

    private func statusColor(for state: TunnelState) -> NSColor {
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

    private func statusGlyphColor(for state: TunnelState) -> NSColor {
        switch state {
        case .starting:
            return NSColor(calibratedWhite: 0.18, alpha: 0.9)
        case .running, .stopping, .failed, .stopped:
            return .white
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < store.connections.count else {
            return
        }

        let connection = store.connections[row]
        selectedID = connection.id
        populateFields(with: connection)
    }
}
