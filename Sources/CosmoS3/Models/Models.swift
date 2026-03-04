import Foundation

public struct S3Bucket: Sendable {
    public var id: Int
    public var guid: String
    public var ownerGuid: String
    public var name: String
    public var region: String
    public var storageType: String
    public var diskDirectory: String
    public var enableVersioning: Bool
    public var enablePublicWrite: Bool
    public var enablePublicRead: Bool
    public var createdUtc: String

    public init(
        id: Int = 0,
        guid: String = UUID().uuidString.lowercased(),
        ownerGuid: String,
        name: String,
        region: String = "us-west-1",
        storageType: String = "Disk",
        diskDirectory: String,
        enableVersioning: Bool = false,
        enablePublicWrite: Bool = false,
        enablePublicRead: Bool = false,
        createdUtc: String = isoNow()
    ) {
        self.id = id; self.guid = guid; self.ownerGuid = ownerGuid
        self.name = name; self.region = region; self.storageType = storageType
        self.diskDirectory = diskDirectory; self.enableVersioning = enableVersioning
        self.enablePublicWrite = enablePublicWrite; self.enablePublicRead = enablePublicRead
        self.createdUtc = createdUtc
    }
}

public struct S3ObjectMeta: Sendable {
    public var id: Int
    public var guid: String
    public var bucketGuid: String
    public var ownerGuid: String
    public var authorGuid: String
    public var key: String
    public var contentType: String
    public var contentLength: Int
    public var version: Int
    public var etag: String
    public var blobFilename: String
    public var isFolder: Bool
    public var deleteMarker: Bool
    public var md5: String?
    public var metadata: String?
    public var createdUtc: String
    public var lastUpdateUtc: String

    public init(
        id: Int = 0,
        guid: String = UUID().uuidString.lowercased(),
        bucketGuid: String,
        ownerGuid: String,
        authorGuid: String,
        key: String,
        contentType: String = "application/octet-stream",
        contentLength: Int = 0,
        version: Int = 1,
        etag: String = "",
        blobFilename: String = UUID().uuidString.lowercased(),
        isFolder: Bool = false,
        deleteMarker: Bool = false,
        md5: String? = nil,
        metadata: String? = nil
    ) {
        self.id = id; self.guid = guid; self.bucketGuid = bucketGuid
        self.ownerGuid = ownerGuid; self.authorGuid = authorGuid; self.key = key
        self.contentType = contentType; self.contentLength = contentLength
        self.version = version; self.etag = etag; self.blobFilename = blobFilename
        self.isFolder = isFolder; self.deleteMarker = deleteMarker
        self.md5 = md5; self.metadata = metadata
        let now = isoNow()
        self.createdUtc = now; self.lastUpdateUtc = now
    }
}

public struct S3User: Sendable {
    public var guid: String
    public var name: String
    public var email: String
    public var createdUtc: String
}

public struct S3Credential: Sendable {
    public var guid: String
    public var userGuid: String
    public var accessKey: String
    public var secretKey: String
    public var isBase64: Bool
}

public func isoNow() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}
