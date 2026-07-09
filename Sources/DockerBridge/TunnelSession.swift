import Foundation
import Darwin

@MainActor
final class TunnelSession {
    let connection: BridgeConnection
    let logURL: URL
    private let settings: AppSettings
    private(set) var state: TunnelState = .stopped
    private(set) var output: String = ""

    var onChange: (() -> Void)?

    private var process: Process?
    private var pipe: Pipe?
    private var logHandle: FileHandle?

    init(connection: BridgeConnection, settings: AppSettings) {
        self.connection = connection
        self.settings = settings
        self.logURL = settings.logDirectoryURL.appendingPathComponent("\(connection.id.uuidString).log")
    }

    func start() {
        guard process?.isRunning != true else {
            return
        }

        let connectScriptURL = settings.connectScriptURL
        guard FileManager.default.isReadableFile(atPath: connectScriptURL.path) else {
            state = .failed(L10n.trf("tunnel.error.scriptNotFound", connectScriptURL.path))
            onChange?()
            return
        }

        output = ""
        prepareLogFile()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [connectScriptURL.path] + connection.scriptArguments()

        var environment = ProcessInfo.processInfo.environment
        environment["RUNNING_IN_BACKGROUND"] = "1"
        environment["LOG_FILE"] = logURL.path
        environment["SSH_CONNECT_TIMEOUT"] = String(settings.connectTimeoutSeconds)
        environment["SSH_SERVER_ALIVE_INTERVAL"] = String(settings.serverAliveIntervalSeconds)
        environment["SSH_SERVER_ALIVE_COUNT_MAX"] = String(settings.serverAliveCountMax)
        configurePasswordEnvironment(&environment)
        process.environment = environment

        let pipe = Pipe()
        self.pipe = pipe
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            Task { @MainActor [weak self] in
                self?.receive(data: data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { @MainActor [weak self] in
                self?.finish(status: status)
            }
        }

        state = .starting(Date())
        onChange?()

        do {
            try process.run()
            self.process = process
        } catch {
            closeLogFile()
            self.process = nil
            state = .failed(L10n.trf("tunnel.error.couldNotStart", error.localizedDescription))
            onChange?()
        }
    }

    func stop() {
        guard let process, process.isRunning else {
            state = .stopped
            onChange?()
            return
        }

        state = .stopping
        onChange?()

        let pid = process.processIdentifier
        Darwin.kill(pid, SIGTERM)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard
                let self,
                self.process?.processIdentifier == pid,
                self.process?.isRunning == true
            else {
                return
            }

            Darwin.kill(pid, SIGKILL)
        }
    }

    private func receive(data: Data) {
        logHandle?.write(data)

        let text = String(decoding: data, as: UTF8.self)
        output += text

        if output.contains("Estableciendo puente") {
            switch state {
            case .running:
                break
            default:
                state = .running(Date())
            }
        }

        onChange?()
    }

    private func finish(status: Int32) {
        pipe?.fileHandleForReading.readabilityHandler = nil
        closeLogFile()
        process = nil

        switch state {
        case .stopping:
            state = .stopped
        default:
            if status == 0 {
                state = .stopped
            } else {
                state = .failed(lastOutputSummary(fallbackStatus: status))
            }
        }

        onChange?()
    }

    private func prepareLogFile() {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
    }

    private func configurePasswordEnvironment(_ environment: inout [String: String]) {
        guard PasswordStore.shared.hasPassword(for: connection.id) else {
            return
        }

        do {
            let askpassURL = try AskpassHelper.ensureInstalled()
            environment["SSH_ASKPASS"] = askpassURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
            environment["DOCKER_BRIDGE_KEYCHAIN_SERVICE"] = PasswordStore.shared.serviceName(for: connection.id)
            environment["DOCKER_BRIDGE_KEYCHAIN_ACCOUNT"] = PasswordStore.shared.accountName()
        } catch {
            output += L10n.trf("tunnel.error.askpass", error.localizedDescription) + "\n"
        }
    }

    private func closeLogFile() {
        logHandle?.closeFile()
        logHandle = nil
    }

    private func lastOutputSummary(fallbackStatus: Int32) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .suffix(3)
            .map(String.init)
            .joined(separator: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if lines.isEmpty {
            return L10n.trf("tunnel.error.processExited", fallbackStatus)
        }

        return lines
    }
}
