// Draws the NotchNotch app icon at every size iconutil needs.
// Usage: swift scripts/make-icon.swift <output.iconset>
// Then:  iconutil -c icns <output.iconset> -o apps/macos/Resources/AppIcon.icns
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func drawIcon(size: CGFloat) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = size / 1024
    context.scaleBy(x: scale, y: scale)
    // Flip to a top-left origin so the layout reads like the screen.
    context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824 pt body centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the body.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(squircle); context.setFillColor(CGColor(gray: 0.1, alpha: 1)); context.fillPath()
    context.restoreGState()

    // Body: a calm "screen" gradient.
    context.saveGState()
    context.addPath(squircle); context.clip()
    let colors = [CGColor(srgbRed: 0.33, green: 0.36, blue: 0.55, alpha: 1),
                  CGColor(srgbRed: 0.10, green: 0.11, blue: 0.18, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Wallpaper glows give the body depth, like a desktop under the notch.
    func glow(_ center: CGPoint, _ radius: CGFloat, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) {
        let colors = [CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha),
                      CGColor(srgbRed: red, green: green, blue: blue, alpha: 0)] as CFArray
        let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        context.drawRadialGradient(radial, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    glow(CGPoint(x: 760, y: 860), 520, 1.0, 0.55, 0.42, 0.55)
    glow(CGPoint(x: 230, y: 900), 460, 0.35, 0.55, 1.0, 0.45)

    // Notch: black body hanging from the top edge with concave shoulders.
    let notchWidth: CGFloat = 480, notchHeight: CGFloat = 210, shoulder: CGFloat = 46, radius: CGFloat = 96
    let left = 512 - notchWidth / 2, right = 512 + notchWidth / 2, top: CGFloat = 100, bottom = top + notchHeight
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: left - shoulder, y: top))
    notch.addQuadCurve(to: CGPoint(x: left, y: top + shoulder), control: CGPoint(x: left, y: top))
    notch.addLine(to: CGPoint(x: left, y: bottom - radius))
    notch.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
    notch.addLine(to: CGPoint(x: right - radius, y: bottom))
    notch.addQuadCurve(to: CGPoint(x: right, y: bottom - radius), control: CGPoint(x: right, y: bottom))
    notch.addLine(to: CGPoint(x: right, y: top + shoulder))
    notch.addQuadCurve(to: CGPoint(x: right + shoulder, y: top), control: CGPoint(x: right, y: top))
    notch.closeSubpath()
    context.addPath(notch); context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fillPath()

    // Live activity inside the notch: artwork tile on the left, waveform on the right.
    let center = top + notchHeight * 0.58
    let tile = CGRect(x: left + 62, y: center - 40, width: 80, height: 80)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 22, cornerHeight: 22, transform: nil))
    context.setFillColor(CGColor(srgbRed: 1.0, green: 0.62, blue: 0.38, alpha: 1)); context.fillPath()
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    for (index, height) in [40.0, 78.0, 54.0, 88.0].enumerated() {
        let x = right - 62 - 20 - CGFloat(3 - index) * 34
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: center - height / 2, width: 20, height: height),
                               cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()
    }

    // Soft highlight along the top of the body.
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.12)); context.setLineWidth(4)
    context.addPath(squircle); context.strokePath()
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
