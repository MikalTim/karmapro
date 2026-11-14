// by cipher.org.uk
import Foundation

/// One folder or file in a listing.
public struct DirectoryEntryDTO: Codable, Sendable {
    public var name: String
    /// Absolute path.
    public var path: String
    public var isDirectory: Bool

    public init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}

/// The contents of one folder, for the browser's "choose a folder or file on this machine" dialogs
/// (the stand-in for `NSOpenPanel`).
public struct DirectoryListingDTO: Codable, Sendable {
    /// The folder that was listed, absolute and standardized.
    public var path: String
    /// The folder above it; nil at the root of the file system.
    public var parent: String?
    /// Folders first, then files, each group sorted by name ignoring case.
    public var entries: [DirectoryEntryDTO]

    public init(path: String, parent: String?, entries: [DirectoryEntryDTO]) {
        self.path = path
        self.parent = parent
        self.entries = entries
    }
}

public enum FileSystemService {
    /// Lists `path` (the user's home folder when nil or empty).
    ///
    /// Names that start with a dot are left out unless `includeHidden` is set, and files are only listed when
    /// `includeFiles` is set: a dialog that chooses a folder only needs the folders.
    public static func list(path: String?, includeFiles: Bool, includeHidden: Bool) throws -> DirectoryListingDTO {
        let requested = (path?.isEmpty == false) ? path! : NSHomeDirectory()
        let folder = URL(fileURLWithPath: requested).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw KarmaServiceError.notADirectory(requested)
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        } catch {
            throw KarmaServiceError.invalid("Could not read \"\(folder.path)\": \(error.localizedDescription)")
        }

        var entries: [DirectoryEntryDTO] = []
        for url in urls {
            let name = url.lastPathComponent
            if !includeHidden && name.hasPrefix(".") { continue }
            // A symbolic link to a folder is a folder to the user, so the link is followed.
            var childIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &childIsDirectory) else { continue }
            if !childIsDirectory.boolValue && !includeFiles { continue }
            entries.append(DirectoryEntryDTO(name: name, path: url.path, isDirectory: childIsDirectory.boolValue))
        }
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.compare(b.name, options: [.caseInsensitive, .numeric]) == .orderedAscending
        }

        let parent = folder.path == "/" ? nil : folder.deletingLastPathComponent().path
        return DirectoryListingDTO(path: folder.path, parent: parent, entries: entries)
    }
}
