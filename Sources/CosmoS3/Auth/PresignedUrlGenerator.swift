import Foundation
import Crypto

/// Generates SigV4 presigned URLs for GET and PUT object operations.
///
/// A presigned URL embeds authentication in query parameters, allowing unauthenticated
/// clients to download or upload objects without needing AWS credentials.
///
/// Usage:
/// ```swift
/// let gen = PresignedUrlGenerator(host: "s3.example.com", region: "us-east-1", service: "s3")
/// let url = gen.presign(
///     method: "GET", bucket: "my-bucket", key: "photo.jpg",
///     accessKey: "AKID", secretKey: "SECRET", expiresIn: 3600
/// )
/// ```
public struct PresignedUrlGenerator: Sendable {
    private let host: String
    private let region: String
    private let service: String
    private let scheme: String

    public init(host: String, region: String = "us-east-1", service: String = "s3", scheme: String = "http") {
        self.host = host
        self.region = region
        self.service = service
        self.scheme = scheme
    }

    /// Returns a SigV4 presigned URL.
    /// - Parameters:
    ///   - method:     HTTP method (GET / PUT / DELETE).
    ///   - bucket:     Bucket name.
    ///   - key:        Object key.
    ///   - accessKey:  Credential access key.
    ///   - secretKey:  Credential secret key.
    ///   - expiresIn:  Validity in seconds (max 604800 = 7 days per AWS spec).
    ///   - extraQuery: Additional query parameters (e.g. versionId).
    public func presign(
        method: String,
        bucket: String,
        key: String,
        accessKey: String,
        secretKey: String,
        expiresIn: Int = 900,
        extraQuery: [String: String] = [:]
    ) -> URL? {
        let now = Date()
        let datetime = isoDatetime(now)
        let dateStr = String(datetime.prefix(8))
        let credentialScope = "\(dateStr)/\(region)/\(service)/aws4_request"
        let credential = "\(accessKey)/\(credentialScope)"
        let canonicalURI = "/\(bucket)/\(key)"

        // Build query string (sorted per SigV4 spec)
        var query: [String: String] = extraQuery
        query["X-Amz-Algorithm"]  = "AWS4-HMAC-SHA256"
        query["X-Amz-Credential"] = credential
        query["X-Amz-Date"]       = datetime
        query["X-Amz-Expires"]    = String(expiresIn)
        query["X-Amz-SignedHeaders"] = "host"

        let canonicalQS = query.sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")

        // Canonical request — body hash is UNSIGNED-PAYLOAD for presigned URLs
        let canonicalRequest = [
            method.uppercased(),
            canonicalURI,
            canonicalQS,
            "host:\(host)\n",   // canonical headers
            "host",             // signed headers
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        // String to sign
        let strToSign = [
            "AWS4-HMAC-SHA256",
            datetime,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        // Signing key + signature
        let signingKey = deriveSigningKey(secret: secretKey, date: dateStr, region: region, service: service)
        let signature = hmacSHA256Hex(key: signingKey, data: Data(strToSign.utf8))

        // Final URL
        let queryWithSig = canonicalQS + "&X-Amz-Signature=\(signature)"
        let urlString = "\(scheme)://\(host)\(canonicalURI)?\(queryWithSig)"
        return URL(string: urlString)
    }

    // MARK: - Crypto helpers (mirrors AuthManager internals)

    private func isoDatetime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private func encode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private func hmacSHA256Hex(key: Data, data: Data) -> String {
        hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func deriveSigningKey(secret: String, date: String, region: String, service: String) -> Data {
        let kDate    = hmacSHA256(key: Data("AWS4\(secret)".utf8), data: Data(date.utf8))
        let kRegion  = hmacSHA256(key: kDate,    data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion,  data: Data(service.utf8))
        return hmacSHA256(key: kService, data: Data("aws4_request".utf8))
    }
}
