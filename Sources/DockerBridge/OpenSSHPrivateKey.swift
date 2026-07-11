import Crypto
import Foundation
import NIOSSH

enum OpenSSHPrivateKeyError: LocalizedError {
    case invalidEnvelope
    case invalidPayload
    case encryptedKeyUnsupported
    case unsupportedKeyType(String)

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return L10n.tr("tunnel.error.privateKeyEnvelope")
        case .invalidPayload:
            return L10n.tr("tunnel.error.privateKeyPayload")
        case .encryptedKeyUnsupported:
            return L10n.tr("tunnel.error.encryptedPrivateKey")
        case .unsupportedKeyType(let type):
            return L10n.trf("tunnel.error.privateKeyType", type)
        }
    }
}

enum OpenSSHPrivateKeyLoader {
    static func loadDefaultKey() throws -> NIOSSHPrivateKey? {
        let keyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("id_ed25519")

        guard FileManager.default.isReadableFile(atPath: keyURL.path) else {
            return nil
        }

        return try loadKey(at: keyURL)
    }

    static func loadKey(at url: URL) throws -> NIOSSHPrivateKey {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)

        guard
            lines.first == "-----BEGIN OPENSSH PRIVATE KEY-----",
            lines.last == "-----END OPENSSH PRIVATE KEY-----",
            lines.count >= 3
        else {
            throw OpenSSHPrivateKeyError.invalidEnvelope
        }

        let encoded = lines.dropFirst().dropLast().joined()
        guard let payload = Data(base64Encoded: encoded) else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        return try decode(payload)
    }

    private static func decode(_ payload: Data) throws -> NIOSSHPrivateKey {
        let magic = Data("openssh-key-v1\0".utf8)
        guard payload.starts(with: magic) else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        var envelope = SSHBinaryReader(data: Data(payload.dropFirst(magic.count)))
        let cipherName = try envelope.readStringValue()
        let kdfName = try envelope.readStringValue()
        _ = try envelope.readString()

        guard cipherName == "none", kdfName == "none" else {
            throw OpenSSHPrivateKeyError.encryptedKeyUnsupported
        }

        guard try envelope.readUInt32() == 1 else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        _ = try envelope.readString()
        let privateBlock = try envelope.readString()
        var keyReader = SSHBinaryReader(data: privateBlock)

        let firstCheck = try keyReader.readUInt32()
        let secondCheck = try keyReader.readUInt32()
        guard firstCheck == secondCheck else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        let keyType = try keyReader.readStringValue()
        guard keyType == "ssh-ed25519" else {
            throw OpenSSHPrivateKeyError.unsupportedKeyType(keyType)
        }

        let publicBytes = try keyReader.readString()
        let privateBytes = try keyReader.readString()
        _ = try keyReader.readString()

        guard publicBytes.count == 32, privateBytes.count == 64 else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        let seed = Data(privateBytes.prefix(32))
        let embeddedPublicBytes = Data(privateBytes.suffix(32))
        guard embeddedPublicBytes == publicBytes else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        guard key.publicKey.rawRepresentation == publicBytes else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        return NIOSSHPrivateKey(ed25519Key: key)
    }
}

private struct SSHBinaryReader {
    let data: Data
    private(set) var offset = 0

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try read(count: 4)
        return bytes.reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
    }

    mutating func readString() throws -> Data {
        let length = try readUInt32()
        return Data(try read(count: Int(length)))
    }

    mutating func readStringValue() throws -> String {
        let bytes = try readString()
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }
        return value
    }

    private mutating func read(count: Int) throws -> Data.SubSequence {
        guard count >= 0, offset <= data.count - count else {
            throw OpenSSHPrivateKeyError.invalidPayload
        }

        defer { offset += count }
        return data[offset..<(offset + count)]
    }
}
