// by cipher.org.uk
import Foundation

/// Installs the services a front end needs that depend on the operating system.
public enum KarmaPlatform {
    /// Chooses where forge access tokens are kept: the macOS Keychain where it
    /// exists, otherwise a private file (see `FilePRTokenStorage`).
    ///
    /// The AppKit app installs the Keychain itself at launch; `karma --serve`
    /// calls this.
    public static func installDefaultServices() {
        #if canImport(Security) && canImport(LocalAuthentication)
        PRStore.shared.tokenStorage = KeychainPRTokenStorage()
        #else
        PRStore.shared.tokenStorage = FilePRTokenStorage()
        #endif
    }
}
