import Foundation
import Security

enum PasswordStoreError: Error {
    case keychain(OSStatus)
}

final class PasswordStore {
    static let shared = PasswordStore()

    private let account = NSUserName()
    private let servicePrefix = "ar.tecnologica.dockerbridge.connection"

    func save(_ password: String, for id: UUID) throws {
        let data = Data(password.utf8)
        let query = baseQuery(for: id)
        let attributes = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status != errSecItemNotFound {
            throw PasswordStoreError.keychain(status)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PasswordStoreError.keychain(addStatus)
        }
    }

    func delete(for id: UUID) {
        SecItemDelete(baseQuery(for: id) as CFDictionary)
    }

    func hasPassword(for id: UUID) -> Bool {
        let query = baseQuery(for: id)
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func serviceName(for id: UUID) -> String {
        "\(servicePrefix).\(id.uuidString)"
    }

    func accountName() -> String {
        account
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: id),
            kSecAttrAccount as String: account
        ]
    }
}

enum AskpassHelper {
    static func ensureInstalled() throws -> URL {
        let url = AppPaths.helperDirectoryURL.appendingPathComponent("ssh-askpass.sh")
        try FileManager.default.createDirectory(at: AppPaths.helperDirectoryURL, withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        if [ -z "${DOCKER_BRIDGE_KEYCHAIN_SERVICE:-}" ]; then
          exit 1
        fi
        exec /usr/bin/security find-generic-password -s "$DOCKER_BRIDGE_KEYCHAIN_SERVICE" -a "${DOCKER_BRIDGE_KEYCHAIN_ACCOUNT:-$USER}" -w
        """

        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
