import Foundation

public struct SpeechTemplates: Codable, Equatable, Sendable {
    public var lines: [SpeechKind: [String]]

    public init(lines: [SpeechKind: [String]]) {
        self.lines = lines
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: [String]].self)
        var lines: [SpeechKind: [String]] = [:]
        for (key, value) in raw {
            if let kind = SpeechKind(rawValue: key) {
                lines[kind] = value
            }
        }
        self.lines = lines
    }

    public func encode(to encoder: Encoder) throws {
        var raw: [String: [String]] = [:]
        for (kind, value) in lines {
            raw[kind.rawValue] = value
        }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

private let placeholderPattern = try? NSRegularExpression(pattern: #"\{([A-Za-z_]+)\}"#)
private let punctuationAfterGap: Set<Character> = [".", ",", "!", "?"]

public func renderTemplate(_ template: String, values: [String: String]) -> String {
    let source = template as NSString
    let matches = placeholderPattern?.matches(in: template, range: NSRange(location: 0, length: source.length)) ?? []

    var output = ""
    var endsWithLiteralSpace = false

    func appendLiteral(_ text: String) {
        var chunk = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if chunk.hasPrefix(" "), output.isEmpty || endsWithLiteralSpace {
            chunk.removeFirst()
        }
        guard !chunk.isEmpty else { return }
        output += chunk
        endsWithLiteralSpace = chunk.hasSuffix(" ")
    }

    var cursor = 0
    for match in matches {
        appendLiteral(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
        cursor = match.range.location + match.range.length

        let value = values[source.substring(with: match.range(at: 1))] ?? ""
        if value.isEmpty {
            if endsWithLiteralSpace, cursor < source.length,
               let next = source.substring(from: cursor).first, punctuationAfterGap.contains(next) {
                output.removeLast()
                endsWithLiteralSpace = false
            }
        } else {
            output += value
            endsWithLiteralSpace = false
        }
    }
    appendLiteral(source.substring(from: cursor))

    if endsWithLiteralSpace {
        output.removeLast()
    }
    return output
}

public func speechLine(
    for session: SessionRecord?,
    templates: SpeechTemplates,
    fallback: SpeechTemplates,
    pick: ([String]) -> String?
) -> String {
    let kind = session?.speechKind ?? .allClear
    let candidates = [templates.lines[kind], fallback.lines[kind]]
        .compactMap { $0 }
        .first { !$0.isEmpty }

    guard let session else {
        guard let candidates, let template = pick(candidates) else { return "All clear" }
        return renderTemplate(template, values: [:])
    }

    let values = [
        "project": session.projectName,
        "tool": session.toolName ?? "",
        "detail": session.detail ?? "",
    ]
    if let candidates, let template = pick(candidates) {
        return renderTemplate(template, values: values)
    }
    let detail = session.detail ?? ""
    return detail.isEmpty ? session.projectName : "\(session.projectName): \(detail)"
}
