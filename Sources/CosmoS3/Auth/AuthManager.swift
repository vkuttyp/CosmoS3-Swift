import Foundation
import Crypto

/// SigV4 / SigV2 authentication manager.
public final class AuthManager: @unchecked Sendable {
    private let da: DataAccess

    public init(da: DataAccess) {
        self.da = da
    }

    /// Returns (user, credential) if authentication succeeds, nil otherwise.
    public func authenticate(s3req: S3Request) async -> (user: S3User, credential: S3Credential)? {
        guard let accessKey = s3req.accessKey, !accessKey.isEmpty else {
            return nil
        }
        guard let cred = try? await da.getCredentialByAccessKey(accessKey),
              let user = try? await da.getUser(guid: cred.userGuid) else {
            return nil
        }
        // Signature validation
        let isValid: Bool
        if s3req.isPresigned {
            isValid = validatePresigned(s3req: s3req, credential: cred)
        } else if s3req.signatureVersion == 4 {
            isValid = validateSigV4(s3req: s3req, credential: cred)
        } else {
            isValid = validateSigV2(s3req: s3req, credential: cred)
        }
        guard isValid else { return nil }
        return (user, cred)
    }

    // MARK: - Presigned URL validation

    private func validatePresigned(s3req: S3Request, credential: S3Credential) -> Bool {
        let q = s3req.queryItems

        // SigV4 presigned (X-Amz-Signature)
        if let providedSig = q["X-Amz-Signature"] {
            return validatePresignedV4(s3req: s3req, credential: credential, providedSig: providedSig)
        }
        // SigV2 presigned (Signature + Expires)
        if let providedSig = q["Signature"] {
            return validatePresignedV2(s3req: s3req, credential: credential, providedSig: providedSig)
        }
        return false
    }

    private func validatePresignedV4(s3req: S3Request, credential: S3Credential, providedSig: String) -> Bool {
        let q = s3req.queryItems
        guard let credParam = q["X-Amz-Credential"],
              let datetime  = q["X-Amz-Date"],
              let expiresStr = q["X-Amz-Expires"],
              let expires = Int(expiresStr),
              let signedHeadersStr = q["X-Amz-SignedHeaders"] else { return false }

        // Check expiry
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        isoFmt.timeZone = TimeZone(identifier: "UTC")
        guard let signedAt = isoFmt.date(from: datetime) else { return false }
        guard Date() <= signedAt.addingTimeInterval(TimeInterval(expires)) else { return false }

        // Extract scope
        let credParts = credParam.components(separatedBy: "/")
        guard credParts.count >= 5 else { return false }
        let dateStr = credParts[1]
        let region  = credParts[2]
        let service = credParts[3]

        // Rebuild canonical query string WITHOUT X-Amz-Signature
        let canonicalQS = q
            .filter { $0.key != "X-Amz-Signature" }
            .sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")

        // Canonical headers (only signed headers, for presigned = "host")
        let signedHeaderNames = signedHeadersStr.components(separatedBy: ";")
        let canonicalHeaders = buildCanonicalHeaders(headers: s3req.headers, names: signedHeaderNames)

        // Canonical request — body hash is UNSIGNED-PAYLOAD
        let method = methodString(s3req: s3req)
        let canonicalURI = canonicalizeURI(s3req: s3req)
        let canonicalRequest = [method, canonicalURI, canonicalQS, canonicalHeaders, signedHeadersStr, "UNSIGNED-PAYLOAD"]
            .joined(separator: "\n")

        // String to sign
        let credScope = "\(dateStr)/\(region)/\(service)/aws4_request"
        let strToSign = "AWS4-HMAC-SHA256\n\(datetime)\n\(credScope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"

        let signingKey = deriveSigningKey(secret: credential.secretKey, date: dateStr, region: region, service: service)
        return hmacSHA256Hex(key: signingKey, data: Data(strToSign.utf8)) == providedSig
    }

    private func validatePresignedV2(s3req: S3Request, credential: S3Credential, providedSig: String) -> Bool {
        let q = s3req.queryItems
        guard let expiresStr = q["Expires"],
              let expires = TimeInterval(expiresStr) else { return false }

        // Check expiry
        guard Date() <= Date(timeIntervalSince1970: expires) else { return false }

        // StringToSign for presigned v2: METHOD\n\nContentType\nExpires\nResource
        let contentType = s3req.headers["content-type"] ?? ""
        let resource = buildCanonicalResource(s3req: s3req)
        let stringToSign = "\(methodString(s3req: s3req))\n\n\(contentType)\n\(expiresStr)\n\(resource)"
        return hmacSHA1Base64(key: credential.secretKey, data: stringToSign) == providedSig
    }

    // MARK: - SigV4

    private func validateSigV4(s3req: S3Request, credential: S3Credential) -> Bool {
        guard let auth = s3req.authorization,
              let signatureRange = auth.range(of: "Signature=") else { return false }
        let providedSig = String(auth[signatureRange.upperBound...])
            .components(separatedBy: ",").first ?? ""

        // Extract signing metadata from Authorization header
        guard let credentialRange = auth.range(of: "Credential=") else { return false }
        let credentialPart = String(auth[credentialRange.upperBound...])
            .components(separatedBy: ",").first ?? ""
        let credParts = credentialPart.components(separatedBy: "/")
        guard credParts.count >= 5 else { return false }
        let dateStr = credParts[1]   // YYYYMMDD
        let region = credParts[2]
        let service = credParts[3]

        // Extract signed headers
        guard let shRange = auth.range(of: "SignedHeaders=") else { return false }
        let signedHeadersStr = String(auth[shRange.upperBound...])
            .components(separatedBy: ",").first ?? ""

        // Build canonical request
        let method = s3req.headers["x-http-method"] ?? methodString(s3req: s3req)
        let canonicalURI = canonicalizeURI(s3req: s3req)
        let canonicalQS = canonicalizeQueryString(query: s3req.queryItems)
        let signedHeaderNames = signedHeadersStr.components(separatedBy: ";")
        let canonicalHeaders = buildCanonicalHeaders(headers: s3req.headers, names: signedHeaderNames)
        let bodyHash = s3req.headers["x-amz-content-sha256"] ?? sha256Hex(s3req.body)

        let canonicalRequest = [method, canonicalURI, canonicalQS, canonicalHeaders, signedHeadersStr, bodyHash]
            .joined(separator: "\n")

        // String to sign
        let datetime = s3req.headers["x-amz-date"] ?? "\(dateStr)T000000Z"
        let credScope = "\(dateStr)/\(region)/\(service)/aws4_request"
        let strToSign = "AWS4-HMAC-SHA256\n\(datetime)\n\(credScope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"

        // Signing key
        let signingKey = deriveSigningKey(secret: credential.secretKey, date: dateStr, region: region, service: service)
        let computedSig = hmacSHA256Hex(key: signingKey, data: Data(strToSign.utf8))

        return computedSig == providedSig
    }

    // MARK: - SigV2

    private func validateSigV2(s3req: S3Request, credential: S3Credential) -> Bool {
        guard let auth = s3req.authorization else { return false }
        // AWS ACCESS:BASE64(HMAC-SHA1(StringToSign, secret))
        let parts = auth.components(separatedBy: " ")
        guard parts.count == 2 else { return false }
        let sigPart = parts[1].components(separatedBy: ":")
        guard sigPart.count == 2 else { return false }
        let providedSig = sigPart[1]

        let date = s3req.headers["date"] ?? s3req.headers["x-amz-date"] ?? ""
        let contentType = s3req.headers["content-type"] ?? ""
        let contentMD5 = s3req.headers["content-md5"] ?? ""
        let resource = buildCanonicalResource(s3req: s3req)

        let stringToSign = "\(methodString(s3req: s3req))\n\(contentMD5)\n\(contentType)\n\(date)\n\(resource)"
        let computedSig = hmacSHA1Base64(key: credential.secretKey, data: stringToSign)

        return computedSig == providedSig
    }

    // MARK: - Helpers

    private func methodString(s3req: S3Request) -> String {
        // infer from request type
        switch s3req.requestType {
        case .listBuckets, .bucketRead, .objectRead, .bucketExists, .objectExists,
             .bucketAclRead, .bucketTagRead, .bucketVersioningRead, .objectAclRead, .objectTagRead,
             .bucketMultipartList, .objectMultipartListParts:
            return "GET"
        case .bucketCreate, .objectWrite, .objectCopy, .bucketAclWrite, .bucketTagWrite,
             .bucketVersioningWrite, .objectAclWrite, .objectTagWrite, .objectMultipartUpload:
            return "PUT"
        case .bucketDelete, .objectDelete, .bucketTagDelete, .objectTagDelete, .objectMultipartAbort:
            return "DELETE"
        case .objectDeleteMultiple, .objectMultipartCreate, .objectMultipartComplete:
            return "POST"
        default:
            return "GET"
        }
    }

    private func canonicalizeURI(_ path: String) -> String {
        "/" + path.split(separator: "/").map { seg in
            seg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(seg)
        }.joined(separator: "/")
    }

    private func canonicalizeURI(s3req: S3Request) -> String {
        var parts: [String] = []
        if let b = s3req.bucket { parts.append(b) }
        if let k = s3req.key { parts.append(k) }
        return "/" + parts.joined(separator: "/")
    }

    private func canonicalizeQueryString(query: [String: String]) -> String {
        query.sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
    }

    private func buildCanonicalHeaders(headers: [String: String], names: [String]) -> String {
        names.sorted().map { name in
            let val = headers[name]?.trimmingCharacters(in: .whitespaces) ?? ""
            return "\(name):\(val)\n"
        }.joined()
    }

    private func buildCanonicalResource(s3req: S3Request) -> String {
        var r = "/"
        if let b = s3req.bucket { r += b }
        if let k = s3req.key { r += "/\(k)" }
        return r
    }

    private func encode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let authCode = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(authCode)
    }

    private func hmacSHA256Hex(key: Data, data: Data) -> String {
        hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func deriveSigningKey(secret: String, date: String, region: String, service: String) -> Data {
        let kDate    = hmacSHA256(key: Data("AWS4\(secret)".utf8), data: Data(date.utf8))
        let kRegion  = hmacSHA256(key: kDate,    data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion,  data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    private func hmacSHA1Base64(key: String, data: String) -> String {
        let keyData = Data(key.utf8)
        let msgData = Data(data.utf8)
        let authCode = HMAC<Insecure.SHA1>.authenticationCode(for: msgData, using: SymmetricKey(data: keyData))
        return Data(authCode).base64EncodedString()
    }
}
