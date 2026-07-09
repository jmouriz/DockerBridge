import AppKit

@main
struct DockerBridgeMain {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate

        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
