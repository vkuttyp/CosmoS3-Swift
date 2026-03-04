import Foundation
import Crypto

public struct ObjectHandler {
    private let da: DataAccess
    private let bucketManager: BucketManager
    private let storageBaseDir: String

    public init(da: DataAccess, bucketManager: BucketManager, storageBaseDir: String) {
        self.da = da
        self.bucketManager = bucketManager
        self.storageBaseDir = storageBaseDir
    }

    // MARK: - Write (PUT)

    public func write(ctx: S3Context) async throws {
        let req = ctx.s3Request
        guard let bucketName = req.bucket, let key = req.key else { throw S3Error.invalidRequest }
        guard let bucket = await bucketManager.get(name: bucketName) else { throw S3Error.noSuchBucket }

        let ownerGuid = ctx.user?.guid ?? "default"
        let data = req.body
        let contentType = req.headers["content-type"] ?? "application/octet-stream"

        // Version
        let version = bucket.enableVersioning
            ? (try await da.getNextVersion(bucketGuid: bucket.guid, key: key))
            : 1

        // If versioning disabled, find existing and reuse its blobFilename
        var existingObj: S3ObjectMeta? = nil
        if !bucket.enableVersioning {
            existingObj = try await da.getObjectLatest(bucketGuid: bucket.guid, key: key)
        }

        let blobFilename = existingObj?.blobFilename ?? UUID().uuidString.lowercased()
        let etag = md5Hex(data)

        var obj = S3ObjectMeta(
            guid: existingObj?.guid ?? UUID().uuidString.lowercased(),
            bucketGuid: bucket.guid,
            ownerGuid: ownerGuid,
            authorGuid: ownerGuid,
            key: key,
            contentType: contentType,
            contentLength: data.count,
            version: version,
            etag: etag,
            blobFilename: blobFilename
        )
        obj.md5 = etag

        // Write blob to disk
        let driver = DiskStorageDriver(baseDirectory: bucket.diskDirectory)
        try driver.write(key: blobFilename, data: data)

        // Persist metadata
        try await da.saveObject(obj)

        ctx.http.response.setStatus(200)
        ctx.http.response.headers["ETag"] = "\"\(etag)\""
        if bucket.enableVersioning {
            ctx.http.response.headers["x-amz-version-id"] = String(version)
        }
    }

    // MARK: - Read (GET)

    public func read(ctx: S3Context) async throws {
        let req = ctx.s3Request
        guard let bucketName = req.bucket, let key = req.key else { throw S3Error.invalidRequest }
        guard let bucket = await bucketManager.get(name: bucketName) else { throw S3Error.noSuchBucket }

        let obj: S3ObjectMeta?
        if let version = req.versionId {
            obj = try await da.getObjectVersion(bucketGuid: bucket.guid, key: key, version: version)
        } else {
            obj = try await da.getObjectLatest(bucketGuid: bucket.guid, key: key)
        }

        guard let obj, !obj.deleteMarker else { throw S3Error.noSuchKey }

        let driver = DiskStorageDriver(baseDirectory: bucket.diskDirectory)
        let data: Data

        if let start = req.rangeStart, let end = req.rangeEnd {
            data = try driver.readRange(key: obj.blobFilename, start: start, end: end)
            ctx.http.response.setStatus(206)
            ctx.http.response.headers["Content-Range"] = "bytes \(start)-\(end)/\(obj.contentLength)"
        } else {
            data = try driver.read(key: obj.blobFilename)
            ctx.http.response.setStatus(200)
        }

        ctx.http.response.headers["Content-Type"] = obj.contentType
        ctx.http.response.headers["ETag"] = "\"\(obj.etag)\""
        ctx.http.response.headers["Last-Modified"] = obj.lastUpdateUtc
        ctx.http.response.headers["Content-Length"] = String(data.count)
        if bucket.enableVersioning {
            ctx.http.response.headers["x-amz-version-id"] = String(obj.version)
        }
        ctx.http.response.write(data)
    }

    // MARK: - Head (HEAD)

    public func head(ctx: S3Context) async throws {
        let req = ctx.s3Request
        guard let bucketName = req.bucket, let key = req.key else { throw S3Error.invalidRequest }
        guard let bucket = await bucketManager.get(name: bucketName) else { throw S3Error.noSuchBucket }

        guard let obj = try await da.getObjectLatest(bucketGuid: bucket.guid, key: key),
              !obj.deleteMarker else { throw S3Error.noSuchKey }

        ctx.http.response.setStatus(200)
        ctx.http.response.headers["Content-Type"] = obj.contentType
        ctx.http.response.headers["Content-Length"] = String(obj.contentLength)
        ctx.http.response.headers["ETag"] = "\"\(obj.etag)\""
        ctx.http.response.headers["Last-Modified"] = obj.lastUpdateUtc
        if bucket.enableVersioning {
            ctx.http.response.headers["x-amz-version-id"] = String(obj.version)
        }
    }

    // MARK: - Delete (DELETE)

    public func delete(ctx: S3Context) async throws {
        let req = ctx.s3Request
        guard let bucketName = req.bucket, let key = req.key else { throw S3Error.invalidRequest }
        guard let bucket = await bucketManager.get(name: bucketName) else { throw S3Error.noSuchBucket }

        let obj: S3ObjectMeta?
        if let version = req.versionId {
            obj = try await da.getObjectVersion(bucketGuid: bucket.guid, key: key, version: version)
        } else {
            obj = try await da.getObjectLatest(bucketGuid: bucket.guid, key: key)
        }

        if let obj {
            try await da.deleteObjectVersion(guid: obj.guid)
            if bucket.enableVersioning {
                ctx.http.response.headers["x-amz-version-id"] = String(obj.version)
            }
        }

        ctx.http.response.setStatus(204)
    }

    // MARK: - Delete Multiple (POST /?delete)

    public func deleteMultiple(ctx: S3Context) async throws {
        guard let bucketName = ctx.s3Request.bucket,
              let bucket = await bucketManager.get(name: bucketName) else { throw S3Error.noSuchBucket }

        let parser = S3XmlParser(itemTag: "Object", fields: ["Key", "VersionId"])
        let items = parser.parse(data: ctx.s3Request.body)

        var deleted: [(key: String, versionId: Int?)] = []
        var errors: [(key: String, code: String, message: String)] = []

        for item in items {
            guard let key = item["Key"] else { continue }
            let versionId = item["VersionId"].flatMap(Int.init)
            do {
                let obj: S3ObjectMeta?
                if let ver = versionId {
                    obj = try await da.getObjectVersion(bucketGuid: bucket.guid, key: key, version: ver)
                } else {
                    obj = try await da.getObjectLatest(bucketGuid: bucket.guid, key: key)
                }
                if let obj {
                    try await da.deleteObjectVersion(guid: obj.guid)
                }
                deleted.append((key, versionId))
            } catch {
                errors.append((key, "InternalError", error.localizedDescription))
            }
        }

        let xml = S3Xml.deleteResult(deleted: deleted, errors: errors)
        ctx.http.response.headers["Content-Type"] = "application/xml"
        ctx.http.response.writeText(xml, contentType: "application/xml")
    }

    // MARK: - Helpers

    private func md5Hex(_ data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
