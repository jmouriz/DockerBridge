import Foundation
import NIOCore
import NIOPosix
import NIOSSH

struct NativeSSHTunnelStartResult {
    let containerIPAddress: String
}

private struct NativeSSHConnection: Sendable {
    let channel: Channel
    let handler: NIOLoopBoundBox<NIOSSHHandler?>
}

final class NativeSSHTunnel: @unchecked Sendable {
    private let connection: BridgeConnection
    private let settings: AppSettings
    private let password: String?
    private let privateKey: NIOSSHPrivateKey?
    private let onLog: (String) -> Void
    private let group = NativeSSHRuntime.shared.group
    private let lock = NSLock()

    private var sshChannel: Channel?
    private var serverChannel: Channel?
    private var keepAliveTask: Task<Void, Never>?
    private var stopped = false
    private var terminalError: Error?

    init(
        connection: BridgeConnection,
        settings: AppSettings,
        password: String?,
        privateKey: NIOSSHPrivateKey?,
        onLog: @escaping (String) -> Void
    ) {
        self.connection = connection
        self.settings = settings
        self.password = password
        self.privateKey = privateKey
        self.onLog = onLog
    }

    func start() async throws -> NativeSSHTunnelStartResult {
        guard password?.isEmpty == false || privateKey != nil else {
            throw NativeSSHTunnelError.noCredentials
        }
        try ensureRunning()

        onLog(L10n.trf("tunnel.log.connecting", connection.sshEndpoint))
        let sshConnection = try await connectSSH()
        guard storeSSHChannel(sshConnection.channel) else {
            try? await sshConnection.channel.close().get()
            throw NativeSSHTunnelError.stopped
        }

        do {
            let containerIPAddress = try await discoverContainerIPAddress(using: sshConnection.handler)
            try ensureRunning()

            let serverChannel = try await bindLocalServer(
                sshHandler: sshConnection.handler,
                targetHost: containerIPAddress
            )
            guard storeServerChannel(serverChannel) else {
                try? await serverChannel.close().get()
                throw NativeSSHTunnelError.stopped
            }
            startKeepAlive(using: sshConnection.handler)

            onLog(
                L10n.trf(
                    "tunnel.log.forwarding",
                    connection.localEndpoint,
                    containerIPAddress,
                    connection.remotePort,
                    connection.sshEndpoint
                )
            )
            return NativeSSHTunnelStartResult(containerIPAddress: containerIPAddress)
        } catch {
            await stop()
            throw error
        }
    }

    func waitUntilClosed() async throws {
        let channel = lock.withLock { sshChannel }
        guard let channel else {
            throw NativeSSHTunnelError.stopped
        }

        try await channel.closeFuture.get()

        let outcome = lock.withLock { (stopped, terminalError) }
        if let error = outcome.1 {
            throw error
        }
        if !outcome.0 {
            throw NativeSSHTunnelError.commandFailed(
                status: -1,
                message: L10n.tr("tunnel.error.connectionClosed")
            )
        }
    }

    func stop() async {
        let resources: (Channel?, Channel?, Task<Void, Never>?) = lock.withLock {
            stopped = true
            let resources = (serverChannel, sshChannel, keepAliveTask)
            serverChannel = nil
            sshChannel = nil
            keepAliveTask = nil
            return resources
        }

        resources.2?.cancel()
        if let serverChannel = resources.0 {
            try? await serverChannel.close().get()
        }
        if let sshChannel = resources.1 {
            try? await sshChannel.close().get()
        }
    }

    private func connectSSH() async throws -> NativeSSHConnection {
        let userAuthDelegate = DockerBridgeUserAuthenticationDelegate(
            username: connection.sshUser,
            password: password,
            privateKey: privateKey
        )
        let hostKeyDelegate = DockerBridgeHostKeyDelegate(
            host: connection.host,
            port: connection.sshPort,
            onLog: onLog
        )
        let eventLoop = group.next()
        let handlerBox = NIOLoopBoundBox<NIOSSHHandler?>.makeEmptyBox(
            valueType: NIOSSHHandler.self,
            eventLoop: eventLoop
        )

        let bootstrap = ClientBootstrap(group: eventLoop)
            .connectTimeout(.seconds(Int64(settings.connectTimeoutSeconds)))
            .channelInitializer { [weak self] channel in
                guard let self else {
                    return channel.eventLoop.makeFailedFuture(NativeSSHTunnelError.stopped)
                }

                return channel.eventLoop.makeCompletedFuture {
                    let sshHandler = NIOSSHHandler(
                        role: .client(
                            .init(
                                userAuthDelegate: userAuthDelegate,
                                serverAuthDelegate: hostKeyDelegate
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    handlerBox.value = sshHandler

                    try channel.pipeline.syncOperations.addHandler(sshHandler)
                    try channel.pipeline.syncOperations.addHandler(
                        SSHConnectionErrorHandler { [weak self] error in
                            self?.recordTerminalError(error)
                        }
                    )
                }
            }
            .channelOption(.socketOption(.so_keepalive), value: 1)
            .channelOption(.tcpOption(.tcp_nodelay), value: 1)

        let channel = try await bootstrap.connect(host: connection.host, port: connection.sshPort).get()
        return NativeSSHConnection(channel: channel, handler: handlerBox)
    }

    private func discoverContainerIPAddress(
        using sshHandler: NIOLoopBoundBox<NIOSSHHandler?>
    ) async throws -> String {
        let command = "docker container inspect -- \(shellQuoted(connection.container))"
        onLog(L10n.trf("tunnel.log.inspectingContainer", connection.container, connection.network))

        let result = try await execute(command: command, using: sshHandler)
        guard result.exitStatus == 0 else {
            let message = nonEmpty(result.standardError, fallback: result.standardOutput)
            throw NativeSSHTunnelError.commandFailed(status: result.exitStatus, message: message)
        }

        guard let data = result.standardOutput.data(using: .utf8) else {
            throw NativeSSHTunnelError.invalidDockerResponse
        }

        let records: [DockerInspectRecord]
        do {
            records = try JSONDecoder().decode([DockerInspectRecord].self, from: data)
        } catch {
            throw NativeSSHTunnelError.invalidDockerResponse
        }

        guard let networks = records.first?.networkSettings.networks else {
            throw NativeSSHTunnelError.invalidDockerResponse
        }
        guard let endpoint = networks[connection.network] else {
            throw NativeSSHTunnelError.dockerNetworkNotFound(connection.network)
        }

        let address = nonEmpty(endpoint.ipAddress, fallback: endpoint.globalIPv6Address)
        guard !address.isEmpty else {
            throw NativeSSHTunnelError.dockerIPAddressMissing(connection.network)
        }

        onLog(L10n.trf("tunnel.log.containerAddress", connection.container, address))
        return address
    }

    private func execute(
        command: String,
        using sshHandler: NIOLoopBoundBox<NIOSSHHandler?>
    ) async throws -> SSHCommandResult {
        let eventLoop = sshHandler.eventLoop
        let channelPromise = eventLoop.makePromise(of: Channel.self)
        let resultPromise = eventLoop.makePromise(of: SSHCommandResult.self)

        eventLoop.execute {
            guard let handler = sshHandler.value else {
                channelPromise.fail(NativeSSHTunnelError.stopped)
                resultPromise.fail(NativeSSHTunnelError.stopped)
                return
            }

            handler.createChannel(channelPromise, channelType: .session) { childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(NativeSSHTunnelError.invalidChannelType)
                }

                return childChannel.pipeline.addHandlers(
                    SSHCommandHandler(command: command, completion: resultPromise),
                    SSHConnectionErrorHandler { [weak self] error in
                        self?.onLog(L10n.trf("tunnel.log.channelError", error.localizedDescription))
                    }
                )
            }
        }

        let childChannel = try await channelPromise.futureResult.get()
        let result = try await resultPromise.futureResult.get()
        try? await childChannel.close().get()
        return result
    }

    private func bindLocalServer(
        sshHandler: NIOLoopBoundBox<NIOSSHHandler?>,
        targetHost: String
    ) async throws -> Channel {
        let targetPort = connection.remotePort
        let onLog = self.onLog

        let bootstrap = ServerBootstrap(group: sshHandler.eventLoop)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.so_keepalive), value: 1)
            .childChannelOption(.tcpOption(.tcp_nodelay), value: 1)
            .childChannelInitializer { localChannel in
                guard let handler = sshHandler.value else {
                    return localChannel.eventLoop.makeFailedFuture(NativeSSHTunnelError.stopped)
                }
                guard let originatorAddress = localChannel.remoteAddress else {
                    return localChannel.eventLoop.makeFailedFuture(NativeSSHTunnelError.invalidChannelType)
                }

                let channelPromise = localChannel.eventLoop.makePromise(of: Channel.self)
                let channelType = SSHChannelType.directTCPIP(
                    .init(
                        targetHost: targetHost,
                        targetPort: targetPort,
                        originatorAddress: originatorAddress
                    )
                )

                handler.createChannel(channelPromise, channelType: channelType) { sshChildChannel, type in
                    guard case .directTCPIP = type else {
                        return sshChildChannel.eventLoop.makeFailedFuture(
                            NativeSSHTunnelError.invalidChannelType
                        )
                    }

                    return sshChildChannel.eventLoop.makeCompletedFuture {
                        let (sshGlue, localGlue) = SSHGlueHandler.matchedPair()

                        try sshChildChannel.pipeline.syncOperations.addHandlers(
                            SSHChannelDataWrapper(),
                            sshGlue,
                            SSHConnectionErrorHandler { error in
                                onLog(L10n.trf("tunnel.log.forwardError", error.localizedDescription))
                            }
                        )
                        try localChannel.pipeline.syncOperations.addHandlers(
                            localGlue,
                            SSHConnectionErrorHandler { error in
                                onLog(L10n.trf("tunnel.log.localError", error.localizedDescription))
                            }
                        )
                    }
                }

                return channelPromise.futureResult.map { _ in () }
            }

        return try await bootstrap.bind(host: connection.bindAddress, port: connection.localPort).get()
    }

    private func startKeepAlive(using sshHandler: NIOLoopBoundBox<NIOSSHHandler?>) {
        let interval = settings.serverAliveIntervalSeconds
        guard interval > 0 else {
            return
        }

        let maximumFailures = settings.serverAliveCountMax
        let task = Task { [weak self] in
            var failures = 0

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                    guard let self else {
                        return
                    }

                    let result = try await self.execute(command: "true", using: sshHandler)
                    guard result.exitStatus == 0 else {
                        throw NativeSSHTunnelError.commandFailed(
                            status: result.exitStatus,
                            message: self.nonEmpty(result.standardError, fallback: result.standardOutput)
                        )
                    }
                    failures = 0
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, !self.lock.withLock({ self.stopped }) else {
                        return
                    }

                    failures += 1
                    self.onLog(
                        L10n.trf(
                            "tunnel.log.keepAliveFailure",
                            failures,
                            maximumFailures,
                            error.localizedDescription
                        )
                    )

                    if failures >= maximumFailures {
                        let terminalError = NativeSSHTunnelError.keepAliveFailed(
                            attempts: failures,
                            message: error.localizedDescription
                        )
                        self.recordTerminalError(terminalError)
                        let channel = self.lock.withLock { self.sshChannel }
                        try? await channel?.close().get()
                        return
                    }
                }
            }
        }

        let shouldCancel = lock.withLock {
            guard !stopped else {
                return true
            }
            keepAliveTask = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    private func storeSSHChannel(_ channel: Channel) -> Bool {
        lock.withLock {
            guard !stopped else {
                return false
            }
            sshChannel = channel
            return true
        }
    }

    private func storeServerChannel(_ channel: Channel) -> Bool {
        lock.withLock {
            guard !stopped else {
                return false
            }
            serverChannel = channel
            return true
        }
    }

    private func ensureRunning() throws {
        if lock.withLock({ stopped }) {
            throw NativeSSHTunnelError.stopped
        }
    }

    private func recordTerminalError(_ error: Error) {
        lock.withLock {
            terminalError = error
        }
        onLog(L10n.trf("tunnel.log.sshError", error.localizedDescription))
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class NativeSSHRuntime: @unchecked Sendable {
    static let shared = NativeSSHRuntime()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}

private struct DockerInspectRecord: Decodable {
    let networkSettings: DockerNetworkSettings

    private enum CodingKeys: String, CodingKey {
        case networkSettings = "NetworkSettings"
    }
}

private struct DockerNetworkSettings: Decodable {
    let networks: [String: DockerNetworkEndpoint]

    private enum CodingKeys: String, CodingKey {
        case networks = "Networks"
    }
}

private struct DockerNetworkEndpoint: Decodable {
    let ipAddress: String
    let globalIPv6Address: String

    private enum CodingKeys: String, CodingKey {
        case ipAddress = "IPAddress"
        case globalIPv6Address = "GlobalIPv6Address"
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
