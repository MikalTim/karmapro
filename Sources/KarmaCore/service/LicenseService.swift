// by cipher.org.uk
import Foundation

/// The Licensing window (`LicensingWindowController`): the license files of the
/// open project and what they allow for commercial use.
public enum LicenseService {
    /// The job result.
    public struct ReportDTO: Codable, Sendable {
        /// The text the window shows. Without an open project it is the window's "no project" message.
        public var report: String

        public init(report: String) {
            self.report = report
        }
    }

    /// `POST /api/licenses`: scans the open project's license files off the request thread and returns the job id.
    public static func report() -> String {
        KarmaJobCenter.shared.start(kind: "licenses") { _ in
            let root = KarmaWorkspace.shared.read { $0.root }
            return KarmaJSON.data(ReportDTO(report: reportText(root: root)))
        }
    }

    /// The window's text for `root` (`LicenseScanner.report`).
    static func reportText(root: URL?) -> String {
        LicenseScanner.report(root: root)
    }
}
