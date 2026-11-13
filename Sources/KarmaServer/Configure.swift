// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// Where the built web front end (`Web/dist`) lives, first hit wins:
///  1. the `KARMA_WEB_ROOT` environment variable;
///  2. `karma-web` next to the executable (`build.sh` puts it there);
///  3. `Web/dist` in the repository this source file belongs to.
/// A candidate only counts when it contains `index.html`.
func resolveWebRoot(filePath: String = #filePath) -> URL? {
    var candidates: [URL] = []
    if let env = ProcessInfo.processInfo.environment["KARMA_WEB_ROOT"], !env.isEmpty {
        candidates.append(URL(fileURLWithPath: env, isDirectory: true))
    }
    if let executableDirectory = KarmaResources.executableDirectory {
        candidates.append(executableDirectory.appendingPathComponent("karma-web", isDirectory: true))
    }
    // <repo>/Sources/KarmaServer/Configure.swift → <repo>
    let repo = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    candidates.append(repo.appendingPathComponent("Web/dist", isDirectory: true))
    return candidates.first {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path)
    }
}

private let missingFrontEndPage = """
<h1>Karma Pro</h1><p>The web front end is not built. Run <code>npm ci &amp;&amp; npm run build</code> in <code>Web/</code>, or <code>./build.sh --no-appkit</code>.</p>
"""

/// Registers middleware and routes. `token` is nil in loopback mode.
func configure(_ app: Application, token: String?) throws {
    app.routes.defaultMaxBodySize = "256mb"

    if let webRoot = resolveWebRoot() {
        app.middleware.use(FileMiddleware(publicDirectory: webRoot.path + "/", defaultFile: "index.html"))
    } else {
        app.get { _ -> Response in
            var headers = HTTPHeaders()
            headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
            return Response(status: .serviceUnavailable, headers: headers, body: .init(string: missingFrontEndPage))
        }
    }

    let api = app.grouped("api")
        .grouped(KarmaErrorMiddleware())
        .grouped(KarmaAuthMiddleware(token: token))
    registerAppRoutes(api, tokenRequired: token != nil)
}
