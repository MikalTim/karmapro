// by cipher.org.uk
import Foundation
import KarmaCore
import Vapor

/// The web front end: a Vapor server that serves the Svelte single-page app
/// from `Web/` and the JSON API it talks to.
public enum KarmaWebServer {
    /// Starts the server and returns the process exit status once it stops:
    /// 0 after a clean stop, 1 when it could not start.
    public static func run(host: String, port: Int) async -> Int32 {
        let token: String? = KarmaAuthMiddleware.isLoopback(host) ? nil : KarmaAuthMiddleware.makeToken()
        let app: Application
        do {
            // Explicit arguments stop Vapor from parsing karma's own flags.
            app = try await Application.make(Environment(name: "production", arguments: ["karma"]))
        } catch {
            FileHandle.standardError.write(Data("karma: could not start the web server: \(error)\n".utf8))
            return 1
        }
        var status: Int32 = 0
        do {
            app.http.server.configuration.hostname = host
            app.http.server.configuration.port = port
            startKarmaServices()
            try configure(app, token: token)

            let shownHost = host.contains(":") ? "[\(host)]" : host
            let address = "http://\(shownHost):\(port)/"
            let suffix = token.map { "?token=\($0)" } ?? ""
            FileHandle.standardError.write(Data("Karma Pro web UI: \(address)\(suffix)\n".utf8))

            try await app.execute()
        } catch {
            FileHandle.standardError.write(Data("karma: could not start the web server: \(error)\n".utf8))
            status = 1
        }
        try? await app.asyncShutdown()
        return status
    }
}
