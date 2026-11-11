import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import NotchProtocol
@testable import NotchExtensions

private func makePackage(icon: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-icon-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
    try Data("""
    {"id":"dev.test.icon","name":"Icon","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[],"icon":"\(icon)"}
    """.utf8).write(to: root.appendingPathComponent("notchnotch.json"))
    try Data("void 0;".utf8).write(to: root.appendingPathComponent("bundle.js"))
    return root
}

private func writePNG(_ url: URL, width: Int, height: Int = 0) throws {
    let context = try #require(CGContext(data: nil, width: width, height: height == 0 ? width : height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height == 0 ? width : height))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Test func aSymbolNameStaysASymbol() throws {
    let root = try makePackage(icon: "timer")
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try ExtensionStore(directory: root).inspect(root).icon == .symbol("timer"))
}

@Test func aPNGIconResolvesToItsAsset() throws {
    let root = try makePackage(icon: "icon.png")
    defer { try? FileManager.default.removeItem(at: root) }
    try writePNG(root.resolvingSymlinksInPath().appendingPathComponent("assets/icon.png"), width: 512)
    #expect(try ExtensionStore(directory: root).inspect(root).icon.imageURL?.lastPathComponent == "icon.png")
}

@Test func iconsThatAreMissingOrTheWrongSizeAreRejected() throws {
    let root = try makePackage(icon: "icon.png")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ExtensionStore(directory: root)
    #expect(throws: ProtocolError.self) { try store.inspect(root) }
    try writePNG(root.appendingPathComponent("assets/icon.png"), width: 256)
    #expect(throws: ProtocolError.self) { try store.inspect(root) }
    try writePNG(root.appendingPathComponent("assets/icon.png"), width: 512, height: 500)
    #expect(throws: ProtocolError.self) { try store.inspect(root) }
    try Data("not a png".utf8).write(to: root.appendingPathComponent("assets/icon.png"))
    #expect(throws: ProtocolError.self) { try store.inspect(root) }
}

@Test func iconFileNamesCannotLeaveTheAssetsFolder() throws {
    for icon in ["../icon.png", "assets/icon.png", ".png", "icon@dark.png"] {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
        {"id":"dev.test.icon","name":"Icon","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[],"icon":"\(icon)"}
        """.utf8))
        #expect(throws: ProtocolError.self, "\(icon)") { try manifest.validate() }
    }
}
