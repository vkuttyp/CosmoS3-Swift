import Foundation

public struct BucketHandler {
    private let da: DataAccess
    private let bucketManager: BucketManager
    private let storageBaseDir: String

    public init(da: DataAccess, bucketManager: BucketManager, storageBaseDir: String) {
        self.da = da
        self.bucketManager = bucketManager
        self.storageBaseDir = storageBaseDir
    }

    // MARK: - Create

    public func create(ctx: S3Context) async throws {
        guard let name = ctx.s3Request.bucket else { throw S3Error.invalidBucketName }

        if await bucketManager.get(name: name) != nil {
            // Already exists — return 200 if same owner, else 409
            if let existing = await bucketManager.get(name: name),
               existing.ownerGuid == (ctx.user?.guid ?? "default") {
                ctx.http.response.setStatus(200)
                return
            }
            throw S3Error.bucketAlreadyExists
        }

        guard isValidBucketName(name) else { throw S3Error.invalidBucketName }

        let ownerGuid = ctx.user?.guid ?? "default"
        let diskDir = "\(storageBaseDir)/\(name)/Objects/"
        let bucket = S3Bucket(ownerGuid: ownerGuid, name: name, diskDirectory: diskDir)
        try await bucketManager.add(bucket)

        ctx.http.response.setStatus(200)
        ctx.http.response.headers["Location"] = "/\(name)"
    }

    // MARK: - Delete

    public func delete(ctx: S3Context) async throws {
        guard let name = ctx.s3Request.bucket,
              let bucket = await bucketManager.get(name: name) else {
            throw S3Error.noSuchBucket
        }

        // Bucket must be empty
        let stats = try await da.getBucketObjectStats(bucketGuid: bucket.guid)
        guard stats.count == 0 else { throw S3Error.bucketNotEmpty }

        try await bucketManager.remove(name: name)
        ctx.http.response.setStatus(204)
    }

    // MARK: - Exists (HEAD)

    public func exists(ctx: S3Context) async throws {
        guard let name = ctx.s3Request.bucket,
              let bucket = await bucketManager.get(name: name) else {
            throw S3Error.noSuchBucket
        }
        ctx.http.response.headers["x-amz-bucket-region"] = bucket.region
        ctx.http.response.setStatus(200)
    }

    // MARK: - List Objects

    public func listObjects(ctx: S3Context) async throws -> String {
        let req = ctx.s3Request
        guard let name = req.bucket,
              let bucket = await bucketManager.get(name: name) else {
            throw S3Error.noSuchBucket
        }

        let prefix = req.prefix ?? ""
        let delimiter = req.delimiter
        let marker = req.marker
        let maxKeys = req.maxKeys

        // Determine startIndex from marker
        var startIndex = 0
        if let marker, !marker.isEmpty, let idx = Int(marker) {
            startIndex = idx
        }

        let result = try await da.enumerateObjects(
            bucketGuid: bucket.guid,
            prefix: prefix.isEmpty ? nil : prefix,
            delimiter: delimiter,
            startIndex: startIndex,
            maxKeys: maxKeys
        )

        let nextMarker = result.isTruncated ? String(result.nextStartIndex) : nil

        return S3Xml.listObjects(
            bucket: bucket,
            objects: result.objects,
            prefixes: result.prefixes,
            prefix: prefix,
            delimiter: delimiter,
            marker: req.marker,
            maxKeys: maxKeys,
            isTruncated: result.isTruncated,
            nextMarker: nextMarker
        )
    }

    // MARK: - Helpers

    private func isValidBucketName(_ name: String) -> Bool {
        guard name.count >= 3 && name.count <= 63 else { return false }
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
