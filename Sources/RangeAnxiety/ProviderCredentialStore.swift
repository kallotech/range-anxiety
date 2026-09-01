import Foundation
import LocalAuthentication
import Security

struct ProviderCredential: Codable, Equatable {
    let key: String
    let auxiliary: String?
}

enum CredentialStoreError: LocalizedError {
    case applicationSupportUnavailable
    case invalidData
    case keychain(OSStatus)
    case keychainAccessChanged
    case migrationFailed(String)
    case fileOperation(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Application Support is unavailable on this Mac."
        case .invalidData:
            return "The saved provider credential could not be read."
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Could not update macOS Keychain: \(detail) (\(status))."
        case .keychainAccessChanged:
            return "Keychain access changed after an unsigned rebuild. Reconnect this provider in Settings."
        case .migrationFailed(let message):
            return "The credential was left in its existing protected file because Keychain migration could not be verified: \(message)"
        case .fileOperation(let message):
            return "Could not remove the previous local credential file: \(message)"
        }
    }
}

struct ProviderCredentialStore {
    private static let service = "com.kallotech.rangeanxiety.provider-credential"

    private static var legacyDirectoryURL: URL {
        get throws {
            guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw CredentialStoreError.applicationSupportUnavailable
            }
            return base.appendingPathComponent("Codex Quota", isDirectory: true)
        }
    }

    private static func legacyCredentialURL(for provider: ProviderID) throws -> URL {
        try legacyDirectoryURL.appendingPathComponent("\(provider.rawValue)-credential.json", isDirectory: false)
    }

    private static func query(for provider: ProviderID, allowAuthenticationUI: Bool) -> [String: Any] {
        var lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        if !allowAuthenticationUI {
            let context = LAContext()
            context.interactionNotAllowed = true
            lookup[kSecUseAuthenticationContext as String] = context
        }
        return lookup
    }

    static func read(_ provider: ProviderID) throws -> ProviderCredential? {
        do {
            if let credential = try readKeychain(provider, allowAuthenticationUI: false) {
                return credential
            }
        } catch CredentialStoreError.keychainAccessChanged {
            throw CredentialStoreError.keychainAccessChanged
        }

        return try migrateLegacyCredentialIfNeeded(for: provider)
    }

    static func save(_ credential: ProviderCredential, for provider: ProviderID) throws {
        try saveKeychain(credential, for: provider, allowAuthenticationUI: true)
    }

    static func authorize(_ provider: ProviderID) throws -> ProviderCredential? {
        try readKeychain(provider, allowAuthenticationUI: true)
    }

    static func remove(_ provider: ProviderID) throws {
        let status = SecItemDelete(query(for: provider, allowAuthenticationUI: true) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mappedKeychainError(status)
        }
        try removeLegacyFiles(for: provider)
    }

    private static func readKeychain(
        _ provider: ProviderID,
        allowAuthenticationUI: Bool
    ) throws -> ProviderCredential? {
        var lookup = query(for: provider, allowAuthenticationUI: allowAuthenticationUI)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw mappedKeychainError(status) }
        guard let data = result as? Data,
              let credential = try? JSONDecoder().decode(ProviderCredential.self, from: data) else {
            throw CredentialStoreError.invalidData
        }
        return credential
    }

    private static func saveKeychain(
        _ credential: ProviderCredential,
        for provider: ProviderID,
        allowAuthenticationUI: Bool
    ) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credential)
        } catch {
            throw CredentialStoreError.invalidData
        }

        let lookup = query(for: provider, allowAuthenticationUI: allowAuthenticationUI)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: "RangeAnxiety – \(provider.displayName) credential"
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw mappedKeychainError(updateStatus) }

        var add = lookup
        add.removeValue(forKey: kSecUseAuthenticationContext as String)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "RangeAnxiety – \(provider.displayName) credential"
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw mappedKeychainError(addStatus) }
    }

    private static func migrateLegacyCredentialIfNeeded(for provider: ProviderID) throws -> ProviderCredential? {
        guard let legacy = try readLegacyCredential(for: provider) else { return nil }
        do {
            try saveKeychain(legacy, for: provider, allowAuthenticationUI: false)
            guard try readKeychain(provider, allowAuthenticationUI: false) == legacy else {
                throw CredentialStoreError.invalidData
            }
            try removeLegacyFiles(for: provider)
            return legacy
        } catch let error as CredentialStoreError {
            throw CredentialStoreError.migrationFailed(error.localizedDescription)
        } catch {
            throw CredentialStoreError.migrationFailed(error.localizedDescription)
        }
    }

    private static func readLegacyCredential(for provider: ProviderID) throws -> ProviderCredential? {
        let jsonURL = try legacyCredentialURL(for: provider)
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            do {
                return try JSONDecoder().decode(ProviderCredential.self, from: Data(contentsOf: jsonURL))
            } catch {
                throw CredentialStoreError.invalidData
            }
        }

        guard provider == .openRouter else { return nil }
        let rawURL = try legacyDirectoryURL.appendingPathComponent("openrouter-management-key", isDirectory: false)
        guard FileManager.default.fileExists(atPath: rawURL.path) else { return nil }
        do {
            let value = try String(contentsOf: rawURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CredentialStoreError.invalidData }
            return ProviderCredential(key: value, auxiliary: nil)
        } catch let error as CredentialStoreError {
            throw error
        } catch {
            throw CredentialStoreError.fileOperation(error.localizedDescription)
        }
    }

    private static func removeLegacyFiles(for provider: ProviderID) throws {
        let fileManager = FileManager.default
        var urls = [try legacyCredentialURL(for: provider)]
        if provider == .openRouter {
            urls.append(try legacyDirectoryURL.appendingPathComponent("openrouter-management-key", isDirectory: false))
        }
        do {
            for url in urls where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw CredentialStoreError.fileOperation(error.localizedDescription)
        }
    }

    private static func mappedKeychainError(_ status: OSStatus) -> CredentialStoreError {
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            return .keychainAccessChanged
        }
        return .keychain(status)
    }
}
