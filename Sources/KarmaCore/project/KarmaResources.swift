// by cipher.org.uk
import Foundation

/// Locates the data files Karma Pro ships with (prompt templates, bundled
/// Bayesian models, `Info.plist`, help content, images).
///
/// The AppKit app runs from an app bundle, so it leaves `directory` nil and
/// every lookup goes to `Bundle.main`. The headless and web front ends are plain
/// executables with no bundle; they point `directory` at a folder that has the
/// same layout as the bundle's `Resources` directory (the repository's
/// `Resources_src`, or the `karma-resources` folder `build.sh` creates next to
/// the binary).
public enum KarmaResources {
    /// Folder holding the resources when not running from an app bundle.
    /// nil means "use `Bundle.main`".
    public static var directory: URL?

    /// Resolves a resource file. With `directory` set this is
    /// `directory/[subdirectory/]name.ext` when that file exists.
    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        guard let directory else {
            return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
        }
        var folder = directory
        if let subdirectory, !subdirectory.isEmpty {
            folder = folder.appendingPathComponent(subdirectory, isDirectory: true)
        }
        let fileName = (ext?.isEmpty == false) ? "\(name).\(ext!)" : name
        let file = folder.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The release number (`CFBundleShortVersionString`), or nil when it is not
    /// known. Read from `Info.plist` inside `directory` when that is set.
    static var shortVersion: String? {
        guard let directory else {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }
        let plistURL = directory.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    /// True when at least one lookup can succeed: a resource folder was set, or
    /// the process runs from an app bundle that has an `Info.plist`.
    public static var isAvailable: Bool {
        if let directory {
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent("Info.plist").path)
        }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") != nil
    }

    /// Absolute path of a bundled file, for front ends that serve it (the web
    /// server sends the splash and help images). nil when it is not present.
    public static func path(of fileName: String) -> String? {
        let ns = fileName as NSString
        let ext = ns.pathExtension
        return url(forResource: ns.deletingPathExtension, withExtension: ext.isEmpty ? nil : ext)?.path
    }
}

extension KarmaResources {
    /// The folder containing the running executable, with symbolic links
    /// resolved. Front ends use it to find `karma-resources` and `karma-web`
    /// next to the binary.
    public static var executableDirectory: URL? {
        #if os(Linux)
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") {
            return URL(fileURLWithPath: target).deletingLastPathComponent()
        }
        #endif
        if let url = Bundle.main.executableURL {
            return url.resolvingSymlinksInPath().deletingLastPathComponent()
        }
        guard let first = CommandLine.arguments.first, first.contains("/") else { return nil }
        return URL(fileURLWithPath: first).resolvingSymlinksInPath().deletingLastPathComponent()
    }
}
