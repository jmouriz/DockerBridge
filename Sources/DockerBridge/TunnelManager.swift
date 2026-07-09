import Foundation

@MainActor
final class TunnelManager {
    private var sessions: [UUID: TunnelSession] = [:]
    private let settingsStore: AppSettingsStore
    var onChange: (() -> Void)?

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    var logDirectoryURL: URL {
        settingsStore.settings.logDirectoryURL
    }

    func start(_ connection: BridgeConnection) {
        if let session = sessions[connection.id], session.state.isActive {
            return
        }

        let session = TunnelSession(connection: connection, settings: settingsStore.settings)
        session.onChange = { [weak self] in
            self?.onChange?()
        }
        sessions[connection.id] = session
        session.start()
        onChange?()
    }

    func stop(id: UUID) {
        sessions[id]?.stop()
        onChange?()
    }

    func toggle(_ connection: BridgeConnection) {
        if state(for: connection.id).isActive {
            stop(id: connection.id)
        } else {
            start(connection)
        }
    }

    func stopAll() {
        sessions.values.forEach { $0.stop() }
        onChange?()
    }

    func forget(id: UUID) {
        sessions[id]?.stop()
        sessions.removeValue(forKey: id)
        onChange?()
    }

    func state(for id: UUID) -> TunnelState {
        sessions[id]?.state ?? .stopped
    }

    func session(for id: UUID) -> TunnelSession? {
        sessions[id]
    }

    func activeSessions() -> [TunnelSession] {
        sessions.values
            .filter { $0.state.isActive }
            .sorted { $0.connection.name.localizedCaseInsensitiveCompare($1.connection.name) == .orderedAscending }
    }

    func activeCount() -> Int {
        activeSessions().count
    }
}
