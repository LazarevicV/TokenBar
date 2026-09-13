import Foundation
import Security

/// Read-only access to a generic-password Keychain item.
public enum KeychainReader {
    public struct ReadError: Error, Equatable, Sendable {
        public let status: OSStatus
    }

    public static func read(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ReadError(status: status) }
        guard let data = result as? Data else { throw ReadError(status: errSecDecode) }
        return data
    }
}
