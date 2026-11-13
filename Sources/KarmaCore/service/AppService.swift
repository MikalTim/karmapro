// by cipher.org.uk
import Foundation

/// What a front end needs to know about the running program.
public struct AppInfoDTO: Codable, Sendable {
    /// Release number from `Info.plist` ("unknown" when no resources were found).
    public var version: String
    /// "macos" or "linux".
    public var platform: String
    /// False when the bundled resources (prompts, models, images) were not found.
    public var resourcesFound: Bool
    /// True when the front end requires an access token (non-loopback host).
    public var tokenRequired: Bool
    /// Bugs with status "Open" or "In Progress" (the Dock badge number).
    public var openBugCount: Int

    public init(version: String, platform: String, resourcesFound: Bool, tokenRequired: Bool, openBugCount: Int) {
        self.version = version
        self.platform = platform
        self.resourcesFound = resourcesFound
        self.tokenRequired = tokenRequired
        self.openBugCount = openBugCount
    }
}

public enum AppService {
    public static func info(tokenRequired: Bool) -> AppInfoDTO {
        #if os(macOS)
        let platform = "macos"
        #else
        let platform = "linux"
        #endif
        BugStore.shared.reload()
        return AppInfoDTO(version: KarmaResources.shortVersion ?? "unknown",
                          platform: platform,
                          resourcesFound: KarmaResources.isAvailable,
                          tokenRequired: tokenRequired,
                          openBugCount: BugStore.shared.openBugCount)
    }
}
