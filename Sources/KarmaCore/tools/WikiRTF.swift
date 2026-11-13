// by cipher.org.uk
import Foundation

/// A wiki page body as plain data: paragraphs made of styled runs.
///
/// These are exactly the formats the wiki editor can produce: bold, italic,
/// underline, code (monospaced), heading (20 pt bold) and body (14 pt) text,
/// and links (`wiki://page/<name>` for other pages, or an http URL). Pages stay
/// RTF files on disk; `WikiRTF` converts between the two so the AppKit app and
/// the web front end read and write the same files.
public struct WikiDocument: Codable, Equatable {
    public var paragraphs: [WikiParagraph]

    public init(paragraphs: [WikiParagraph] = []) {
        self.paragraphs = paragraphs
    }

    /// A document of unformatted text; `\n` starts a new paragraph.
    public init(plain: String) {
        paragraphs = plain.isEmpty ? [] : plain.components(separatedBy: "\n").map { line in
            WikiParagraph(runs: line.isEmpty ? [] : [WikiRun(text: line)])
        }
    }

    /// The text without formatting, paragraphs joined by `\n`.
    public var plainText: String {
        paragraphs.map { $0.runs.map(\.text).joined() }.joined(separator: "\n")
    }
}

public struct WikiParagraph: Codable, Equatable {
    public var runs: [WikiRun]

    public init(runs: [WikiRun] = []) {
        self.runs = runs
    }
}

public struct WikiRun: Codable, Equatable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var code: Bool
    public var heading: Bool
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false,
                code: Bool = false, heading: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.code = code
        self.heading = heading
        self.link = link
    }

    private enum CodingKeys: String, CodingKey {
        case text, bold, italic, underline, code, heading, link
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        code = try c.decodeIfPresent(Bool.self, forKey: .code) ?? false
        heading = try c.decodeIfPresent(Bool.self, forKey: .heading) ?? false
        link = try c.decodeIfPresent(String.self, forKey: .link)
    }

    fileprivate func hasSameFormat(as other: WikiRun) -> Bool {
        bold == other.bold && italic == other.italic && underline == other.underline
            && code == other.code && heading == other.heading && link == other.link
    }
}

/// Reads and writes the RTF subset Karma Pro's wiki uses. `decode` accepts RTF
/// written by Cocoa (the AppKit app) or by `encode`; `encode` writes RTF that
/// Cocoa reads.
public enum WikiRTF {
    private static let bodyHalfPoints = 28      // 14 pt
    private static let headingHalfPoints = 40   // 20 pt
    /// Sizes from this value up (17 pt) count as headings when reading.
    private static let headingThreshold = 34

    // MARK: - Encoding

    public static func encode(_ document: WikiDocument) -> Data {
        var out = "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2580\n"
        out += "\\cocoatextscaling0\\cocoaplatform0{\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;\\f1\\fmodern\\fcharset0 Menlo-Regular;}\n"
        out += "{\\colortbl;\\red255\\green255\\blue255;}\n"
        out += "\\pard\\pardeftab720\\partightenfactor0\n"
        for (index, paragraph) in document.paragraphs.enumerated() {
            if index > 0 { out += "\\par\n" }
            for run in paragraph.runs where !run.text.isEmpty {
                out += encode(run)
            }
        }
        out += "}"
        return Data(out.utf8)
    }

    private static func encode(_ run: WikiRun) -> String {
        var format = run.code ? "\\f1" : "\\f0"
        format += "\\fs\(run.heading ? headingHalfPoints : bodyHalfPoints)"
        format += (run.bold || run.heading) ? "\\b" : "\\b0"
        format += run.italic ? "\\i" : "\\i0"
        format += run.underline ? "\\ul" : "\\ulnone"
        let body = "{\(format) \(escape(run.text))}"
        guard let link = run.link, !link.isEmpty else { return body }
        let target = escape(link.replacingOccurrences(of: "\"", with: "%22"))
        return "{\\field{\\*\\fldinst{HYPERLINK \"\(target)\"}}{\\fldrslt \(body)}}"
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            switch unit {
            case 0x5C: out += "\\\\"
            case 0x7B: out += "\\{"
            case 0x7D: out += "\\}"
            case 0x09: out += "\\tab "
            case 0x0A: out += "\\par "
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            case 0x00...0x1F: break
            default: out += "\\u\(Int16(bitPattern: unit))?"
            }
        }
        return out
    }

    // MARK: - Decoding

    public static func plainText(_ data: Data) -> String {
        decode(data).plainText
    }

    public static func decode(_ data: Data) -> WikiDocument {
        let bytes = [UInt8](data)
        let signature = Array("{\\rtf".utf8)
        guard bytes.count >= signature.count, Array(bytes.prefix(signature.count)) == signature else {
            return WikiDocument(plain: String(decoding: bytes, as: UTF8.self))
        }
        var reader = Reader(bytes: bytes)
        reader.run()
        return reader.document()
    }

    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var font = 0
        var halfPoints = 24
        var skipCount = 1
    }

    private enum Capture { case none, fontTable, fieldInstruction }

    private struct Group {
        var style = Style()
        var skip = false
        var capture = Capture.none
        var link: String?
        var isField = false
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0
        var stack: [Group] = [Group()]
        var fonts: [Int: String] = [:]
        var fontIndex = 0
        var fontName = ""
        var fieldInstruction = ""
        var fieldLink: String?
        var paragraphs: [WikiParagraph] = []
        var runs: [WikiRun] = []
        var pendingHighSurrogate: UInt16?

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        func document() -> WikiDocument {
            var all = paragraphs
            all.append(WikiParagraph(runs: runs))
            if all.count == 1 && all[0].runs.isEmpty { all = [] }
            return WikiDocument(paragraphs: all)
        }

        mutating func run() {
            // The outermost group is "{\rtf1 …}"; the Group already on the stack stands for it.
            if bytes.first == UInt8(ascii: "{") { position = 1 }
            while position < bytes.count {
                let byte = bytes[position]
                switch byte {
                case UInt8(ascii: "{"):
                    position += 1
                    let parent = stack[stack.count - 1]
                    var child = parent
                    child.isField = false
                    stack.append(child)
                case UInt8(ascii: "}"):
                    position += 1
                    closeGroup()
                case UInt8(ascii: "\\"):
                    position += 1
                    readControl()
                case 0x0A, 0x0D:
                    position += 1
                default:
                    readText()
                }
            }
        }

        private mutating func closeGroup() {
            guard stack.count > 1 else { return }
            let closed = stack.removeLast()
            if closed.capture == .fieldInstruction && stack[stack.count - 1].capture != .fieldInstruction {
                fieldLink = Self.url(fromInstruction: fieldInstruction)
                fieldInstruction = ""
            }
            if closed.isField { fieldLink = nil }
        }

        private static func url(fromInstruction instruction: String) -> String? {
            guard instruction.uppercased().contains("HYPERLINK"),
                  let open = instruction.firstIndex(of: "\"") else { return nil }
            let rest = instruction[instruction.index(after: open)...]
            guard let close = rest.firstIndex(of: "\"") else { return nil }
            let url = String(rest[..<close])
            return url.isEmpty ? nil : url
        }

        // MARK: Control words

        private mutating func readControl() {
            guard position < bytes.count else { return }
            let byte = bytes[position]
            switch byte {
            case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"):
                position += 1
                emit(String(UnicodeScalar(byte)))
            case UInt8(ascii: "'"):
                position += 1
                if let value = readHexByte() { emit(String(Self.windows1252(value))) }
            case UInt8(ascii: "*"):
                position += 1
                markIgnorableDestination()
            case 0x0A, 0x0D:
                position += 1
                endParagraph()
            case UInt8(ascii: "~"):
                position += 1
                emit("\u{00A0}")
            case UInt8(ascii: "_"):
                position += 1
                emit("-")
            case UInt8(ascii: "-"), UInt8(ascii: "|"), UInt8(ascii: ":"):
                position += 1
            default:
                if Self.isLetter(byte) { readControlWord() } else { position += 1 }
            }
        }

        private mutating func readControlWord() {
            let start = position
            while position < bytes.count, Self.isLetter(bytes[position]) { position += 1 }
            let word = String(decoding: bytes[start..<position], as: UTF8.self)
            var parameter: Int?
            let numberStart = position
            if position < bytes.count, bytes[position] == UInt8(ascii: "-") { position += 1 }
            let digitsStart = position
            while position < bytes.count, bytes[position] >= 0x30, bytes[position] <= 0x39 { position += 1 }
            if position > digitsStart {
                parameter = Int(String(decoding: bytes[numberStart..<position], as: UTF8.self))
            } else {
                position = numberStart
            }
            if position < bytes.count, bytes[position] == UInt8(ascii: " ") { position += 1 }
            apply(word: word, parameter: parameter)
        }

        private var ignorableNext = false

        private mutating func markIgnorableDestination() {
            ignorableNext = true
        }

        private mutating func apply(word: String, parameter: Int?) {
            let wasIgnorable = ignorableNext
            ignorableNext = false
            let top = stack.count - 1

            // Destinations that carry no page text.
            let skipped: Set<String> = [
                "colortbl", "expandedcolortbl", "stylesheet", "info", "header", "footer", "pict",
                "object", "themedata", "colorschememapping", "latentstyles", "listtable",
                "listoverridetable", "revtbl", "generator", "xmlnstbl", "fonttbl_skip",
            ]
            switch word {
            case "fonttbl":
                stack[top].capture = .fontTable
                return
            case "fldinst":
                stack[top].capture = .fieldInstruction
                stack[top].skip = false
                return
            case "field":
                stack[top].isField = true
                return
            case "fldrslt":
                stack[top].skip = false
                stack[top].link = fieldLink
                return
            default:
                break
            }
            if skipped.contains(word) || wasIgnorable {
                stack[top].skip = true
                return
            }
            if stack[top].skip { return }

            switch word {
            case "f":
                if stack[top].capture == .fontTable {
                    fontIndex = parameter ?? 0
                    fontName = ""
                } else {
                    stack[top].style.font = parameter ?? 0
                }
            case "fs": stack[top].style.halfPoints = parameter ?? 24
            case "b": stack[top].style.bold = (parameter ?? 1) != 0
            case "i": stack[top].style.italic = (parameter ?? 1) != 0
            case "ulnone": stack[top].style.underline = false
            case "ul", "uld", "uldb", "ulth", "ulw", "ulwave", "uldash", "uldashd", "uldashdd", "ulthd", "ulthdash":
                stack[top].style.underline = (parameter ?? 1) != 0
            case "plain":
                stack[top].style.bold = false
                stack[top].style.italic = false
                stack[top].style.underline = false
                stack[top].style.halfPoints = 24
                stack[top].style.font = 0
            case "uc": stack[top].style.skipCount = parameter ?? 1
            case "par", "line", "sect", "page": endParagraph()
            case "tab": emit("\t")
            case "emdash": emit("\u{2014}")
            case "endash": emit("\u{2013}")
            case "emspace", "enspace": emit(" ")
            case "bullet": emit("\u{2022}")
            case "lquote": emit("\u{2018}")
            case "rquote": emit("\u{2019}")
            case "ldblquote": emit("\u{201C}")
            case "rdblquote": emit("\u{201D}")
            case "u": readUnicode(parameter ?? 0)
            default: break
            }
        }

        private mutating func readUnicode(_ parameter: Int) {
            let unit = UInt16(truncatingIfNeeded: parameter < 0 ? parameter + 65536 : parameter)
            // Skip the ANSI fallback that follows (\uc gives how many).
            var remaining = stack[stack.count - 1].style.skipCount
            while remaining > 0, position < bytes.count {
                if bytes[position] == UInt8(ascii: "\\"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "'") {
                    position += 4
                } else if bytes[position] != UInt8(ascii: "{"), bytes[position] != UInt8(ascii: "}") {
                    position += 1
                } else {
                    break
                }
                remaining -= 1
            }
            if (0xD800...0xDBFF).contains(unit) {
                pendingHighSurrogate = unit
                return
            }
            if (0xDC00...0xDFFF).contains(unit), let high = pendingHighSurrogate {
                pendingHighSurrogate = nil
                let value = 0x10000 + ((UInt32(high) - 0xD800) << 10) + (UInt32(unit) - 0xDC00)
                emit(String(Unicode.Scalar(value) ?? "\u{FFFD}"))
                return
            }
            pendingHighSurrogate = nil
            emit(String(Unicode.Scalar(UInt32(unit)) ?? "\u{FFFD}"))
        }

        private mutating func readHexByte() -> UInt8? {
            guard position + 1 < bytes.count,
                  let high = Self.hexValue(bytes[position]),
                  let low = Self.hexValue(bytes[position + 1]) else { return nil }
            position += 2
            return UInt8(high * 16 + low)
        }

        // MARK: Text

        private mutating func readText() {
            let byte = bytes[position]
            if byte < 0x80 {
                position += 1
                emit(String(UnicodeScalar(byte)))
                return
            }
            // Raw bytes: UTF-8 when valid, otherwise Windows-1252.
            let length = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            if length > 1, position + length <= bytes.count,
               let text = String(bytes: bytes[position..<position + length], encoding: .utf8) {
                position += length
                emit(text)
            } else {
                position += 1
                emit(String(Self.windows1252(byte)))
            }
        }

        private mutating func emit(_ text: String) {
            let group = stack[stack.count - 1]
            switch group.capture {
            case .fieldInstruction:
                fieldInstruction += text
                return
            case .fontTable:
                if text == ";" {
                    fonts[fontIndex] = fontName.trimmingCharacters(in: .whitespaces)
                    fontName = ""
                } else if !group.skip {
                    fontName += text
                }
                return
            case .none:
                break
            }
            if group.skip { return }

            let name = fonts[group.style.font]?.lowercased() ?? ""
            let run = WikiRun(
                text: text,
                bold: group.style.bold || name.contains("bold"),
                italic: group.style.italic || name.contains("italic") || name.contains("oblique"),
                underline: group.style.underline,
                code: ["menlo", "courier", "mono", "monaco"].contains { name.contains($0) },
                heading: group.style.halfPoints >= WikiRTF.headingThreshold,
                link: group.link)
            if let last = runs.last, last.hasSameFormat(as: run) {
                runs[runs.count - 1].text += text
            } else {
                runs.append(run)
            }
        }

        private mutating func endParagraph() {
            if stack[stack.count - 1].skip || stack[stack.count - 1].capture != .none { return }
            paragraphs.append(WikiParagraph(runs: runs))
            runs = []
        }

        // MARK: Helpers

        private static func isLetter(_ byte: UInt8) -> Bool {
            (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A)
        }

        private static func hexValue(_ byte: UInt8) -> Int? {
            switch byte {
            case 0x30...0x39: return Int(byte) - 0x30
            case 0x41...0x46: return Int(byte) - 0x41 + 10
            case 0x61...0x66: return Int(byte) - 0x61 + 10
            default: return nil
            }
        }

        private static let windows1252High: [UInt32] = [
            0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
            0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
            0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
            0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
        ]

        static func windows1252(_ byte: UInt8) -> Character {
            if byte >= 0x80 && byte <= 0x9F {
                return Character(Unicode.Scalar(windows1252High[Int(byte) - 0x80]) ?? "\u{FFFD}")
            }
            return Character(Unicode.Scalar(byte))
        }
    }
}
