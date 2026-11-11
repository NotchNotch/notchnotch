import SwiftUI
import UniformTypeIdentifiers
import NotchCore

/// The report the user is about to share, shown in full before it's saved.
struct ProblemReportSheet: View {
    let text: String
    let saved: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Problem Report").font(.title2).bold()
                Text("Review it before you share it. NotchNotch doesn’t send it anywhere: save it, then attach it to an issue on GitHub.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
            Divider()
            ScrollView {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(height: 340)
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityLabel("Report text")
            Divider()
            HStack(spacing: 12) {
                Link("Open GitHub Issues", destination: URL(string: "https://github.com/NotchNotch/notchnotch/issues")!)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save…", action: save).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 640)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "NotchNotch Problem Report \(Date.now.formatted(.iso8601.year().month().day())).txt"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            saved(url)
            dismiss()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// Settings › General › Problems.
struct ProblemsSection: View {
    @Bindable var coordinator: ManagementCoordinator
    @State private var report: ReportText?
    @State private var preparing = false

    private struct ReportText: Identifiable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        @Bindable var problems = coordinator.model.problems
        Section {
            if let crash = problems.unseenCrash {
                Label {
                    Text("\(crash.process) quit unexpectedly \(crash.date.formatted(.relative(presentation: .named))).")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
            }
            Toggle(isOn: $problems.remembers) {
                Text("Remember problems between launches")
                Text("Keeps up to two weeks of errors and notices crashes, in a file on this Mac.")
            }.toggleStyle(.switch)
            LabeledContent {
                HStack {
                    if !problems.problems.isEmpty { Button("Clear", action: problems.clear) }
                    Button("Export…", action: prepare).disabled(preparing)
                }
            } label: {
                Text("Problem report")
                Text(summary(problems.problems.count))
            }
        } header: {
            Text("Problems")
        } footer: {
            Text("A report lists versions, extensions, errors and recent crashes, with your home folder and name removed. NotchNotch never sends it: you review it, save it and choose whether to share it.")
        }
        .sheet(item: $report) { item in
            ProblemReportSheet(text: item.text) { url in
                problems.markCrashSeen()
                coordinator.notify("Saved \(url.lastPathComponent).")
            }
        }
    }

    private func summary(_ count: Int) -> String {
        switch count {
        case 0: "No problems recorded"
        case 1: "1 problem recorded"
        default: "\(count) problems recorded"
        }
    }

    private func prepare() {
        preparing = true
        Task {
            let text = await coordinator.model.problemReport()
            preparing = false
            report = ReportText(text: text)
        }
    }
}
