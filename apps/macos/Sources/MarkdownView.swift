import SwiftUI
import NotchExtensions

/// Renders an extension's README or CHANGELOG with native text styles.
/// Links open in the browser only when they are `https`; nothing else in the
/// document can load or open anything.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    init(_ source: String, droppingTitle: Bool = true) {
        var blocks = Markdown.blocks(source)
        // The page already shows the extension's name above its documents.
        if droppingTitle, case .heading(1, _) = blocks.first { blocks.removeFirst() }
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in view(for: block) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "https" else { return .discarded }
            return .systemAction(url)
        })
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text)).font(level <= 1 ? .title2 : level == 2 ? .headline : .subheadline).bold()
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•").foregroundStyle(.secondary).monospacedDigit()
                        Text(Self.inline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            Text(Self.inline(text)).foregroundStyle(.secondary).padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        case .code(let text):
            Text(text).font(.callout.monospaced()).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }

    /// Emphasis, code spans and links; anything Foundation cannot parse stays plain.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
