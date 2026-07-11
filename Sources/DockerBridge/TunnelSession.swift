import Foundation
import NIOSSH

@MainActor
final class TunnelSession {
    let connection: BridgeConnection
    let logURL: URL
    private let settings: AppSettings
    private(set) var state: TunnelState = .stopped
    private(set) var output: String = ""

    var onChange: (() -> Void)?

    private var tunnel: NativeSSHTunnel?
    private var lifecycleTask: Task<Void, Never>?
    private var logHandle: FileHandle?
    private var stopRequested = false

    init(connection: BridgeConnection, settings: AppSettings) {
        self.connection = connection
        self.settings = settings
        self.logURL = settings.logDirectoryURL.appendingPathComponent("\(connection.id.uuidString).log")
    }

    func start() {
        guard !state.isActive else {
            return
        }

        output = ""
        stopRequested = false
        prepareLogFile()

        let password: String?
        do {
            password = try PasswordStore.shared.password(for: connection.id)
        } catch {
            fail(error)
            return
        }

        let privateKey: NIOSSHPrivateKey?
        do {
            privateKey = password == nil ? try OpenSSHPrivateKeyLoader.loadDefaultKey() : nil
        } catch {
            fail(error)
            return
        }

        let tunnel = NativeSSHTunnel(
            connection: connection,
            settings: settings,
            password: password,
            privateKey: privateKey,
            onLog: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.appendLog(message)
                }
            }
        )
        self.tunnel = tunnel

        appendLog(
            privateKey == nil
                ? L10n.tr("tunnel.log.passwordAuthentication")
                : L10n.tr("tunnel.log.privateKeyAuthentication")
        )
        state = .starting(Date())
        onChange?()

        lifecycleTask = Task { [weak self, tunnel] in
            do {
                let result = try await tunnel.start()
                guard let self else {
                    await tunnel.stop()
                    return
                }

                guard !self.stopRequested else {
                    await tunnel.stop()
                    self.finishStopped()
                    return
                }

                self.appendLog(
                    L10n.trf("tunnel.log.started", result.containerIPAddress, self.connection.remotePort)
                )
                self.state = .running(Date())
                self.onChange?()

                try await tunnel.waitUntilClosed()
                if self.stopRequested {
                    self.finishStopped()
                } else {
                    await tunnel.stop()
                    self.fail(NativeSSHTunnelError.commandFailed(
                        status: -1,
                        message: L10n.tr("tunnel.error.connectionClosed")
                    ))
                }
            } catch {
                guard let self else {
                    return
                }

                if self.stopRequested || (error as? NativeSSHTunnelError) == .stopped {
                    self.finishStopped()
                } else {
                    await tunnel.stop()
                    self.fail(error)
                }
            }
        }
    }

    func stop() {
        guard state.isActive else {
            state = .stopped
            onChange?()
            return
        }

        stopRequested = true
        state = .stopping
        appendLog(L10n.tr("tunnel.log.stopping"))
        onChange?()

        let tunnel = self.tunnel
        Task { [weak self] in
            await tunnel?.stop()
            self?.finishStopped()
        }
    }

    private func prepareLogFile() {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
    }

    private func appendLog(_ message: String) {
        let line = "[\(Self.timestamp.string(from: Date()))] \(message)\n"
        output += line
        logHandle?.write(Data(line.utf8))
        onChange?()
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        appendLog(L10n.trf("tunnel.log.failed", message))
        closeLogFile()
        tunnel = nil
        lifecycleTask = nil
        state = .failed(message)
        onChange?()
    }

    private func finishStopped() {
        guard state != .stopped else {
            return
        }

        appendLog(L10n.tr("tunnel.log.stopped"))
        closeLogFile()
        tunnel = nil
        lifecycleTask = nil
        state = .stopped
        onChange?()
    }

    private func closeLogFile() {
        logHandle?.closeFile()
        logHandle = nil
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
