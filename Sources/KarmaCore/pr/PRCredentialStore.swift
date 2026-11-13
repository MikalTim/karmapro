// by cipher.org.uk
import Foundation
#if canImport(Security) && canImport(LocalAuthentication)
import LocalAuthentication
import Security

/// Token storage backed by the macOS Keychain.

enum PRCredentialStore {
    private static let service = "karmapro.pullrequests"

    /// The one Keychain item that holds every token.
    private static let itemAccount = "tokens"

    /// Where tokens were kept before the service was renamed, as one item per
    /// account. Read once, folded into the new item and then deleted, so
    /// renaming the key does not cost the user their saved tokens.
    private static let legacyService = "uk.cipher.karmapro.forge"

    /// Authorizes once per session and is then reused, so macOS prompts at most
    /// once for all of this feature's Keychain access.
    private static let authContext: LAContext = {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 600
        context.localizedReason = "Karma Pro is reading the pull request tokens you saved."
        return context
    }()

    /// All known tokens, or nil while they have not been read this session.
    private static var cache: [String: String]?

    /// Whether the cache can answer without touching the Keychain.
    private static var didLoad = false

    /// Set once a call has failed because this build cannot use the Data
    /// Protection keychain, so the older file-based keychain is used instead.
    private static var usesClassicKeychain = false

    /// What the UI may safely say about an account without reading anything.
    static func cachedState(identity: String) -> (isCached: Bool, token: String?) {
        guard let cache = cache else { return (false, nil) }
        return (true, cache[identity])
    }

    /// Drops everything held in memory.
    ///
    /// Called when monitoring is switched off so a later switch back on reads
    /// the Keychain once, freshly, rather than reusing a token that may have
    /// been rotated while monitoring was off.
    static func invalidateSessionCache() {
        cache = nil
        didLoad = false
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case malformedData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "Keychain error: \(message)"
            case .malformedData:
                return "Keychain error: stored token could not be read."
            }
        }
    }

    // MARK: - Reading

    /// The token for an identity, or nil when there is none.
    ///
    /// - Parameter prompt: when false the Keychain is not touched at all and
    ///   only the session cache is consulted, so merely running the app cannot
    ///   put a Keychain dialog in front of the user.
    static func token(identity: String, prompt: Bool = true) -> String? {
        if let cache = cache { return cache[identity] }
        guard prompt else { return nil }
        // One read answers for every account, so this prompts at most once for
        // the whole session however many accounts the user has.
        guard load() else {
            // The read did not complete, so whether this account has a token is
            // unknown. Reporting "no" would make a private repository look like
            // it had no credentials because of a cancelled unlock.
            return nil
        }
        if let token = cache?[identity] { return token }
        return migrateLegacyToken(identity: identity)
    }

    /// Moves one token out of the old keychain key and into the current one.
    ///
    /// Asked only about the account that came back empty. Reading the old key
    /// in bulk on every load made a save, a listing and a launch each raise a
    /// second authorization prompt for a service that is normally empty.
    private static func migrateLegacyToken(identity: String) -> String? {
        guard let data = readItem(service: legacyService, account: identity),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        var merged = cache ?? [:]
        merged[identity] = token
        // Written before the old entry is removed, so a failure here leaves the
        // token exactly where it was rather than losing it.
        guard (try? writeItem(merged)) != nil else { return nil }
        cache = merged
        deleteLegacyItem(identity: identity)
        PRLog.write("moved a pull request token for \(identity) from the old keychain key to \(service)")
        return token
    }

    static func hasToken(identity: String, prompt: Bool = true) -> Bool {
        token(identity: identity, prompt: prompt) != nil
    }

    /// Reads every token in one go, at most once per session.
    ///
    /// Returns false when the read could not be completed, so the caller treats
    /// the answer as unknown rather than as "no tokens exist".
    private static func load() -> Bool {
        if didLoad { return cache != nil }
        guard let data = readItem(service: service, account: itemAccount) else { return false }
        let found = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        // A token entered earlier in this session wins over whatever the
        // Keychain still holds for it.
        cache = cache.map { existing in existing.merging(found) { $1 } } ?? found
        didLoad = true
        return true
    }

    // MARK: - Writing

    /// Stores (or replaces) the read-only token for a host+user pair.
    /// - Parameter identity: stable per-account key, e.g. "github|alice".
    static func setToken(_ token: String, identity: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteToken(identity: identity)
            return
        }
        // The token is already in hand here, so this read is what saves every
        // later one: the item is read at most once per session from now on.
        guard load() else { throw KeychainError.malformedData }
        var tokens = cache ?? [:]
        tokens[identity] = trimmed
        cache = tokens
        try writeItem(tokens)
    }

    static func deleteToken(identity: String) throws {
        guard load() else { throw KeychainError.malformedData }
        var tokens = cache ?? [:]
        tokens.removeValue(forKey: identity)
        cache = tokens
        try writeItem(tokens)
    }

    /// Removes every token this app owns. Used when the user asks to forget all
    /// accounts; it never touches unrelated Keychain items.
    static func deleteAll() {
        deleteAll(in: service)
        deleteAll(in: legacyService)
        invalidateSessionCache()
    }

    /// Removes one entry left behind under the old service.
    private static func deleteLegacyItem(identity: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: identity
        ]
        if usesClassicKeychain {
            query[kSecUseDataProtectionKeychain as String] = false
        }
        SecItemDelete(query as CFDictionary)
    }

    private static func deleteAll(in service: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if usesClassicKeychain {
            query[kSecUseDataProtectionKeychain as String] = false
        }
        SecItemDelete(query as CFDictionary)
    }

    /// Reads one item's contents, preferring the Data Protection keychain.
    ///
    /// The Data Protection keychain is scoped to the app and carries no
    /// per-item access list. The file-based keychain records which binary may
    /// read each item, so a build signed differently from the one that saved the
    /// token is asked about separately from unlocking — a second dialog that no
    /// amount of app-side caching can remove. A build that is not entitled for
    /// the Data Protection keychain, such as an ad-hoc signed one, falls back.
    private static func readItem(service: String, account: String) -> Data? {
        func attempt(_ dataProtection: Bool) -> (OSStatus, Data?) {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: authContext
            ]
            if dataProtection {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        }

        if usesClassicKeychain {
            let result = attempt(false)
            return log(result.0, data: result.1)
        }
        let first = attempt(true)
        switch first.0 {
        case errSecSuccess:
            return log(first.0, data: first.1)
        case errSecItemNotFound:
            // A build that fell back writes to the file-based keychain, and a
            // lookup there reports "not found" rather than "no entitlement", so
            // not-found has to be checked in both places. Checking only the
            // first meant every token read back as absent after a relaunch,
            // while the item itself sat in the keychain the whole time.
            let second = attempt(false)
            if second.0 == errSecSuccess {
                usesClassicKeychain = true
                return log(second.0, data: second.1)
            }
            return log(first.0, data: first.1)
        case errSecMissingEntitlement, errSecNotAvailable, errSecParam:
            usesClassicKeychain = true
            let second = attempt(false)
            return log(second.0, data: second.1)
        default:
            return log(first.0, data: first.1)
        }
    }

    /// Turns a read outcome into a result, treating "nothing stored" as a
    /// successful empty answer and anything else as unknown.
    private static func log(_ status: OSStatus, data: Data?) -> Data? {
        switch status {
        case errSecSuccess:
            return data
        case errSecItemNotFound:
            return Data()
        case errSecUserCanceled, errSecAuthFailed:
            // Deliberately not remembered, so the next poll can ask again rather
            // than treating a cancelled unlock as "this account has no token".
            return nil
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            PRLog.write("keychain read of \(service) failed: \(message) (\(status))")
            return nil
        }
    }

    /// Writes the whole token set as one item.
    private static func writeItem(_ tokens: [String: String]) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        func attempt(_ dataProtection: Bool) -> OSStatus {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: itemAccount
            ]
            if dataProtection {
                query[kSecUseDataProtectionKeychain as String] = true
            }
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecSuccess { return status }
            guard status == errSecItemNotFound else { return status }
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil)
        }

        if usesClassicKeychain {
            let status = attempt(false)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
            return
        }
        let first = attempt(true)
        switch first {
        case errSecSuccess:
            return
        case errSecMissingEntitlement, errSecNotAvailable, errSecParam:
            usesClassicKeychain = true
            let second = attempt(false)
            guard second == errSecSuccess else { throw KeychainError.unexpectedStatus(second) }
        default:
            throw KeychainError.unexpectedStatus(first)
        }
    }
}

/// Installs the Keychain as `PRStore`'s token storage.
struct KeychainPRTokenStorage: PRTokenStorage {
    func token(identity: String, prompt: Bool) -> String? {
        PRCredentialStore.token(identity: identity, prompt: prompt)
    }

    func setToken(_ token: String, identity: String) throws {
        try PRCredentialStore.setToken(token, identity: identity)
    }

    func deleteToken(identity: String) throws {
        try PRCredentialStore.deleteToken(identity: identity)
    }

    func invalidateSessionCache() {
        PRCredentialStore.invalidateSessionCache()
    }
}
#endif
