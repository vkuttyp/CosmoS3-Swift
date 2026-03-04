import Foundation
import CosmoApiServer

// MARK: - S3RequestType

public enum S3RequestType: Sendable {
    // Service
    case listBuckets
    // Bucket
    case bucketExists, bucketCreate, bucketRead, bucketDelete
    case bucketAclRead, bucketAclWrite
    case bucketTagRead, bucketTagWrite, bucketTagDelete
    case bucketVersioningRead, bucketVersioningWrite
    case bucketMultipartList
    // Object
    case objectExists, objectRead, objectWrite, objectDelete
    case objectAclRead, objectAclWrite
    case objectTagRead, objectTagWrite, objectTagDelete
    case objectMultipartCreate, objectMultipartUpload, objectMultipartComplete, objectMultipartAbort, objectMultipartListParts
    case objectDeleteMultiple
    case objectCopy
    case unknown
}

// MARK: - S3Request

public struct S3Request: Sendable {
    public let bucket: String?
    public let key: String?
    public let requestType: S3RequestType
    public let queryItems: [String: String]
    public let headers: [String: String]
    public let body: Data
    public let accessKey: String?
    public let authorization: String?
    public let signatureVersion: Int  // 2 or 4
    public let isPresigned: Bool
    public let rangeStart: Int?
    public let rangeEnd: Int?

    public var prefix: String? { queryItems["prefix"] }
    public var delimiter: String? { queryItems["delimiter"] }
    public var marker: String? { queryItems["marker"] ?? queryItems["continuation-token"] }
    public var maxKeys: Int { Int(queryItems["max-keys"] ?? "1000") ?? 1000 }
    public var versionId: Int? { queryItems["versionId"].flatMap(Int.init) }
    public var uploadId: String? { queryItems["uploadId"] }
    public var partNumber: Int? { queryItems["partNumber"].flatMap(Int.init) }

    public init(
        bucket: String?, key: String?, requestType: S3RequestType,
        queryItems: [String: String], headers: [String: String], body: Data,
        accessKey: String?, authorization: String?, signatureVersion: Int,
        isPresigned: Bool, rangeStart: Int?, rangeEnd: Int?
    ) {
        self.bucket = bucket; self.key = key; self.requestType = requestType
        self.queryItems = queryItems; self.headers = headers; self.body = body
        self.accessKey = accessKey; self.authorization = authorization
        self.signatureVersion = signatureVersion; self.isPresigned = isPresigned
        self.rangeStart = rangeStart; self.rangeEnd = rangeEnd
    }
}

// MARK: - S3Context

public final class S3Context: @unchecked Sendable {
    public let http: HttpContext
    public let s3Request: S3Request
    public var bucket: S3Bucket?
    public var user: S3User?
    public var credential: S3Credential?

    public init(http: HttpContext, s3Request: S3Request) {
        self.http = http
        self.s3Request = s3Request
    }
}

// MARK: - S3RequestParser

struct S3RequestParser {
    static func parse(http: HttpContext) -> S3Request {
        let req = http.request
        let query = req.query
        let headers = req.headers
        let path = req.path   // e.g. /bucket/key or /

        // Extract bucket and key from path-style URL
        var pathParts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let bucket = pathParts.isEmpty ? nil : pathParts.removeFirst()
        let key = pathParts.isEmpty ? nil : pathParts.joined(separator: "/")

        // Authorization
        let auth = headers["authorization"]
        let accessKey = extractAccessKey(from: auth, query: query)
        let sigVersion = (auth?.contains("AWS4-HMAC-SHA256") == true || query["X-Amz-Algorithm"] != nil) ? 4 : 2
        let isPresigned = query["X-Amz-Signature"] != nil || query["Signature"] != nil

        // Range
        var rangeStart: Int? = nil
        var rangeEnd: Int? = nil
        if let rangeHeader = headers["range"] {
            parseRange(rangeHeader, start: &rangeStart, end: &rangeEnd)
        }

        // Request type
        let requestType = classifyRequest(
            method: req.method, bucket: bucket, key: key, query: query,
            headers: headers
        )

        return S3Request(
            bucket: bucket, key: key, requestType: requestType,
            queryItems: query, headers: headers, body: req.body,
            accessKey: accessKey, authorization: auth, signatureVersion: sigVersion,
            isPresigned: isPresigned, rangeStart: rangeStart, rangeEnd: rangeEnd
        )
    }

    private static func extractAccessKey(from auth: String?, query: [String: String]) -> String? {
        if let auth {
            // SigV4: AWS4-HMAC-SHA256 Credential=ACCESS/...
            if let credRange = auth.range(of: "Credential=") {
                let rest = auth[credRange.upperBound...]
                return rest.components(separatedBy: "/").first.map { String($0) }
            }
            // SigV2: AWS ACCESS:signature
            if let awsRange = auth.range(of: "AWS ") {
                let rest = auth[awsRange.upperBound...]
                return rest.components(separatedBy: ":").first.map { String($0) }
            }
        }
        return query["AWSAccessKeyId"] ?? query["X-Amz-Credential"]?.components(separatedBy: "/").first
    }

    private static func parseRange(_ header: String, start: inout Int?, end: inout Int?) {
        // bytes=0-1023
        guard header.lowercased().hasPrefix("bytes=") else { return }
        let range = String(header.dropFirst(6))
        let parts = range.split(separator: "-")
        if parts.count == 2 {
            start = Int(parts[0])
            end = Int(parts[1])
        } else if parts.count == 1 && header.hasSuffix("-") {
            start = Int(parts[0])
        }
    }

    private static func classifyRequest(
        method: HttpMethod, bucket: String?, key: String?,
        query: [String: String], headers: [String: String]
    ) -> S3RequestType {
        guard let bucket else { return method == .get ? .listBuckets : .unknown }

        if let key {
            // Object-level
            switch method {
            case .head: return .objectExists
            case .get:
                if query["uploadId"] != nil && query["partNumber"] == nil { return .objectMultipartListParts }
                return .objectRead
            case .put:
                if query.keys.contains("acl") { return .objectAclWrite }
                if query.keys.contains("tagging") { return .objectTagWrite }
                if query["uploadId"] != nil { return .objectMultipartUpload }
                if headers["x-amz-copy-source"] != nil { return .objectCopy }
                return .objectWrite
            case .post:
                if query.keys.contains("delete") { return .objectDeleteMultiple }
                if let uploadId = query["uploadId"], !uploadId.isEmpty { return .objectMultipartComplete }
                if query.keys.contains("uploads") { return .objectMultipartCreate }
                return .unknown
            case .delete:
                if query["uploadId"] != nil { return .objectMultipartAbort }
                if query.keys.contains("tagging") { return .objectTagDelete }
                return .objectDelete
            default: return .unknown
            }
        } else {
            // Bucket-level
            switch method {
            case .head: return .bucketExists
            case .get:
                if query.keys.contains("acl")        { return .bucketAclRead }
                if query.keys.contains("tagging")     { return .bucketTagRead }
                if query.keys.contains("versioning")  { return .bucketVersioningRead }
                if query.keys.contains("uploads")     { return .bucketMultipartList }
                return .bucketRead   // list objects
            case .put:
                if query.keys.contains("acl")        { return .bucketAclWrite }
                if query.keys.contains("tagging")     { return .bucketTagWrite }
                if query.keys.contains("versioning")  { return .bucketVersioningWrite }
                return .bucketCreate
            case .post:
                if query.keys.contains("delete") { return .objectDeleteMultiple }
                return .unknown
            case .delete:
                if query.keys.contains("tagging") { return .bucketTagDelete }
                return .bucketDelete
            default: return .unknown
            }
        }
    }
}
