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

public func renderTemplate(_ template: String, values: [String: String]) -> String {
    var result = template
    for name in ["project", "tool", "detail"] {
        result = result.replacingOccurrences(of: "{\(name)}", with: values[name] ?? "")
    }
    result = result.replacingOccurrences(of: #"\{[A-Za-z_]+\}"#, with: "", options: .regularExpression)
    result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    result = result.replacingOccurrences(of: #" +([.,!?])"#, with: "$1", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
    return renderTemplate("{project}: {detail}", values: values)
        .replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)
}
