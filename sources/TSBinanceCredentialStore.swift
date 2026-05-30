import Foundation
import Security

enum TSBinanceCredentialState {
    case configured(apiKey: String, secret: String)
    case missing
    case temporarilyUnavailable(NSError)
    case failed(NSError)
}

private enum TSBinanceCredentialValueResult {
    case success(String)
    case notFound
    case temporarilyUnavailable(NSError)
    case failure(NSError)
}

@objcMembers
final class TSBinanceCredentialStore: NSObject {
    private static let service = "com.inighty.binancehud.binance"
    private static let apiKeyAccount = "apiKey"
    private static let secretAccount = "secret"
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private static let sharedInstance = TSBinanceCredentialStore()

    @objc(sharedStore)
    class func sharedStore() -> TSBinanceCredentialStore {
        sharedInstance
    }

    func hasCredentials() -> Bool {
        guard
            let apiKey = currentAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty,
            let secret = currentSecret()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !secret.isEmpty
        else {
            return false
        }

        return true
    }

    func currentAPIKey() -> String? {
        loadValue(forAccount: Self.apiKeyAccount)
    }

    func currentSecret() -> String? {
        loadValue(forAccount: Self.secretAccount)
    }

    @nonobjc
    func credentialState() -> TSBinanceCredentialState {
        let apiKeyResult = loadValueResult(forAccount: Self.apiKeyAccount)
        let secretResult = loadValueResult(forAccount: Self.secretAccount)

        switch (apiKeyResult, secretResult) {
        case (.success(let apiKey), .success(let secret)):
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAPIKey.isEmpty, !trimmedSecret.isEmpty else {
                return .missing
            }
            migrateAccessibilityIfNeeded(apiKey: trimmedAPIKey, secret: trimmedSecret)
            return .configured(apiKey: trimmedAPIKey, secret: trimmedSecret)
        case (.notFound, _), (_, .notFound):
            return .missing
        case (.temporarilyUnavailable(let error), _), (_, .temporarilyUnavailable(let error)):
            return .temporarilyUnavailable(error)
        case (.failure(let error), _), (_, .failure(let error)):
            return .failed(error)
        }
    }

    @objc(saveAPIKey:secret:error:)
    func save(apiKey: String, secret: String) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAPIKey.isEmpty else {
            throw NSError(
                domain: "TSBinanceCredentialStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("API Key cannot be empty.", comment: "TSBinanceCredentialStore")]
            )
        }

        guard !trimmedSecret.isEmpty else {
            throw NSError(
                domain: "TSBinanceCredentialStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("API Secret cannot be empty.", comment: "TSBinanceCredentialStore")]
            )
        }

        try saveValue(trimmedAPIKey, forAccount: Self.apiKeyAccount)
        try saveValue(trimmedSecret, forAccount: Self.secretAccount)
    }

    @objc(clearCredentials:)
    func clearCredentials(_ error: NSErrorPointer) -> Bool {
        do {
            try deleteValue(forAccount: Self.apiKeyAccount)
            try deleteValue(forAccount: Self.secretAccount)
            return true
        } catch let nsError as NSError {
            error?.pointee = nsError
            return false
        }
    }

    private func loadValue(forAccount account: String) -> String? {
        guard case .success(let value) = loadValueResult(forAccount: account) else {
            return nil
        }

        return value
    }

    private func loadValueResult(forAccount account: String) -> TSBinanceCredentialValueResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return .notFound
            }
            let error = keychainError(status: status)
            if Self.isTemporarilyUnavailable(status) {
                return .temporarilyUnavailable(error)
            }
            return .failure(error)
        }

        guard
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return .failure(NSError(
                domain: "TSBinanceCredentialStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to decode saved Binance credential."]
            ))
        }

        return .success(value)
    }

    private func saveValue(_ value: String, forAccount account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw keychainError(status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = Self.accessibility
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(status: addStatus)
        }
    }

    private func migrateAccessibilityIfNeeded(apiKey: String, secret: String) {
        try? saveValue(apiKey, forAccount: Self.apiKeyAccount)
        try? saveValue(secret, forAccount: Self.secretAccount)
    }

    private func deleteValue(forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status: status)
        }
    }

    private func keychainError(status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func isTemporarilyUnavailable(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecNotAvailable
    }
}
