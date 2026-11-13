import Foundation
import CoreGraphics

/// The silhouette always fits the complete content. Its transparent animation
/// canvas can grow for taller content, and stays stable during open/close.
public struct NotchGeometry: Equatable, Sendable {
    public static let expandedBottomPadding: CGFloat = 14
    public var cameraWidth: CGFloat
    public var cameraHeight: CGFloat
    public var attached: Bool
    public var contentHeight: CGFloat
    public var hasActivity: Bool
    public var reservedCanvasHeight: CGFloat
    public var expandedHeaderHeight: CGFloat?
    /// Each compact wing's width beside the camera; see `wingWidth(fitting:)`.
    public var wingWidth: CGFloat
    /// Home's width while it shows (wider than an activity's page), else zero.
    public var homeWidth: CGFloat = 0

    /// Wings hold an icon and a short reading. Both are as wide as the wider
    /// content so the notch stays centered on the camera, with room for the
    /// rounded outer corner and a gap beside the camera.
    public static let minimumWingWidth: CGFloat = 30
    public static let maximumWingWidth: CGFloat = 96
    /// With more live activities shown beside the main one, both wings may
    /// grow this far, so the silhouette stays symmetric around the camera.
    public static let roomyWingWidth: CGFloat = 132
    public static let wingOuterInset: CGFloat = 10
    public static let wingInnerInset: CGFloat = 6
    public static func wingWidth(fitting contentWidth: CGFloat, roomy: Bool = false) -> CGFloat {
        let needed = ceil(max(0, contentWidth)) + wingOuterInset + wingInnerInset
        return min(roomy ? roomyWingWidth : maximumWingWidth, max(minimumWingWidth, needed))
    }

    public init(cameraWidth: CGFloat = 184, cameraHeight: CGFloat = 32, attached: Bool = true,
                contentHeight: CGFloat = 156, hasActivity: Bool = true, reservedCanvasHeight: CGFloat = 0,
                expandedHeaderHeight: CGFloat? = nil, wingWidth: CGFloat = NotchGeometry.minimumWingWidth) {
        self.cameraWidth = max(0, cameraWidth)
        self.cameraHeight = max(24, cameraHeight)
        self.attached = attached
        self.contentHeight = contentHeight
        self.hasActivity = hasActivity
        self.reservedCanvasHeight = reservedCanvasHeight
        self.expandedHeaderHeight = expandedHeaderHeight
        self.wingWidth = min(Self.roomyWingWidth, max(Self.minimumWingWidth, wingWidth))
    }

    /// An open activity's page width.
    public var expandedWidth: CGFloat { max(384, cameraWidth + 148) }
    /// The open notch: an activity's page, or Home when it is wider.
    public var expandedBodyWidth: CGFloat { max(expandedWidth, homeWidth) }
    public var compactWidth: CGFloat { cameraWidth + (hasActivity ? 2 * wingWidth : 0) }
    public var hoveredWidth: CGFloat { max(cameraWidth + 72, compactWidth + 12) }
    public var hoveredHeight: CGFloat { cameraHeight + (hasActivity ? 4 : 10) }
    public var peekWidth: CGFloat { max(320, cameraWidth + 112) }
    public var peekHeight: CGFloat { cameraHeight + 46 }
    public var fittedContentHeight: CGFloat { ceil(max(0, contentHeight)) }
    public var expandedHeight: CGFloat { (expandedHeaderHeight ?? cameraHeight + 8) + fittedContentHeight + Self.expandedBottomPadding }
    public var canvasSize: CGSize {
        // Fixed for every state, so the window never resizes mid-animation.
        let widestCompact = cameraWidth + 2 * Self.roomyWingWidth + 12
        return .init(width: max(expandedWidth, HomeLayout.maximumWidth, peekWidth, widestCompact) + 104,
              height: ceil(max(cameraHeight + 378, expandedHeight + 28, reservedCanvasHeight)))
    }
    public func bodySize(expanded: Bool) -> CGSize {
        bodySize(presentation: expanded ? .expanded : .compact)
    }
    public func bodySize(presentation: NotchPresentation) -> CGSize {
        switch presentation {
        case .idle: .init(width: cameraWidth, height: cameraHeight)
        case .compact: .init(width: compactWidth, height: cameraHeight)
        case .hovered: .init(width: hoveredWidth, height: hoveredHeight)
        case .peek: .init(width: peekWidth, height: peekHeight)
        case .expanded: .init(width: expandedBodyWidth, height: expandedHeight)
        }
    }

    public func shoulderRadius(expanded: Bool) -> CGFloat { shoulderRadius(presentation: expanded ? .expanded : .compact) }
    public func bottomRadius(expanded: Bool) -> CGFloat { bottomRadius(presentation: expanded ? .expanded : .compact) }
    public func shoulderRadius(presentation: NotchPresentation) -> CGFloat {
        guard attached else { return 0 }
        switch presentation {
        case .idle: return 0
        case .compact: return 5
        case .hovered: return 10
        case .peek: return 18
        case .expanded: return 28
        }
    }
    public func bottomRadius(presentation: NotchPresentation) -> CGFloat {
        switch presentation { case .idle: 12; case .compact: 12; case .hovered: 16; case .peek: 22; case .expanded: 34 }
    }
    public func bodyFrame(presentation: NotchPresentation) -> CGRect {
        let size = bodySize(presentation: presentation)
        return .init(x: (canvasSize.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }
    /// The hidden notch can be discovered by approaching its bottom edge.
    public func activationFrame(presentation: NotchPresentation) -> CGRect {
        bodyFrame(presentation: presentation).insetBy(dx: -4, dy: 0)
            .union(CGRect(x: (canvasSize.width - cameraWidth - 8) / 2, y: 0,
                          width: cameraWidth + 8, height: cameraHeight + 6))
    }
    public func bodyFrame(expanded: Bool) -> CGRect {
        let size = bodySize(expanded: expanded)
        return .init(x: (canvasSize.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }
}
