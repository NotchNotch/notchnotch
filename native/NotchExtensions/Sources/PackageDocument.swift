import Foundation
import NotchProtocol

/// Markdown files a package can carry for people: `README.md` is shown as the
/// extension's About page, `CHANGELOG.md` as its version history.
public enum PackageDocument: String, CaseIterable, Sendable {
    case readme = "README.md"
    case changelog = "CHANGELOG.md"

    public static let maximumBytes = 256 * 1024

    /// The document's text, or nil when the package has none or it cannot be read.
    public func load(from directory: URL) -> String? {
        let url = directory.appendingPathComponent(rawValue)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? .max) <= Self.maximumBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The installer's checks: an included document is a UTF-8 file of at most 256 KiB.
    static func validate(directory: URL) throws {
        for document in allCases {
            let url = directory.appendingPathComponent(document.rawValue)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard document.load(from: directory) != nil else {
                throw ProtocolError.invalid("\(document.rawValue) must be a UTF-8 text file of at most 256 KiB.")
            }
        }
    }
}

/// The block structure of the Markdown subset NotchNotch renders natively.
/// Inline formatting stays in the text and is rendered by the view.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [String])
    case quote(String)
    case code(String)
    case rule
}

public enum Markdown {
    /// Splits Markdown into blocks. Images become their alt text, and raw HTML
    /// is kept as plain text, so a document cannot load anything.
    public static func blocks(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var list: (ordered: Bool, items: [String])?
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(inline(paragraph.joined(separator: " ")))); paragraph = [] }
            if !quote.isEmpty { blocks.append(.quote(inline(quote.joined(separator: " ")))); quote = [] }
            if let current = list { blocks.append(.list(ordered: current.ordered, items: current.items.map(inline))); list = nil }
        }

        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))); code = nil }
                else { flush(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let heading = heading(line) { flush(); blocks.append(heading); continue }
            if line.range(of: "^([-*_])( ?\\1){2,}$", options: .regularExpression) != nil { flush(); blocks.append(.rule); continue }
            if line.hasPrefix(">") {
                if !paragraph.isEmpty || list != nil { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if let (ordered, item) = listItem(line) {
                if !paragraph.isEmpty || !quote.isEmpty || (list != nil && list?.ordered != ordered) { flush() }
                if list == nil { list = (ordered, []) }
                list?.items.append(item)
                continue
            }
            if raw.hasPrefix("  "), var current = list, !current.items.isEmpty {
                current.items[current.items.count - 1] += " " + line
                list = current
                continue
            }
            if list != nil || !quote.isEmpty { flush() }
            paragraph.append(line)
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+#+$", with: "", options: .regularExpression)
        return .heading(level: hashes, text: inline(text))
    }

    private static func listItem(_ line: String) -> (Bool, String)? {
        if let range = line.range(of: "^[-*+] +", options: .regularExpression) {
            return (false, String(line[range.upperBound...]))
        }
        if let range = line.range(of: "^[0-9]{1,9}[.)] +", options: .regularExpression) {
            return (true, String(line[range.upperBound...]))
        }
        return nil
    }

    /// Replaces images with their alt text; links and emphasis stay for the view.
    static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
    }
}
