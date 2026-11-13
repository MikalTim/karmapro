import Foundation

extension SimParameterSeed {

    /// Interprets the text typed into a parameter's value cell. Buffers keep the
    /// text (without one pair of surrounding quotes) at the seed's capacity;
    /// everything else is read as bool, int, double, quoted string or bare string.
    func parse(_ text: String) -> SimDebugValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isBuffer {
            var value = trimmed
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return .buffer(value, capacity: capacity)
        }
        if let b = Bool(trimmed) { return .bool(b) }
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }
        if let i = Int(trimmed) { return .int(i) }
        if trimmed.contains("."), let d = Double(trimmed) { return .double(d) }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        return .string(trimmed)
    }
}
