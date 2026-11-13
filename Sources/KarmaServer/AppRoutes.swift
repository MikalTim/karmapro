// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// Routes about the program itself: `GET /api/app/info`.
func registerAppRoutes(_ api: RoutesBuilder, tokenRequired: Bool) {
    api.get("app", "info") { req async throws -> Response in
        let info = try await req.application.threadPool.runIfActive(eventLoop: req.eventLoop) {
            AppService.info(tokenRequired: tokenRequired)
        }.get()
        return jsonResponse(info)
    }
}
