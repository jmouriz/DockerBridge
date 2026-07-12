import AppKit

@MainActor
final class AboutWindowController: NSWindowController {
    private let appIconView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let buildDateLabel = NSTextField(labelWithString: "")
    private let developerLabel = NSTextField(labelWithString: "")
    private let disclaimerLabel = NSTextField(wrappingLabelWithString: "")
    private let repositoryButton = NSButton(title: "", target: nil, action: nil)
    private let licenseButton = NSButton(title: "", target: nil, action: nil)
    private let thirdPartyButton = NSButton(title: "", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
        applyLocalization()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        applyLocalization()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyLocalization() {
        window?.title = L10n.trf("about.title", AppConstants.appName)
        appNameLabel.stringValue = AppConstants.appName
        versionLabel.stringValue = L10n.trf("about.version", version, buildNumber)
        buildDateLabel.stringValue = L10n.trf("about.buildDate", formattedBuildDate)
        developerLabel.stringValue = L10n.trf("about.developer", AppConstants.developerName)
        disclaimerLabel.stringValue = L10n.tr("about.disclaimer")

        updateLinkButton(repositoryButton, titleKey: "about.link.github", symbolName: "chevron.left.forwardslash.chevron.right")
        updateLinkButton(licenseButton, titleKey: "about.link.license", symbolName: "doc.text")
        updateLinkButton(thirdPartyButton, titleKey: "about.link.thirdParty", symbolName: "books.vertical")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        appIconView.image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            appIconView.widthAnchor.constraint(equalToConstant: 88),
            appIconView.heightAnchor.constraint(equalToConstant: 88)
        ])
        root.addArrangedSubview(appIconView)

        appNameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        appNameLabel.alignment = .center
        root.addArrangedSubview(appNameLabel)

        for label in [versionLabel, buildDateLabel, developerLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            root.addArrangedSubview(label)
        }

        root.setCustomSpacing(16, after: developerLabel)

        let separator = NSBox()
        separator.boxType = .separator
        root.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -96).isActive = true
        root.setCustomSpacing(14, after: separator)

        repositoryButton.target = self
        repositoryButton.action = #selector(openRepository(_:))
        licenseButton.target = self
        licenseButton.action = #selector(openLicense(_:))
        thirdPartyButton.target = self
        thirdPartyButton.action = #selector(openThirdPartyLicenses(_:))

        let links = NSStackView(views: [repositoryButton, licenseButton, thirdPartyButton])
        links.orientation = .horizontal
        links.alignment = .centerY
        links.spacing = 8
        root.addArrangedSubview(links)

        for button in [repositoryButton, licenseButton, thirdPartyButton] {
            button.bezelStyle = .rounded
            button.imagePosition = .imageLeading
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }

        root.setCustomSpacing(16, after: links)

        disclaimerLabel.font = .systemFont(ofSize: 11)
        disclaimerLabel.textColor = .tertiaryLabelColor
        disclaimerLabel.alignment = .center
        disclaimerLabel.maximumNumberOfLines = 3
        disclaimerLabel.lineBreakMode = .byWordWrapping
        disclaimerLabel.widthAnchor.constraint(equalToConstant: 500).isActive = true
        root.addArrangedSubview(disclaimerLabel)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L10n.tr("about.unavailable")
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? L10n.tr("about.unavailable")
    }

    private var formattedBuildDate: String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: AppConstants.buildDateInfoKey) as? String,
            let date = buildDateParser.date(from: value)
        else {
            return L10n.tr("about.unavailable")
        }

        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var buildDateParser: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var displayLocale: Locale {
        switch L10n.activeLanguageCode {
        case "es":
            return Locale(identifier: "es")
        case "pt":
            return Locale(identifier: "pt_BR")
        default:
            return Locale(identifier: "en_US")
        }
    }

    private func updateLinkButton(_ button: NSButton, titleKey: String, symbolName: String) {
        button.title = L10n.tr(titleKey)
        button.toolTip = button.title
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: button.title)
        button.image?.isTemplate = true
    }

    @objc private func openRepository(_ sender: Any?) {
        NSWorkspace.shared.open(AppConstants.repositoryURL)
    }

    @objc private func openLicense(_ sender: Any?) {
        NSWorkspace.shared.open(AppConstants.licenseURL)
    }

    @objc private func openThirdPartyLicenses(_ sender: Any?) {
        NSWorkspace.shared.open(AppConstants.thirdPartyLicensesURL)
    }
}
