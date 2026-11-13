import SwiftUI
import AppKit
import NotchCore
import NotchRenderer

/// The notch after files were handed to Open With: the apps that open them,
/// at Home's tile size, the default first and a shade brighter. Never scrolls: up to seven apps and
/// Other…, which picks any app.
struct OpenWithView: View {
    let choice: AppModel.AppChoice
    let width: CGFloat
    let onChoose: (URL?) -> Void
    @State private var hovered: URL??
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maximumApps = 7
    private var shown: [URL] { Array(choice.apps.prefix(Self.maximumApps)) }
    private var columns: Int { min(4, shown.count + 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(NotchTheme.Ink.secondary)
                .lineLimit(1).truncationMode(.middle)
                .padding(.leading, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HomeLayout.spacing), count: columns),
                      spacing: HomeLayout.spacing) {
                ForEach(shown, id: \.self) { app in
                    tile(app: app)
                }
                tile(app: nil)
            }
        }
        .frame(width: width)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: hovered)
    }

    /// "Open Report.pdf with", "Open 3 files with".
    private var title: String {
        choice.urls.count == 1 ? "Open \(choice.urls[0].lastPathComponent) with" : "Open \(choice.urls.count) files with"
    }

    private func tile(app: URL?) -> some View {
        let isHovered = hovered == .some(app)
        let isDefault = app != nil && app == choice.preferred
        return Button { onChoose(app) } label: {
            VStack(spacing: 5) {
                Group {
                    if let app {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "ellipsis.circle").resizable().fontWeight(.light)
                            .foregroundStyle(.white.opacity(0.7)).padding(3)
                    }
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                Text(app.map(FileMenus.name(of:)) ?? "Other…")
                    .font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(.white.opacity(isHovered ? 1 : 0.82))
                    .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity).frame(height: HomeLayout.tileHeight)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.18 : isDefault ? 0.13 : 0.06)))
            .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = .some(app) } else if hovered == .some(app) { hovered = nil }
        }
        .accessibilityLabel(app.map { isDefault ? "\(FileMenus.name(of: $0)), default app" : FileMenus.name(of: $0) } ?? "Other app")
    }
}
