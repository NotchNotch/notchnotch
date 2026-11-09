import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-archive-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private let manifest = Data(#"{"id":"dev.test.archive","name":"Archive","version":"1","apiVersion":1,"entry":"bundle.js","permissions":[]}"#.utf8)

/// Writes a stored (uncompressed) zip so tests can craft entries no zip tool would make.
private struct ZipWriter {
    struct Item { var name: String; var data = Data(); var mode: UInt32 = 0o100644; var crc: UInt32? = nil; var flags: UInt16 = 0 }
    static func archive(_ items: [Item]) -> Data {
        var body = Data(), directory = Data()
        func u16(_ value: Int, _ out: inout Data) { out.append(UInt8(value & 0xFF)); out.append(UInt8((value >> 8) & 0xFF)) }
        func u32(_ value: UInt32, _ out: inout Data) { for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8((value >> UInt32(shift)) & 0xFF)) } }
        for item in items {
            let name = Data(item.name.utf8), crc = item.crc ?? ExtensionArchive.crc32(item.data), offset = UInt32(body.count)
            u32(0x0403_4b50, &body); u16(20, &body); u16(Int(item.flags), &body); u16(0, &body); u16(0, &body); u16(0, &body)
            u32(crc, &body); u32(UInt32(item.data.count), &body); u32(UInt32(item.data.count), &body)
            u16(name.count, &body); u16(0, &body); body.append(name); body.append(item.data)
            u32(0x0201_4b50, &directory); u16(0x031E, &directory); u16(20, &directory); u16(Int(item.flags), &directory); u16(0, &directory)
            u16(0, &directory); u16(0, &directory); u32(crc, &directory); u32(UInt32(item.data.count), &directory)
            u32(UInt32(item.data.count), &directory); u16(name.count, &directory); u16(0, &directory); u16(0, &directory)
            u16(0, &directory); u16(0, &directory); u32(item.mode << 16, &directory); u32(offset, &directory); directory.append(name)
        }
        var end = Data()
        u32(0x0605_4b50, &end); u16(0, &end); u16(0, &end); u16(items.count, &end); u16(items.count, &end)
        u32(UInt32(directory.count), &end); u32(UInt32(body.count), &end); u16(0, &end)
        return body + directory + end
    }
}

private func extract(_ items: [ZipWriter.Item], in root: URL) throws -> URL {
    let file = root.appendingPathComponent("test.notchext")
    try ZipWriter.archive(items).write(to: file)
    let destination = root.appendingPathComponent("out")
    try ExtensionArchive.extract(file, into: destination)
    return destination
}

@Test func archivesFromZipAndFinderCompressExtractWithExecutableHelpers() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("my-extension")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("helpers"), withIntermediateDirectories: true)
    try manifest.write(to: source.appendingPathComponent("notchnotch.json"))
    try Data(String(repeating: "console.log('compressible');\n", count: 400).utf8).write(to: source.appendingPathComponent("bundle.js"))
    let tool = source.appendingPathComponent("helpers/tool")
    try Data("#!/bin/sh\necho ok\n".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

    // `notchnotch pack` uses zip with the package at the root (deflated).
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.arguments = ["-q", "-r", "-X", root.appendingPathComponent("pack.notchext").path, "."]
    zip.currentDirectoryURL = source
    try zip.run(); zip.waitUntilExit()
    // Finder's Compress wraps the folder and adds __MACOSX resource forks.
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, root.appendingPathComponent("finder.notchext").path]
    try ditto.run(); ditto.waitUntilExit()

    for name in ["pack", "finder"] {
        let out = root.appendingPathComponent(name + "-out")
        try ExtensionArchive.extract(root.appendingPathComponent(name + ".notchext"), into: out)
        #expect(try Data(contentsOf: out.appendingPathComponent("bundle.js")) == Data(contentsOf: source.appendingPathComponent("bundle.js")))
        #expect(FileManager.default.isExecutableFile(atPath: out.appendingPathComponent("helpers/tool").path))
        #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("__MACOSX").path))
        #expect(try ExtensionStore(directory: root.appendingPathComponent("library")).inspect(out).id == "dev.test.archive")
    }
}

@Test func unsafeEntriesAreRejectedBeforeAnythingIsWritten() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let base = ZipWriter.Item(name: "notchnotch.json", data: manifest)
    let unsafe: [([ZipWriter.Item], String)] = [
        ([base, .init(name: "../escape.txt", data: Data("x".utf8))], "unsafe path"),
        ([base, .init(name: "helpers/../../escape.txt", data: Data("x".utf8))], "unsafe path"),
        ([base, .init(name: "/etc/escape.txt", data: Data("x".utf8))], "unsafe path"),
        ([base, .init(name: "link", data: Data("/etc/passwd".utf8), mode: 0o120777)], "symbolic links"),
        ([base, .init(name: "fifo", mode: 0o010644)], "special files"),
        ([base, .init(name: "a\\b.txt", data: Data("x".utf8))], "unsafe path"),
        ([base, .init(name: "Bundle.js", data: Data()), .init(name: "bundle.js", data: Data())], "twice"),
        ([base, .init(name: "secret.txt", data: Data("x".utf8), flags: 1)], "Encrypted"),
        ([base, .init(name: "bundle.js", data: Data("x".utf8), crc: 0xDEAD_BEEF)], "checksum"),
        ([.init(name: "bundle.js", data: Data("x".utf8))], "no notchnotch.json"),
        ([base] + (0..<512).map { ZipWriter.Item(name: "f\($0)", data: Data()) }, "up to 512"),
    ]
    for (index, (items, reason)) in unsafe.enumerated() {
        let directory = root.appendingPathComponent("case-\(index)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            _ = try extract(items, in: directory)
            Issue.record("case \(index) was accepted")
        } catch {
            #expect(error.localizedDescription.contains(reason), "case \(index): \(error.localizedDescription)")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("out").path), "case \(index) left output")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
    }
}

@Test func declaredSizesAreBoundedSoAZipBombCannotExpand() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var archive = ZipWriter.archive([.init(name: "notchnotch.json", data: manifest), .init(name: "big.bin", data: Data("x".utf8))])
    // Rewrite the central directory's uncompressed size of the second entry to 65 MiB.
    let directoryStart = Int(archive[archive.count - 6]) | Int(archive[archive.count - 5]) << 8 | Int(archive[archive.count - 4]) << 16
    let second = directoryStart + 46 + "notchnotch.json".utf8.count
    let size = UInt32(65 * 1024 * 1024)
    for byte in 0..<4 { archive[second + 24 + byte] = UInt8((size >> UInt32(8 * byte)) & 0xFF) }
    let file = root.appendingPathComponent("bomb.notchext")
    try archive.write(to: file)
    #expect(performing: { try ExtensionArchive.extract(file, into: root.appendingPathComponent("out")) },
            throws: { $0.localizedDescription.contains("64 MiB") })
}

@Test func downloadedPackagesKeepTheirQuarantineFlag() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("download.notchext")
    try ZipWriter.archive([.init(name: "notchnotch.json", data: manifest), .init(name: "helpers/tool", data: Data("#!/bin/sh\n".utf8), mode: 0o100755)]).write(to: file)
    let flag = Array("0081;00000000;Safari;".utf8)
    #expect(setxattr(file.path, "com.apple.quarantine", flag, flag.count, 0, 0) == 0)
    let out = root.appendingPathComponent("out")
    try ExtensionArchive.extract(file, into: out)
    ExtensionArchive.propagateQuarantine(from: file, to: out)
    #expect(getxattr(out.appendingPathComponent("helpers/tool").path, "com.apple.quarantine", nil, 0, 0, 0) == flag.count)
}
