import AppKit
import Crypto
import Foundation
import NIOCore
import NIOSSH

enum NativeSSHTunnelError: LocalizedError, Equatable {
    case noCredentials
    case hostKeyRejected
    case stopped
    case invalidChannelType
    case commandRejected
    case commandFailed(status: Int, message: String)
    case invalidDockerResponse
    case dockerNetworkNotFound(String)
    case dockerIPAddressMissing(String)
    case keepAliveFailed(attempts: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return L10n.tr("tunnel.error.noCredentials")
        case .hostKeyRejected:
            return L10n.tr("tunnel.error.hostKeyRejected")
        case .stopped:
            return L10n.tr("tunnel.error.stopped")
        case .invalidChannelType:
            return L10n.tr("tunnel.error.invalidChannelType")
        case .commandRejected:
            return L10n.tr("tunnel.error.commandRejected")
        case .commandFailed(let status, let message):
            return L10n.trf("tunnel.error.commandFailed", status, message)
        case .invalidDockerResponse:
            return L10n.tr("tunnel.error.invalidDockerResponse")
        case .dockerNetworkNotFound(let network):
            return L10n.trf("tunnel.error.dockerNetworkNotFound", network)
        case .dockerIPAddressMissing(let network):
            return L10n.trf("tunnel.error.dockerIPAddressMissing", network)
        case .keepAliveFailed(let attempts, let message):
            return L10n.trf("tunnel.error.keepAliveFailed", attempts, message)
        }
    }
}

final class DockerBridgeUserAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private var offers: [NIOSSHUserAuthenticationOffer.Offer]

    init(username: String, password: String?, privateKey: NIOSSHPrivateKey?) {
        self.username = username
        self.offers = []

        if let password, !password.isEmpty {
            offers.append(.password(.init(password: password)))
        }
        if let privateKey {
            offers.append(.privateKey(.init(privateKey: privateKey)))
        }
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        while !offers.isEmpty {
            let offer = offers.removeFirst()
            switch offer {
            case .password where availableMethods.contains(.password):
                nextChallengePromise.succeed(makeOffer(offer))
                return
            case .privateKey where availableMethods.contains(.publicKey):
                nextChallengePromise.succeed(makeOffer(offer))
                return
            default:
                continue
            }
        }

        nextChallengePromise.succeed(nil)
    }

    private func makeOffer(_ offer: NIOSSHUserAuthenticationOffer.Offer) -> NIOSSHUserAuthenticationOffer {
        NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: offer)
    }
}

final class DockerBridgeHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let onLog: (String) -> Void

    init(host: String, port: Int, onLog: @escaping (String) -> Void) {
        self.host = host.lowercased()
        self.port = port
        self.onLog = onLog
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = String(openSSHPublicKey: hostKey)
        let fingerprint = Self.fingerprint(for: key)

        DispatchQueue.main.async { [host, port, onLog] in
            let endpoint = "\(host):\(port)"
            let store = SSHKnownHostsStore.shared

            if let trustedKey = store.key(for: endpoint) {
                guard trustedKey == key else {
                    let accepted = Self.confirmChangedKey(
                        endpoint: endpoint,
                        previousFingerprint: Self.fingerprint(for: trustedKey),
                        fingerprint: fingerprint
                    )
                    guard accepted else {
                        validationCompletePromise.fail(NativeSSHTunnelError.hostKeyRejected)
                        return
                    }

                    store.setKey(key, for: endpoint)
                    onLog(L10n.trf("tunnel.log.hostKeyUpdated", endpoint, fingerprint))
                    validationCompletePromise.succeed(())
                    return
                }

                onLog(L10n.trf("tunnel.log.hostKeyVerified", endpoint, fingerprint))
                validationCompletePromise.succeed(())
                return
            }

            guard Self.confirmNewKey(endpoint: endpoint, fingerprint: fingerprint) else {
                validationCompletePromise.fail(NativeSSHTunnelError.hostKeyRejected)
                return
            }

            store.setKey(key, for: endpoint)
            onLog(L10n.trf("tunnel.log.hostKeyTrusted", endpoint, fingerprint))
            validationCompletePromise.succeed(())
        }
    }

    private static func confirmNewKey(endpoint: String, fingerprint: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tr("hostKey.new.title")
        alert.informativeText = L10n.trf("hostKey.new.message", endpoint, fingerprint)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("hostKey.button.trust"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func confirmChangedKey(
        endpoint: String,
        previousFingerprint: String,
        fingerprint: String
    ) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.tr("hostKey.changed.title")
        alert.informativeText = L10n.trf(
            "hostKey.changed.message",
            endpoint,
            previousFingerprint,
            fingerprint
        )
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.tr("hostKey.button.replace"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func fingerprint(for openSSHKey: String) -> String {
        let parts = openSSHKey.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let keyData = Data(base64Encoded: String(parts[1])) else {
            return L10n.tr("hostKey.fingerprint.unavailable")
        }

        let digest = SHA256.hash(data: keyData)
        let encoded = Data(digest)
            .base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(encoded)"
    }
}

private final class SSHKnownHostsStore {
    static let shared = SSHKnownHostsStore()

    private let defaultsKey = "nativeSSHKnownHosts"

    func key(for endpoint: String) -> String? {
        dictionary()[endpoint]
    }

    func setKey(_ key: String, for endpoint: String) {
        var values = dictionary()
        values[endpoint] = key
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }

    private func dictionary() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }
}

struct SSHCommandResult {
    let exitStatus: Int
    let standardOutput: String
    let standardError: String
}

final class SSHCommandHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let command: String
    private var completion: EventLoopPromise<SSHCommandResult>?
    private var standardOutput = Data()
    private var standardError = Data()
    private var exitStatus: Int?

    init(command: String, completion: EventLoopPromise<SSHCommandResult>) {
        self.command = command
        self.completion = completion
    }

    func channelActive(context: ChannelHandlerContext) {
        let request = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        context.triggerUserOutboundEvent(request).whenFailure { [weak self] error in
            self?.fail(error, context: context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else {
            fail(NativeSSHTunnelError.invalidDockerResponse, context: context)
            return
        }

        let bytes = Data(buffer.readableBytesView)
        switch channelData.type {
        case .channel:
            standardOutput.append(bytes)
        case .stdErr:
            standardError.append(bytes)
        default:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let status as SSHChannelRequestEvent.ExitStatus:
            exitStatus = status.exitStatus
        case let signal as SSHChannelRequestEvent.ExitSignal:
            standardError.append(Data(signal.errorMessage.utf8))
        case _ as ChannelFailureEvent:
            fail(NativeSSHTunnelError.commandRejected, context: context)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error, context: context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        finish()
    }

    private func finish() {
        guard let completion else {
            return
        }
        self.completion = nil

        let result = SSHCommandResult(
            exitStatus: exitStatus ?? -1,
            standardOutput: String(decoding: standardOutput, as: UTF8.self),
            standardError: String(decoding: standardError, as: UTF8.self)
        )
        completion.succeed(result)
    }

    private func fail(_ error: Error, context: ChannelHandlerContext) {
        if let completion {
            self.completion = nil
            completion.fail(error)
        }
        context.close(promise: nil)
    }
}

final class SSHConnectionErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let onError: (Error) -> Void

    init(onError: @escaping (Error) -> Void) {
        self.onError = onError
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onError(error)
        context.close(promise: nil)
    }
}

final class SSHChannelDataWrapper: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .channel = channelData.type, case .byteBuffer(let buffer) = channelData.data else {
            context.fireErrorCaught(NativeSSHTunnelError.invalidChannelType)
            return
        }
        context.fireChannelRead(wrapInboundOut(buffer))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let channelData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.write(wrapOutboundOut(channelData), promise: promise)
    }
}

final class SSHGlueHandler {
    private var partner: SSHGlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    private init() {}

    static func matchedPair() -> (SSHGlueHandler, SSHGlueHandler) {
        let first = SSHGlueHandler()
        let second = SSHGlueHandler()
        first.partner = second
        second.partner = first
        return (first, second)
    }

    private func partnerWrite(_ data: NIOAny) {
        context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        context?.flush()
    }

    private func partnerCloseOutput() {
        context?.close(mode: .output, promise: nil)
    }

    private func partnerClose() {
        context?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        guard pendingRead else {
            return
        }
        pendingRead = false
        context?.read()
    }

    private var partnerIsWritable: Bool {
        context?.channel.isWritable ?? false
    }
}

extension SSHGlueHandler: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        partner?.partnerClose()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let channelEvent = event as? ChannelEvent, case .inputClosed = channelEvent {
            partner?.partnerCloseOutput()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        partner?.partnerClose()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner, partner.partnerIsWritable {
            context.read()
        } else {
            pendingRead = true
        }
    }
}
