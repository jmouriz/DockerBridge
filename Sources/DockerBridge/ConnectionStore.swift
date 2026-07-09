import Foundation

@MainActor
final class ConnectionStore {
    private(set) var connections: [BridgeConnection] = []
    let storageURL: URL
    private let legacyStorageURL: URL
    var onChange: (() -> Void)?

    init() {
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectoryURL, withIntermediateDirectories: true)
        storageURL = AppPaths.supportDirectoryURL.appendingPathComponent("connections.json")
        legacyStorageURL = AppPaths.legacySupportDirectoryURL.appendingPathComponent("connections.json")
    }

    func load() {
        migrateLegacyStorageIfNeeded()

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            connections = [BridgeConnection.defaultConnection()]
            save(notify: false)
            onChange?()
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            connections = try JSONDecoder().decode([BridgeConnection].self, from: data)
        } catch {
            connections = [BridgeConnection.defaultConnection()]
            save(notify: false)
        }

        onChange?()
    }

    func upsert(_ connection: BridgeConnection) {
        var copy = connection
        copy.updatedAt = Date()

        if let index = connections.firstIndex(where: { $0.id == copy.id }) {
            connections[index] = copy
        } else {
            connections.append(copy)
        }

        save()
    }

    func delete(id: UUID) {
        connections.removeAll { $0.id == id }
        PasswordStore.shared.delete(for: id)
        save()
    }

    func connection(id: UUID) -> BridgeConnection? {
        connections.first { $0.id == id }
    }

    private func save(notify: Bool = true) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(connections)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            NSLog("Could not save connections: \(error.localizedDescription)")
        }

        if notify {
            onChange?()
        }
    }

    private func migrateLegacyStorageIfNeeded() {
        guard
            !FileManager.default.fileExists(atPath: storageURL.path),
            FileManager.default.fileExists(atPath: legacyStorageURL.path)
        else {
            return
        }

        do {
            try FileManager.default.copyItem(at: legacyStorageURL, to: storageURL)
        } catch {
            NSLog("Could not migrate legacy connections: \(error.localizedDescription)")
        }
    }
}
