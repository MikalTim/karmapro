// by cipher.org.uk
import Foundation

/// Errors the public service layer throws. Front ends map them to a response:
/// the web server turns `noProject` and `invalid` into HTTP 400, `notFound`
/// into 404 and `busy` into 409.
public enum KarmaServiceError: LocalizedError {
    /// A project folder must be open first.
    case noProject
    case notADirectory(String)
    case notFound(String)
    case invalid(String)
    case busy(String)

    public var errorDescription: String? {
        switch self {
        case .noProject:
            return "No Folder Open: choose a project folder first."
        case .notADirectory(let path):
            return "\"\(path)\" is not a folder."
        case .notFound(let what):
            return what
        case .invalid(let message):
            return message
        case .busy(let message):
            return message
        }
    }
}
