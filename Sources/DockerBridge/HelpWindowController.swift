import AppKit
import WebKit

@MainActor
final class HelpWindowController: NSWindowController {
    private let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.trf("help.title", AppConstants.appName)
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.contentView = NSView()

        super.init(window: window)

        configureContent()
        loadOverview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        loadOverview()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyLocalization() {
        window?.title = L10n.trf("help.title", AppConstants.appName)
        loadOverview()
    }

    private func configureContent() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.12, alpha: 1).cgColor
        contentView.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func loadOverview() {
        guard let overviewURL = L10n.localizedResourceURL(forResource: "overview", withExtension: "svg") else {
            showMissingOverview()
            return
        }

        let html = """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body {
                width: 100%;
                height: 100%;
                margin: 0;
                background: #08111f;
                overflow: hidden;
              }

              body {
                display: flex;
                align-items: center;
                justify-content: center;
              }

              img {
                width: 100%;
                height: 100%;
                object-fit: contain;
                display: block;
              }
            </style>
          </head>
          <body>
            <img src="\(overviewURL.lastPathComponent)" alt="\(L10n.tr("help.overviewAlt"))">
          </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: overviewURL.deletingLastPathComponent())
    }

    private func showMissingOverview() {
        let html = """
        <!doctype html>
        <html>
          <body style="margin:0;background:#08111f;color:#f4f7fb;font:16px -apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;">
            \(L10n.tr("help.missingOverview"))
          </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }
}
