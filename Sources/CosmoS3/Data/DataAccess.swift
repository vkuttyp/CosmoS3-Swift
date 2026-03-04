import Foundation
import CosmoSQLCore

// MARK: - DataAccess

public actor DataAccess {
    let db: any SQLDatabase
    private let t: String   // table prefix "s3_"
    private let useMssql: Bool  // MSSQL uses TOP n / different dialect

    public init(db: any SQLDatabase, tablePrefix: String = "s3_", useMssql: Bool = false) {
        self.db = db
        self.t = tablePrefix
        self.useMssql = useMssql
    }

    /// Returns `TOP 1` (MSSQL) or empty string (all others — `LIMIT 1` appended at end).
    private var top1: String { useMssql ? "TOP 1 " : "" }
    /// Appended at end of SELECT for non-MSSQL databases.
    private var limit1: String { useMssql ? "" : " LIMIT 1" }

    // MARK: - Users

    public func getUser(guid: String) async throws -> S3User? {
        let rows = try await db.query("SELECT guid, name, email, createdutc FROM \(t)users WHERE guid = ?", [.string(guid)])
        return rows.first.map(mapUser)
    }

    // MARK: - Credentials

    public func getCredentialByAccessKey(_ key: String) async throws -> S3Credential? {
        let rows = try await db.query("SELECT guid, userguid, accesskey, secretkey, isbase64 FROM \(t)credentials WHERE accesskey = ?", [.string(key)])
        return rows.first.map(mapCredential)
    }

    // MARK: - Buckets

    public func getBuckets() async throws -> [S3Bucket] {
        let rows = try await db.query("SELECT * FROM \(t)buckets ORDER BY name", [])
        return rows.map(mapBucket)
    }

    public func getBucketsByUser(_ userGuid: String) async throws -> [S3Bucket] {
        let rows = try await db.query("SELECT * FROM \(t)buckets WHERE ownerguid = ? ORDER BY name", [.string(userGuid)])
        return rows.map(mapBucket)
    }

    public func getBucketByName(_ name: String) async throws -> S3Bucket? {
        let rows = try await db.query("SELECT * FROM \(t)buckets WHERE name = ?", [.string(name)])
        return rows.first.map(mapBucket)
    }

    public func addBucket(_ bucket: S3Bucket) async throws {
        try await db.execute(
            """
            INSERT INTO \(t)buckets
              (guid, ownerguid, name, regionstring, storagetype, diskdirectory,
               enableversioning, enablepublicwrite, enablepublicread, createdutc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .string(bucket.guid), .string(bucket.ownerGuid),
                .string(bucket.name), .string(bucket.region),
                .string(bucket.storageType), .string(bucket.diskDirectory),
                .int(bucket.enableVersioning ? 1 : 0),
                .int(bucket.enablePublicWrite ? 1 : 0),
                .int(bucket.enablePublicRead ? 1 : 0),
                .string(bucket.createdUtc),
            ]
        )
    }

    public func deleteBucket(guid: String) async throws {
        try await db.execute("DELETE FROM \(t)buckets WHERE guid = ?", [.string(guid)])
    }

    // MARK: - Objects

    public func getObjectLatest(bucketGuid: String, key: String) async throws -> S3ObjectMeta? {
        let rows = try await db.query(
            "SELECT \(top1)* FROM \(t)objects WHERE bucketguid = ? AND objectkey = ? AND deletemarker = 0 ORDER BY version DESC\(limit1)",
            [.string(bucketGuid), .string(key)]
        )
        return rows.first.map(mapObject)
    }

    public func getObjectVersion(bucketGuid: String, key: String, version: Int) async throws -> S3ObjectMeta? {
        let rows = try await db.query(
            "SELECT \(top1)* FROM \(t)objects WHERE bucketguid = ? AND objectkey = ? AND version = ?\(limit1)",
            [.string(bucketGuid), .string(key), .int(version)]
        )
        return rows.first.map(mapObject)
    }

    public func getObjectByGuid(_ guid: String) async throws -> S3ObjectMeta? {
        let rows = try await db.query("SELECT \(top1)* FROM \(t)objects WHERE guid = ?\(limit1)", [.string(guid)])
        return rows.first.map(mapObject)
    }

    public func getNextVersion(bucketGuid: String, key: String) async throws -> Int {
        let rows = try await db.query(
            "SELECT COALESCE(MAX(version), 0) AS v FROM \(t)objects WHERE bucketguid = ? AND objectkey = ?",
            [.string(bucketGuid), .string(key)]
        )
        return anyInt(rows.first?["v"] ?? .null) + 1
    }

    public func saveObject(_ obj: S3ObjectMeta) async throws {
        let rows = try await db.query(
            "SELECT COUNT(*) AS cnt FROM \(t)objects WHERE guid = ?", [.string(obj.guid)]
        )
        let exists = anyInt(rows.first?["cnt"] ?? .null) > 0

        if exists {
            try await db.execute(
                "UPDATE \(t)objects SET contenttype=?, contentlength=?, etag=?, md5=?, metadata=?, lastupdateutc=? WHERE guid=?",
                [
                    .string(obj.contentType), .int(obj.contentLength),
                    .string(obj.etag),
                    obj.md5.map { SQLValue.string($0) } ?? .null,
                    obj.metadata.map { SQLValue.string($0) } ?? .null,
                    .string(isoNow()), .string(obj.guid),
                ]
            )
        } else {
            try await db.execute(
                """
                INSERT INTO \(t)objects
                  (guid, bucketguid, ownerguid, authorguid, objectkey, contenttype,
                   contentlength, version, etag, blobfilename, isfolder, deletemarker, md5, metadata, createdutc, lastupdateutc, lastaccessutc)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?)
                """,
                [
                    .string(obj.guid), .string(obj.bucketGuid),
                    .string(obj.ownerGuid), .string(obj.authorGuid),
                    .string(obj.key), .string(obj.contentType),
                    .int(obj.contentLength), .int(obj.version),
                    .string(obj.etag), .string(obj.blobFilename),
                    .int(obj.isFolder ? 1 : 0),
                    obj.md5.map { SQLValue.string($0) } ?? .null,
                    obj.metadata.map { SQLValue.string($0) } ?? .null,
                    .string(obj.createdUtc), .string(obj.createdUtc), .string(obj.createdUtc),
                ]
            )
        }
    }

    public func deleteObjectVersion(guid: String) async throws {
        try await db.execute(
            "UPDATE \(t)objects SET deletemarker = 1, lastupdateutc = ? WHERE guid = ?",
            [.string(isoNow()), .string(guid)]
        )
    }

    public func enumerateObjects(
        bucketGuid: String,
        prefix: String?,
        delimiter: String?,
        startIndex: Int,
        maxKeys: Int
    ) async throws -> (objects: [S3ObjectMeta], prefixes: [String], isTruncated: Bool, nextStartIndex: Int) {
        var sql = "SELECT * FROM \(t)objects WHERE bucketguid = ? AND deletemarker = 0"
        var binds: [SQLValue] = [.string(bucketGuid)]

        if let prefix, !prefix.isEmpty {
            sql += " AND objectkey LIKE ?"
            binds.append(.string("\(prefix)%"))
        }
        sql += " ORDER BY objectkey"

        let rows = try await db.query(sql, binds)
        let all = rows.map(mapObject)

        var objects: [S3ObjectMeta] = []
        var prefixSet = Set<String>()

        for obj in all {
            if let delim = delimiter, !delim.isEmpty {
                let keyAfterPrefix = prefix.map { obj.key.hasPrefix($0) ? String(obj.key.dropFirst($0.count)) : obj.key } ?? obj.key
                if let delimIdx = keyAfterPrefix.range(of: delim) {
                    let commonPrefix = (prefix ?? "") + String(keyAfterPrefix[..<delimIdx.upperBound])
                    prefixSet.insert(commonPrefix)
                    continue
                }
            }
            objects.append(obj)
        }

        let sliced = Array(objects.dropFirst(startIndex))
        let page = Array(sliced.prefix(maxKeys))
        let isTruncated = sliced.count > maxKeys
        let nextStart = isTruncated ? startIndex + maxKeys : 0

        return (page, Array(prefixSet).sorted(), isTruncated, nextStart)
    }

    public func getBucketObjectStats(bucketGuid: String) async throws -> (count: Int, bytes: Int) {
        let rows = try await db.query(
            "SELECT COUNT(*) AS cnt, COALESCE(SUM(contentlength), 0) AS bytes FROM \(t)objects WHERE bucketguid = ? AND deletemarker = 0",
            [.string(bucketGuid)]
        )
        let cnt = anyInt(rows.first?["cnt"] ?? .null)
        let bytes = anyInt(rows.first?["bytes"] ?? .null)
        return (cnt, bytes)
    }

    // MARK: - Universal value helpers (handle SQLite/Postgres/MySQL/MSSQL type differences)

    /// Returns the integer value from any integer SQLValue case (.int, .int8, .int16, .int32, .int64).
    private func anyInt(_ v: SQLValue) -> Int {
        switch v {
        case .int(let n):   return n
        case .int8(let n):  return Int(n)
        case .int16(let n): return Int(n)
        case .int32(let n): return Int(n)
        case .int64(let n): return Int(n)
        default:            return 0
        }
    }

    /// Returns a string from a .string or .date SQLValue.
    private func anyStr(_ v: SQLValue) -> String? {
        switch v {
        case .string(let s): return s.isEmpty ? nil : s
        case .date(let d):
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: d)
        default: return nil
        }
    }

    // MARK: - Mapping helpers

    private func mapUser(_ row: SQLRow) -> S3User {
        S3User(guid: anyStr(row["guid"]) ?? "", name: anyStr(row["name"]) ?? "",
               email: anyStr(row["email"]) ?? "", createdUtc: anyStr(row["createdutc"]) ?? "")
    }

    private func mapCredential(_ row: SQLRow) -> S3Credential {
        S3Credential(guid: anyStr(row["guid"]) ?? "", userGuid: anyStr(row["userguid"]) ?? "",
                     accessKey: anyStr(row["accesskey"]) ?? "", secretKey: anyStr(row["secretkey"]) ?? "",
                     isBase64: anyInt(row["isbase64"]) != 0)
    }

    private func mapBucket(_ row: SQLRow) -> S3Bucket {
        S3Bucket(id: anyInt(row["id"]), guid: anyStr(row["guid"]) ?? "",
                 ownerGuid: anyStr(row["ownerguid"]) ?? "", name: anyStr(row["name"]) ?? "",
                 region: anyStr(row["regionstring"]) ?? "us-west-1",
                 storageType: anyStr(row["storagetype"]) ?? "Disk",
                 diskDirectory: anyStr(row["diskdirectory"]) ?? "",
                 enableVersioning: anyInt(row["enableversioning"]) != 0,
                 enablePublicWrite: anyInt(row["enablepublicwrite"]) != 0,
                 enablePublicRead: anyInt(row["enablepublicread"]) != 0,
                 createdUtc: anyStr(row["createdutc"]) ?? isoNow())
    }

    private func mapObject(_ row: SQLRow) -> S3ObjectMeta {
        S3ObjectMeta(id: anyInt(row["id"]), guid: anyStr(row["guid"]) ?? "",
                     bucketGuid: anyStr(row["bucketguid"]) ?? "",
                     ownerGuid: anyStr(row["ownerguid"]) ?? "",
                     authorGuid: anyStr(row["authorguid"]) ?? "",
                     key: anyStr(row["objectkey"]) ?? "",
                     contentType: anyStr(row["contenttype"]) ?? "application/octet-stream",
                     contentLength: anyInt(row["contentlength"]),
                     version: anyInt(row["version"]),
                     etag: anyStr(row["etag"]) ?? "",
                     blobFilename: anyStr(row["blobfilename"]) ?? "",
                     isFolder: anyInt(row["isfolder"]) != 0,
                     deleteMarker: anyInt(row["deletemarker"]) != 0,
                     md5: anyStr(row["md5"]),
                     metadata: anyStr(row["metadata"]))
    }
}
