// Draws the NotchNotch app icon from the logo (assets/logo.svg) at every size iconutil needs.
// Usage: swift scripts/make-icon.swift <output.iconset>
// Then:  iconutil -c icns <output.iconset> -o apps/macos/Resources/AppIcon.icns
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The logo in its 100 × 100 SVG coordinate space (y grows downward).
func logoPath() -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100), CGPoint(x: 50, y: 100), CGPoint(x: 50, y: 50)])
    path.closeSubpath()
    path.addLines(between: [CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 0)])
    path.closeSubpath()
    return path
}

func drawIcon(size: CGFloat) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: size / 1024, y: size / 1024)
    context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824 pt body centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    // Shadow metrics are in device pixels (not affected by the CTM), so scale them by hand.
    let unit = size / 1024
    context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(squircle); context.setFillColor(CGColor(gray: 0.05, alpha: 1)); context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle); context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.03, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Logo: 400 pt, optically centred (a hair above the geometric centre).
    context.saveGState()
    context.translateBy(x: 312, y: 300); context.scaleBy(x: 4, y: 4)
    context.addPath(logoPath()); context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fillPath()
    context.restoreGState()
    // Hairline edge highlight.
    context.addPath(squircle); context.setStrokeColor(CGColor(gray: 1, alpha: 0.1)); context.setLineWidth(4); context.strokePath()
    context.restoreGState()
    return context.makeImage()!
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let url = output.appendingPathComponent(name) as CFURL
        let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, drawIcon(size: CGFloat(points * scale)), nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
    }
}
print("Wrote \(output.path)")
