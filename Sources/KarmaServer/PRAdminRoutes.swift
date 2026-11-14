// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The pull request accounts dialog, the watched repositories dialog and the review checkout cache. Every rule
/// (validation, status text, alert text) is applied by `PRAdminService`; these routes only decode and encode.
///
/// A repository id is `provider|apiBaseURL|slug`, so it contains `|` and `/`. `PUT /api/pr/repos/:id` takes it as a
/// percent-encoded path segment (`%7C`, `%2F`), which the router decodes. The routes that name a repository or an
/// account without changing it take the id in the `id` (or `identity`) query parameter instead, which avoids
/// encoding rules at the route level.
///
///  Accounts
///  - `GET /api/pr/accounts` -> `AccountsDTO`: the saved accounts (never a token) and the provider list.
///  - `GET /api/pr/accounts/provider?provider=&host=` -> `{provider}`: the provider the form shows for a typed
///    host (`resolveProvider`).
///  - `POST /api/pr/accounts` `{provider, host, username, token}` -> `StatusDTO`: "Save" (refusals are 400 with
///    the dialog's text).
///  - `POST /api/pr/accounts/test` `{identity}` -> `{jobId}`; the job's result is a `StatusDTO`.
///  - `GET /api/pr/accounts/remove-prompt?identity=` -> `ConfirmDTO`.
///  - `DELETE /api/pr/accounts?identity=` -> `StatusDTO`.
///
///  Watched repositories
///  - `GET /api/pr/repos` -> `RepositoriesDTO`.
///  - `POST /api/pr/repos/detect` `{url, isPrivate?, accountIdentity?}` -> `DetectionDTO`; never prompts.
///  - `POST /api/pr/repos` `{url, isPrivate?, localPath?, depth?, baseBranches?, accountIdentity?}` -> `RepoDTO`.
///    `baseBranches` is comma-separated and defaults to every branch.
///  - `PUT /api/pr/repos/:id` `RepoUpdateDTO` (`{isPrivate?, accountIdentity?, depth?, baseBranches?, localPath?,
///    enabled?}`) -> `RepoDTO`; `:id` is the percent-encoded repository id.
///  - `GET /api/pr/repos/remove-prompt?id=` -> `ConfirmDTO`.
///  - `DELETE /api/pr/repos?id=` -> `{ok}`.
///  - `POST /api/pr/repos/test` `{url, isPrivate?, accountIdentity?}` -> `{jobId}`; the job's result is a
///    `StatusDTO`. Refusals (no URL, no account) are 400 at once.
///
///  Review checkout cache
///  - `GET /api/pr/cache/prompt` -> `{prompt: ConfirmDTO | null}`; null when there is nothing to remove. Refuses
///    with 409 while a review is open.
///  - `DELETE /api/pr/cache` -> `StatusDTO`; 409 while a review is open.
func registerPRAdminRoutes(_ api: RoutesBuilder) {
    struct ProviderRequest: Decodable { let provider: String; let host: String }
    struct AccountSaveRequest: Decodable { let provider: String; let host: String; let username: String; let token: String }
    struct IdentityRequest: Decodable { let identity: String }
    struct DetectRequest: Decodable { let url: String; let isPrivate: Bool?; let accountIdentity: String? }
    struct AddRepoRequest: Decodable {
        let url: String
        let isPrivate: Bool?
        let localPath: String?
        let depth: String?
        let baseBranches: String?
        let accountIdentity: String?
    }
    struct TestRepoRequest: Decodable { let url: String; let isPrivate: Bool?; let accountIdentity: String? }
    struct ProviderBody: Encodable { let provider: String }
    /// `prompt` is written as `null` when there is nothing to clear; the synthesized encoder would omit it.
    struct CachePromptBody: Encodable {
        let prompt: PRAdminService.ConfirmDTO?

        enum CodingKeys: String, CodingKey { case prompt }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let prompt {
                try container.encode(prompt, forKey: .prompt)
            } else {
                try container.encodeNil(forKey: .prompt)
            }
        }
    }

    let admin = PRAdminService.shared

    api.get("pr", "accounts") { req async throws -> Response in
        jsonResponse(try await req.service { admin.accounts() })
    }
    api.get("pr", "accounts", "provider") { req async throws -> Response in
        let provider = try req.requiredQuery("provider")
        let host = try req.requiredQuery("host")
        return jsonResponse(ProviderBody(provider: admin.resolveProvider(provider: provider, host: host)))
    }
    api.post("pr", "accounts") { req async throws -> Response in
        let body = try req.jsonBody(AccountSaveRequest.self)
        return jsonResponse(try await req.service {
            try admin.saveAccount(provider: body.provider, host: body.host, username: body.username, token: body.token)
        })
    }
    api.post("pr", "accounts", "test") { req async throws -> Response in
        let identity = try req.jsonBody(IdentityRequest.self).identity
        return jobStartedResponse(try await req.service { try admin.testAccount(identity: identity) })
    }
    api.get("pr", "accounts", "remove-prompt") { req async throws -> Response in
        let identity = try req.requiredQuery("identity")
        return jsonResponse(try await req.service { try admin.removeAccountPrompt(identity: identity) })
    }
    api.delete("pr", "accounts") { req async throws -> Response in
        let identity = try req.requiredQuery("identity")
        return jsonResponse(try await req.service { try admin.removeAccount(identity: identity) })
    }

    api.get("pr", "repos") { req async throws -> Response in
        jsonResponse(try await req.service { admin.repositories() })
    }
    api.post("pr", "repos", "detect") { req async throws -> Response in
        let body = try req.jsonBody(DetectRequest.self)
        return jsonResponse(try await req.service {
            admin.detectRepository(url: body.url, isPrivate: body.isPrivate ?? false,
                                   accountIdentity: body.accountIdentity)
        })
    }
    api.post("pr", "repos") { req async throws -> Response in
        let body = try req.jsonBody(AddRepoRequest.self)
        return jsonResponse(try await req.service {
            try admin.addRepository(url: body.url, isPrivate: body.isPrivate ?? false, localPath: body.localPath,
                                    depth: body.depth, baseBranches: body.baseBranches ?? "",
                                    accountIdentity: body.accountIdentity)
        })
    }
    api.put("pr", "repos", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id"), !id.isEmpty else {
            throw Abort(.badRequest, reason: "The repository id is required.")
        }
        let change = try req.jsonBody(PRAdminService.RepoUpdateDTO.self)
        return jsonResponse(try await req.service { try admin.updateRepository(id: id, change: change) })
    }
    api.get("pr", "repos", "remove-prompt") { req async throws -> Response in
        let id = try req.requiredQuery("id")
        return jsonResponse(try await req.service { try admin.removeRepositoryPrompt(id: id) })
    }
    api.delete("pr", "repos") { req async throws -> Response in
        let id = try req.requiredQuery("id")
        try await req.service { try admin.removeRepository(id: id) }
        return okResponse()
    }
    api.post("pr", "repos", "test") { req async throws -> Response in
        let body = try req.jsonBody(TestRepoRequest.self)
        return jobStartedResponse(try await req.service {
            try admin.testRepository(url: body.url, isPrivate: body.isPrivate ?? false,
                                     accountIdentity: body.accountIdentity)
        })
    }

    api.get("pr", "cache", "prompt") { req async throws -> Response in
        let prompt = try await req.service { try admin.clearCachePrompt() }
        return jsonResponse(CachePromptBody(prompt: prompt))
    }
    api.delete("pr", "cache") { req async throws -> Response in
        jsonResponse(try await req.service { try admin.clearCache() })
    }
}
