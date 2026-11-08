import AppKit
import SwiftUI

/// Console output from an extension runner, newest last.
struct ExtensionLogView: View {
    let entries: [ExtensionLogEntry]
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("No output yet. Messages from console.log appear here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.tertiary)
                                Text(entry.message)
                                    .foregroundStyle(entry.level == .error ? .red : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                }
                .frame(minHeight: 80, maxHeight: 220)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                .defaultScrollAnchor(.bottom)
            }
            HStack {
                Spacer()
                Button("Copy") {
                    let text = entries.map { "\($0.date.formatted(.iso8601)) \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }.disabled(entries.isEmpty)
                Button("Clear", action: onClear).disabled(entries.isEmpty)
            }
        }
    }
}
