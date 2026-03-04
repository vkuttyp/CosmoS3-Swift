import XCTest
import CosmoApiServer
@testable import CosmoS3

final class S3RequestParserTests: XCTestCase {
    func testListBuckets() {
        let http = makeContext(method: "GET", path: "/")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .listBuckets)
        XCTAssertNil(req.bucket)
    }

    func testBucketRead() {
        let http = makeContext(method: "GET", path: "/my-bucket")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .bucketRead)
        XCTAssertEqual(req.bucket, "my-bucket")
    }

    func testObjectWrite() {
        let http = makeContext(method: "PUT", path: "/my-bucket/path/to/object.txt")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .objectWrite)
        XCTAssertEqual(req.bucket, "my-bucket")
        XCTAssertEqual(req.key, "path/to/object.txt")
    }

    func testObjectRead() {
        let http = makeContext(method: "GET", path: "/bucket/key.json")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .objectRead)
        XCTAssertEqual(req.key, "key.json")
    }

    func testBucketExists() {
        let http = makeContext(method: "HEAD", path: "/my-bucket")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .bucketExists)
    }

    func testObjectDelete() {
        let http = makeContext(method: "DELETE", path: "/bucket/file.txt")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .objectDelete)
    }

    func testDeleteMultiple() {
        let http = makeContext(method: "POST", path: "/bucket", query: "delete")
        let req = S3RequestParser.parse(http: http)
        XCTAssertEqual(req.requestType, .objectDeleteMultiple)
    }

    // MARK: - Helpers

    private func makeContext(method: String, path: String, query: String = "") -> HttpContext {
        let m = HttpMethod(rawValue: method) ?? .get
        let req = HttpRequest(method: m, path: path, queryString: query)
        return HttpContext(request: req)
    }
}

final class S3XmlTests: XCTestCase {
    func testListBuckets() {
        let owner = S3User(guid: "u1", name: "Alice", email: "a@b.com", createdUtc: "2024-01-01T00:00:00Z")
        let bucket = S3Bucket(ownerGuid: "u1", name: "test-bucket", diskDirectory: "/tmp")
        let xml = S3Xml.listBuckets(owner: owner, buckets: [bucket])
        XCTAssertTrue(xml.contains("<Name>test-bucket</Name>"))
        XCTAssertTrue(xml.contains("<DisplayName>Alice</DisplayName>"))
    }

    func testErrorXml() {
        let xml = S3Xml.error(code: "NoSuchBucket", message: "Bucket not found")
        XCTAssertTrue(xml.contains("<Code>NoSuchBucket</Code>"))
        XCTAssertTrue(xml.contains("<Message>Bucket not found</Message>"))
    }

    func testXmlParserDeleteItems() {
        let xml = """
        <Delete><Object><Key>file1.txt</Key></Object><Object><Key>file2.txt</Key><VersionId>2</VersionId></Object></Delete>
        """.data(using: .utf8)!
        let parser = S3XmlParser(itemTag: "Object", fields: ["Key", "VersionId"])
        let items = parser.parse(data: xml)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["Key"], "file1.txt")
        XCTAssertEqual(items[1]["VersionId"], "2")
    }
}

// MARK: - Presigned URL tests

final class PresignedUrlTests: XCTestCase {
    func testPresignedGetUrl() {
        let gen = PresignedUrlGenerator(host: "127.0.0.1:18001", region: "us-east-1")
        let url = gen.presign(method: "GET", bucket: "my-bucket", key: "photo.jpg",
                              accessKey: "AKID", secretKey: "SECRET", expiresIn: 3600)
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("http://127.0.0.1:18001/my-bucket/photo.jpg?"))
        XCTAssertTrue(s.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"))
        XCTAssertTrue(s.contains("X-Amz-Credential=AKID"))
        XCTAssertTrue(s.contains("X-Amz-Expires=3600"))
        XCTAssertTrue(s.contains("X-Amz-SignedHeaders=host"))
        XCTAssertTrue(s.contains("X-Amz-Signature="))
    }

    func testPresignedPutUrl() {
        let gen = PresignedUrlGenerator(host: "s3.example.com", region: "eu-west-1")
        let url = gen.presign(method: "PUT", bucket: "uploads", key: "video.mp4",
                              accessKey: "KEY1", secretKey: "SKEY", expiresIn: 900)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("/uploads/video.mp4"))
    }

    func testPresignedUrlHasNoAuthHeader() {
        // The URL must NOT contain X-Amz-Signature in the path itself
        let gen = PresignedUrlGenerator(host: "localhost:18001")
        let url = gen.presign(method: "GET", bucket: "b", key: "k",
                              accessKey: "A", secretKey: "S", expiresIn: 60)!
        // Signature must be in the query string only
        XCTAssertTrue(url.query?.contains("X-Amz-Signature=") == true)
        XCTAssertNil(url.path.range(of: "X-Amz-Signature"))
    }

    func testPresignedExtraQueryParams() {
        let gen = PresignedUrlGenerator(host: "localhost", region: "us-east-1")
        let url = gen.presign(method: "GET", bucket: "b", key: "k",
                              accessKey: "A", secretKey: "S",
                              extraQuery: ["versionId": "5"])
        XCTAssertTrue(url?.query?.contains("versionId=5") == true)
    }
}
