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

    func password(for id: UUID) throws -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PasswordStoreError.keychain(status)
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw PasswordStoreError.keychain(errSecDecode)
        }
        return password
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
