// by cipher.org.uk
import Foundation

/// The JSON encoder and decoder every front end uses for the public service
/// layer, so that dates and key order are the same on every route.
///
/// Conventions shared by all data transfer objects in `service/`:
///  - files are identified by absolute `path` strings;
///  - text positions are UTF-16 `location`/`length` values (the engine's
///    `NSRange` units, which equal JavaScript string indices);
///  - lines are 1-based;
///  - enumerations are encoded as their raw string value.
public enum KarmaJSON {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Encodes a value with `encoder`. Encoding the types in `service/` cannot
    /// fail, so an empty JSON object stands in if it ever does.
    public static func data<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}
