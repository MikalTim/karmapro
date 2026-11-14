// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The pull request menu and the review inside the main window. Changes are announced with the `pr.changed`
/// event (the whole `PRStateDTO`), alerts with `pr.notify` and a review opening or closing with `pr.review`.
///
///  - `GET /api/pr` -> `PRStateDTO`: the menu's content, the watch list and the open review's banner.
///  - `GET /api/pr/about` -> `PRAboutDTO`.
///  - `POST /api/pr/monitoring` `{enabled}` -> `PRStateDTO` (400 with the alert text when there is no repository
///    to watch or git is missing).
///  - `POST /api/pr/check-now` -> `{ok}`.
///  - `PUT /api/pr/settings` `{depth?, notifyStyle?}` -> `PRStateDTO`; the values are the `value` of a choice.
///  - `POST /api/pr/items/dismiss` `{repoID, prID}` -> `{ok}`.
///  - `POST /api/pr/review` `{repoID, prID}` -> `{jobId}`: prepares the checkout and opens it as the project. The
///    job's progress is the "Preparing review" panel (`done` of 100, `stage`); cancelling it is the panel's Cancel.
///  - `GET /api/pr/review` -> `{review: PRReviewBannerDTO | null}`.
///  - `POST /api/pr/review/leave` `{removeCheckout?}` -> `{ok}`: "Close Review".
///  - `PUT /api/pr/review/show-all` `{on}` -> `PRStateDTO`: "Show All Files" (`on` must be true).
///  - `GET /api/pr/review/changes` -> `PRChangesDTO`: "Show Changes…".
///  - `GET /api/pr/review/report` -> `PRReportDTO`: "Report…".
///  - `GET /api/pr/review/scan-prompt` -> `PRScanPromptDTO`: the question before "Run a Scan".
///  - `POST /api/pr/review/scan` `{scope: "headOnly" | "both" | "none", ignoreAICache?}` -> `{jobId}`; the rows are
///    `GET /api/scan`.
///  - `POST /api/pr/review/rescan` -> `{jobId}`.
func registerPRRoutes(_ api: RoutesBuilder) {
    struct MonitoringRequest: Decodable { let enabled: Bool }
    struct SettingsRequest: Decodable {
        let depth: String?
        let notifyStyle: String?
    }
    struct DismissRequest: Decodable {
        let repoID: String
        let prID: Int
    }
    struct ReviewRequest: Decodable {
        let repoID: String
        let prID: Int
    }
    struct LeaveRequest: Decodable { let removeCheckout: Bool? }
    struct ShowAllRequest: Decodable { let on: Bool }
    struct ScanRequest: Decodable {
        let scope: String
        let ignoreAICache: Bool?
    }
    struct ReviewBody: Encodable { let review: PRReviewBannerDTO? }

    let pr = PRService.shared

    api.get("pr") { req async throws -> Response in
        jsonResponse(try await req.service { pr.state() })
    }
    api.get("pr", "about") { req async throws -> Response in
        jsonResponse(try await req.service { pr.about() })
    }
    api.post("pr", "monitoring") { req async throws -> Response in
        let request = try req.jsonBody(MonitoringRequest.self)
        return jsonResponse(try await req.service {
            try pr.setMonitoring(request.enabled)
            return pr.state()
        })
    }
    api.post("pr", "check-now") { req async throws -> Response in
        try await req.service { pr.checkNow() }
        return okResponse()
    }
    api.put("pr", "settings") { req async throws -> Response in
        let request = try req.jsonBody(SettingsRequest.self)
        return jsonResponse(try await req.service {
            if let depth = request.depth { try pr.setDepth(depth) }
            if let style = request.notifyStyle { try pr.setNotifyStyle(style) }
            return pr.state()
        })
    }
    api.post("pr", "items", "dismiss") { req async throws -> Response in
        let request = try req.jsonBody(DismissRequest.self)
        try await req.service { try pr.dismiss(repoID: request.repoID, prID: request.prID) }
        return okResponse()
    }

    api.post("pr", "review") { req async throws -> Response in
        let request = try req.jsonBody(ReviewRequest.self)
        return jobStartedResponse(try await req.service {
            try pr.startReview(repoID: request.repoID, prID: request.prID)
        })
    }
    api.get("pr", "review") { req async throws -> Response in
        jsonResponse(try await req.service { ReviewBody(review: pr.state().review) })
    }
    api.post("pr", "review", "leave") { req async throws -> Response in
        let request = req.body.data == nil ? LeaveRequest(removeCheckout: nil) : try req.jsonBody(LeaveRequest.self)
        try await req.service { pr.leaveReview(removeCheckout: request.removeCheckout ?? true) }
        return okResponse()
    }
    api.put("pr", "review", "show-all") { req async throws -> Response in
        let request = try req.jsonBody(ShowAllRequest.self)
        guard request.on else {
            throw Abort(.badRequest, reason: "\"on\" must be true: the tree cannot be pruned again without reopening the review.")
        }
        return jsonResponse(try await req.service {
            try pr.showAllFiles()
            return pr.state()
        })
    }
    api.get("pr", "review", "changes") { req async throws -> Response in
        jsonResponse(try await req.service { try pr.changes() })
    }
    api.get("pr", "review", "report") { req async throws -> Response in
        jsonResponse(try await req.service { try pr.report() })
    }
    api.get("pr", "review", "scan-prompt") { req async throws -> Response in
        jsonResponse(try await req.service { pr.scanPrompt() })
    }
    api.post("pr", "review", "scan") { req async throws -> Response in
        let request = try req.jsonBody(ScanRequest.self)
        return jobStartedResponse(try await req.service {
            try pr.scan(scope: request.scope, ignoreAICache: request.ignoreAICache ?? false)
        })
    }
    api.post("pr", "review", "rescan") { req async throws -> Response in
        jobStartedResponse(try await req.service { try SecurityScanService.shared.rescan() })
    }
}
