import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Builds S3-compatible XML responses.
public enum S3Xml {
    static let xmlns = "http://s3.amazonaws.com/doc/2006-03-01/"

    // MARK: - ListAllMyBucketsResult

    public static func listBuckets(owner: S3User, buckets: [S3Bucket]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListAllMyBucketsResult xmlns="\(xmlns)">
          <Owner>
            <ID>\(esc(owner.guid))</ID>
            <DisplayName>\(esc(owner.name))</DisplayName>
          </Owner>
          <Buckets>
        """
        for b in buckets {
            xml += """
            \n    <Bucket>
                <Name>\(esc(b.name))</Name>
                <CreationDate>\(b.createdUtc)</CreationDate>
              </Bucket>
        """
        }
        xml += "\n  </Buckets>\n</ListAllMyBucketsResult>"
        return xml
    }

    // MARK: - ListBucketResult

    public static func listObjects(
        bucket: S3Bucket,
        objects: [S3ObjectMeta],
        prefixes: [String],
        prefix: String?,
        delimiter: String?,
        marker: String?,
        maxKeys: Int,
        isTruncated: Bool,
        nextMarker: String?
    ) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult xmlns="\(xmlns)">
          <Name>\(esc(bucket.name))</Name>
          <Prefix>\(esc(prefix ?? ""))</Prefix>
          <Delimiter>\(esc(delimiter ?? ""))</Delimiter>
          <Marker>\(esc(marker ?? ""))</Marker>
          <MaxKeys>\(maxKeys)</MaxKeys>
          <IsTruncated>\(isTruncated)</IsTruncated>
        """
        if isTruncated, let nm = nextMarker {
            xml += "  <NextMarker>\(esc(nm))</NextMarker>\n"
        }
        for obj in objects {
            xml += """
            \n  <Contents>
                <Key>\(esc(obj.key))</Key>
                <LastModified>\(obj.lastUpdateUtc)</LastModified>
                <ETag>&quot;\(esc(obj.etag))&quot;</ETag>
                <Size>\(obj.contentLength)</Size>
                <StorageClass>STANDARD</StorageClass>
              </Contents>
            """
        }
        for p in prefixes {
            xml += "\n  <CommonPrefixes><Prefix>\(esc(p))</Prefix></CommonPrefixes>"
        }
        xml += "\n</ListBucketResult>"
        return xml
    }

    // MARK: - Error

    public static func error(code: String, message: String, resource: String = "", requestId: String = "cosmo") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Error>
          <Code>\(esc(code))</Code>
          <Message>\(esc(message))</Message>
          <Resource>\(esc(resource))</Resource>
          <RequestId>\(esc(requestId))</RequestId>
        </Error>
        """
    }

    // MARK: - DeleteResult

    public static func deleteResult(deleted: [(key: String, versionId: Int?)], errors: [(key: String, code: String, message: String)]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<DeleteResult xmlns=\"\(xmlns)\">"
        for d in deleted {
            xml += "\n  <Deleted><Key>\(esc(d.key))</Key>"
            if let v = d.versionId { xml += "<VersionId>\(v)</VersionId>" }
            xml += "</Deleted>"
        }
        for e in errors {
            xml += "\n  <Error><Key>\(esc(e.key))</Key><Code>\(esc(e.code))</Code><Message>\(esc(e.message))</Message></Error>"
        }
        xml += "\n</DeleteResult>"
        return xml
    }

    // MARK: - InitiateMultipartUploadResult

    public static func initiateMultipart(bucket: String, key: String, uploadId: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <InitiateMultipartUploadResult xmlns="\(xmlns)">
          <Bucket>\(esc(bucket))</Bucket>
          <Key>\(esc(key))</Key>
          <UploadId>\(esc(uploadId))</UploadId>
        </InitiateMultipartUploadResult>
        """
    }

    // MARK: - CompleteMultipartUploadResult

    public static func completeMultipart(bucket: String, key: String, etag: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <CompleteMultipartUploadResult xmlns="\(xmlns)">
          <Bucket>\(esc(bucket))</Bucket>
          <Key>\(esc(key))</Key>
          <ETag>&quot;\(esc(etag))&quot;</ETag>
        </CompleteMultipartUploadResult>
        """
    }

    // MARK: - CopyObjectResult

    public static func copyObject(lastModified: String, etag: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <CopyObjectResult xmlns="\(xmlns)">
          <LastModified>\(lastModified)</LastModified>
          <ETag>&quot;\(esc(etag))&quot;</ETag>
        </CopyObjectResult>
        """
    }

    // MARK: - Helpers

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - XML Parser (for request bodies)

/// Parses simple S3 XML request bodies (Delete, Tags, etc.)
public final class S3XmlParser: NSObject, XMLParserDelegate {
    private var result: [[String: String]] = []
    private var current: [String: String] = [:]
    private var currentElement = ""
    private var currentValue = ""
    private let itemTag: String
    private let fields: [String]

    public init(itemTag: String, fields: [String]) {
        self.itemTag = itemTag
        self.fields = fields
    }

    public func parse(data: Data) -> [[String: String]] {
        result = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?,
                       attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""
        if elementName == itemTag { current = [:] }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?) {
        if fields.contains(elementName) {
            current[elementName] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == itemTag { result.append(current) }
        currentValue = ""
    }
}
