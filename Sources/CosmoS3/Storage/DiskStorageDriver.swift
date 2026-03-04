import Foundation

/// Disk-based blob storage. Each object is stored as a file at baseDirectory/blobFilename.
public final class DiskStorageDriver: @unchecked Sendable {
    private let baseDirectory: String

    public init(baseDirectory: String) {
        var dir = baseDirectory
        if !dir.hasSuffix("/") { dir += "/" }
        self.baseDirectory = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    public func write(key: String, data: Data) throws {
        let path = filePath(for: key)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public func read(key: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: filePath(for: key)))
    }

    public func readRange(key: String, start: Int, end: Int) throws -> Data {
        let url = URL(fileURLWithPath: filePath(for: key))
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(start))
        let length = end - start + 1
        return handle.readData(ofLength: length)
    }

    public func delete(key: String) {
        try? FileManager.default.removeItem(atPath: filePath(for: key))
    }

    public func exists(key: String) -> Bool {
        FileManager.default.fileExists(atPath: filePath(for: key))
    }

    private func filePath(for key: String) -> String {
        baseDirectory + key
    }
}
