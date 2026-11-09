import Compression
import Darwin
import Foundation
import NotchProtocol

/// Reads `.notchext` packages: a zip of a built extension folder.
///
/// Archives come from the internet, so this never hands them to `unzip` or
/// `ditto`. Every central-directory entry is validated before anything is
/// written: relative paths only, no `..`, no symbolic links, no encryption or
/// Zip64, stored or deflated data only, and the installer's count and size
/// limits. Each file's CRC-32 is checked after decompression.
public enum ExtensionArchive {
    public static let fileExtension = "notchext"
    static let maximumEntries = 512
    static let maximumBytes = 64 * 1024 * 1024
    static let maximumArchiveBytes = 96 * 1024 * 1024

    private struct Entry {
        let path: [String]
        let isDirectory: Bool
        let executable: Bool
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localHeader: Int
    }

    /// Extracts `archive` into `destination`, which must not exist yet.
    /// A single top-level folder (as made by Finder's Compress) is unwrapped.
    public static func extract(_ archive: URL, into destination: URL) throws {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard data.count <= maximumArchiveBytes else { throw invalid("The package is larger than 96 MiB.") }
        var entries = try centralDirectory(data)
        entries = unwrapSingleFolder(entries)
        guard entries.contains(where: { $0.path == ["notchnotch.json"] && !$0.isDirectory }) else {
            throw invalid("The package has no notchnotch.json at its top level.")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            for entry in entries {
                let url = entry.path.reduce(destination) { $0.appendingPathComponent($1, isDirectory: false) }
                if entry.isDirectory {
                    try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
                    continue
                }
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
                let contents = try read(entry, from: data)
                guard manager.createFile(atPath: url.path, contents: contents,
                                         attributes: [.posixPermissions: entry.executable ? 0o755 : 0o644]) else {
                    throw invalid("Couldn’t write \(entry.path.joined(separator: "/")).")
                }
            }
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    /// Gives every extracted file the archive's quarantine flag, as Archive
    /// Utility does, so Gatekeeper still assesses downloaded native helpers.
    public static func propagateQuarantine(from archive: URL, to root: URL) {
        let name = "com.apple.quarantine"
        let length = getxattr(archive.path, name, nil, 0, 0, 0)
        guard length > 0 else { return }
        var value = [UInt8](repeating: 0, count: length)
        guard getxattr(archive.path, name, &value, length, 0, 0) == length else { return }
        let paths = [root.path] + (FileManager.default.enumerator(atPath: root.path)?.compactMap { $0 as? String }
            .map { root.appendingPathComponent($0).path } ?? [])
        for path in paths { setxattr(path, name, value, length, 0, XATTR_NOFOLLOW) }
    }

    // MARK: - Zip structure

    private static func centralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw invalid("This isn’t a NotchNotch extension package.") }
        // The end-of-central-directory record is last; only a comment may follow it.
        let lowest = max(0, data.count - 22 - 65_535)
        var end: Int?
        for offset in stride(from: data.count - 22, through: lowest, by: -1)
            where data.u32(offset) == 0x0605_4b50 && offset + 22 + Int(data.u16(offset + 20)) == data.count {
            end = offset; break
        }
        guard let end else { throw invalid("This isn’t a NotchNotch extension package.") }
        let count = Int(data.u16(end + 10))
        let directorySize = Int(data.u32(end + 12))
        let start = Int(data.u32(end + 16))
        guard data.u16(end + 4) == 0, data.u16(end + 6) == 0, data.u16(end + 8) == count,
              count != 0xFFFF, directorySize != 0xFFFF_FFFF, start != 0xFFFF_FFFF,
              start + directorySize <= end else {
            throw invalid("Split or Zip64 packages aren’t supported.")
        }
        var entries: [Entry] = []
        var seen = Set<String>()
        var total = 0
        var offset = start
        for _ in 0..<count {
            guard offset + 46 <= start + directorySize, data.u32(offset) == 0x0201_4b50 else { throw invalid("The package is damaged.") }
            let madeBy = data.u16(offset + 4)
            let flags = data.u16(offset + 8)
            let method = data.u16(offset + 10)
            let crc = data.u32(offset + 16)
            let compressedSize = Int(data.u32(offset + 20))
            let size = Int(data.u32(offset + 24))
            let nameLength = Int(data.u16(offset + 28))
            let headerLength = 46 + nameLength + Int(data.u16(offset + 30)) + Int(data.u16(offset + 32))
            let attributes = data.u32(offset + 38)
            let localHeader = Int(data.u32(offset + 42))
            guard offset + headerLength <= start + directorySize,
                  let name = String(data: data[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8) else {
                throw invalid("The package is damaged.")
            }
            offset += headerLength
            guard flags & 0x41 == 0 else { throw invalid("Encrypted packages aren’t supported.") }
            guard method == 0 || method == 8 else { throw invalid("\(name) uses an unsupported compression method.") }
            guard compressedSize != 0xFFFF_FFFF, size != 0xFFFF_FFFF, localHeader != 0xFFFF_FFFF else {
                throw invalid("Zip64 packages aren’t supported.")
            }
            // Finder's Compress adds resource forks and Finder metadata; they're never part of a package.
            if name.hasPrefix("__MACOSX/") || name == ".DS_Store" || name.hasSuffix("/.DS_Store") { continue }
            let isDirectory = name.hasSuffix("/")
            let path = name.split(separator: "/", omittingEmptySubsequences: false).dropLast(isDirectory ? 1 : 0).map(String.init)
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"), name.utf8.count <= 1024,
                  !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw invalid("The package contains an unsafe path: \(name)")
            }
            // Unix mode lives in the high bits when the archive was made on a Unix-like system.
            let mode = madeBy >> 8 == 3 ? attributes >> 16 : 0
            let type = mode & 0o170000
            guard type == 0 || type == 0o100000 || type == 0o040000 else {
                throw invalid("Packages can’t contain symbolic links or special files: \(name)")
            }
            // APFS is usually case-insensitive: two names differing only in case would overwrite each other.
            guard seen.insert(path.joined(separator: "/").lowercased()).inserted else {
                throw invalid("The package lists \(name) twice.")
            }
            total += size
            guard seen.count <= maximumEntries else { throw invalid("Packages may contain up to 512 files and folders.") }
            guard total <= maximumBytes else { throw invalid("The package is larger than 64 MiB when unpacked.") }
            entries.append(.init(path: path, isDirectory: isDirectory, executable: mode & 0o111 != 0, method: method,
                                 crc: crc, compressedSize: compressedSize, size: size, localHeader: localHeader))
        }
        return entries
    }

    private static func unwrapSingleFolder(_ entries: [Entry]) -> [Entry] {
        guard !entries.contains(where: { $0.path == ["notchnotch.json"] }),
              let first = entries.first?.path.first,
              entries.allSatisfy({ $0.path.first == first && ($0.path.count > 1 || $0.isDirectory) }),
              entries.contains(where: { $0.path == [first, "notchnotch.json"] }) else { return entries }
        return entries.compactMap { entry in
            entry.path.count > 1 ? Entry(path: Array(entry.path.dropFirst()), isDirectory: entry.isDirectory,
                                         executable: entry.executable, method: entry.method, crc: entry.crc,
                                         compressedSize: entry.compressedSize, size: entry.size, localHeader: entry.localHeader) : nil
        }
    }

    private static func read(_ entry: Entry, from data: Data) throws -> Data {
        let header = entry.localHeader
        guard header + 30 <= data.count, data.u32(header) == 0x0403_4b50 else { throw invalid("The package is damaged.") }
        let start = header + 30 + Int(data.u16(header + 26)) + Int(data.u16(header + 28))
        guard start + entry.compressedSize <= data.count else { throw invalid("The package is damaged.") }
        let compressed = data[start..<(start + entry.compressedSize)]
        let output: Data
        if entry.method == 0 {
            guard entry.compressedSize == entry.size else { throw invalid("The package is damaged.") }
            output = Data(compressed)
        } else if entry.size == 0 {
            output = Data()
        } else {
            // Raw DEFLATE into a buffer of the declared size; extra output is cut off
            // and then fails the length or CRC check below.
            var buffer = Data(count: entry.size)
            let written = buffer.withUnsafeMutableBytes { target in
                compressed.withUnsafeBytes { source in
                    compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                                              source.bindMemory(to: UInt8.self).baseAddress!, entry.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.size else { throw invalid("The package is damaged.") }
            output = buffer
        }
        guard crc32(output) == entry.crc else { throw invalid("The package is damaged (checksum mismatch).") }
        return output
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(UInt32.max) { crcTable[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }

    private static func invalid(_ message: String) -> ProtocolError { .invalid(message) }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }
    func u32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }
}
