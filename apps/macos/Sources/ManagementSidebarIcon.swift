import SwiftUI

/// A Settings icon as macOS draws them: a white symbol on a colored squircle,
/// lit a little from the top.
struct SettingsIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(color.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
