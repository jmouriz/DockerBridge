import Foundation
import Darwin

enum LoginAgentError: LocalizedError {
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchctlFailed(let message):
            return message
        }
    }
}

enum LoginAgentManager {
    static let label = "ar.tecnologica.dockerbridge"

    static var plistURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install(appURL: URL = Bundle.main.bundleURL) throws {
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                appURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("MacOS", isDirectory: true)
                    .appendingPathComponent(AppConstants.bundleName)
                    .path,
                "--background"
            ],
            "RunAtLoad": true,
            "WorkingDirectory": appURL.deletingLastPathComponent().path
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: [.atomic])

        _ = try? runLaunchctl(["bootout", guiTarget(), plistURL.path], allowFailure: true)
        try runLaunchctl(["bootstrap", guiTarget(), plistURL.path])
        try runLaunchctl(["enable", "\(guiTarget())/\(label)"])
    }

    static func uninstall() throws {
        _ = try? runLaunchctl(["bootout", guiTarget(), plistURL.path], allowFailure: true)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func guiTarget() -> String {
        "gui/\(getuid())"
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        if process.terminationStatus != 0, !allowFailure {
            throw LoginAgentError.launchctlFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}
