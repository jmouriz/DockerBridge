import Foundation

struct AppSettings: Codable, Equatable {
    var logDirectoryPath: String
    var connectTimeoutSeconds: Int
    var serverAliveIntervalSeconds: Int
    var serverAliveCountMax: Int
    var languageCode: String

    init(
        logDirectoryPath: String,
        connectTimeoutSeconds: Int,
        serverAliveIntervalSeconds: Int,
        serverAliveCountMax: Int,
        languageCode: String = AppLanguage.system.rawValue
    ) {
        self.logDirectoryPath = logDirectoryPath
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.serverAliveIntervalSeconds = serverAliveIntervalSeconds
        self.serverAliveCountMax = serverAliveCountMax
        self.languageCode = languageCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.defaults()
        logDirectoryPath = try container.decodeIfPresent(String.self, forKey: .logDirectoryPath) ?? defaults.logDirectoryPath
        connectTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .connectTimeoutSeconds) ?? defaults.connectTimeoutSeconds
        serverAliveIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .serverAliveIntervalSeconds) ?? defaults.serverAliveIntervalSeconds
        serverAliveCountMax = try container.decodeIfPresent(Int.self, forKey: .serverAliveCountMax) ?? defaults.serverAliveCountMax
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode) ?? defaults.languageCode
    }

    static func defaults() -> AppSettings {
        AppSettings(
            logDirectoryPath: AppPaths.defaultLogDirectoryURL.path,
            connectTimeoutSeconds: 15,
            serverAliveIntervalSeconds: 30,
            serverAliveCountMax: 3,
            languageCode: AppLanguage.system.rawValue
        )
    }

    var logDirectoryURL: URL {
        URL(fileURLWithPath: logDirectoryPath, isDirectory: true)
    }

    var language: AppLanguage {
        AppLanguage.normalized(languageCode)
    }
}

enum AppPaths {
    static var supportDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent(AppConstants.supportDirectoryName, isDirectory: true)
    }

    static var legacySupportDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent(AppConstants.legacySupportDirectoryName, isDirectory: true)
    }

    static var defaultLogDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("Logs", isDirectory: true)
    }

}

@MainActor
final class AppSettingsStore {
    private(set) var settings: AppSettings = .defaults()
    private let storageURL: URL
    var onChange: (() -> Void)?

    init() {
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectoryURL, withIntermediateDirectories: true)
        storageURL = AppPaths.supportDirectoryURL.appendingPathComponent("settings.json")
        load()
    }

    func update(_ newSettings: AppSettings) {
        settings = sanitized(newSettings)
        save()
        onChange?()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            settings = .defaults()
            save()
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let storedValues = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            settings = sanitized(try JSONDecoder().decode(AppSettings.self, from: data))
            if storedValues?["connectScriptPath"] != nil {
                save()
            }
        } catch {
            settings = .defaults()
            save()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: settings.logDirectoryURL, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            NSLog("Could not save settings: \(error.localizedDescription)")
        }
    }

    private func sanitized(_ value: AppSettings) -> AppSettings {
        var copy = value
        copy.logDirectoryPath = copy.logDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.logDirectoryPath.isEmpty {
            copy.logDirectoryPath = AppPaths.defaultLogDirectoryURL.path
        }
        copy.connectTimeoutSeconds = clamp(copy.connectTimeoutSeconds, min: 3, max: 300)
        copy.serverAliveIntervalSeconds = clamp(copy.serverAliveIntervalSeconds, min: 0, max: 300)
        copy.serverAliveCountMax = clamp(copy.serverAliveCountMax, min: 1, max: 20)
        copy.languageCode = AppLanguage.normalized(copy.languageCode).rawValue
        return copy
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}
