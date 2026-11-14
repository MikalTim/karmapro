// by cipher.org.uk
import Vapor

/// Registers the feature routes, one `registerXRoutes` function per service group (see the route files).
func registerFeatureRoutes(_ api: RoutesBuilder) {
    registerProjectRoutes(api)
    registerScanRoutes(api)
    registerPRRoutes(api)
    registerPRAdminRoutes(api)
    registerFileRoutes(api)
    registerToolRoutes(api)
    registerGraphRoutes(api)
    registerBugRoutes(api)
    registerWikiRoutes(api)
    registerAIRoutes(api)
    registerMLRoutes(api)
    registerSettingsRoutes(api)
}
