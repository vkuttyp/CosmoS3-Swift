import Foundation
import CosmoApiServer

/// S3Middleware: intercepts all HTTP requests, parses S3 semantics,
/// authenticates, and dispatches to the appropriate handler.
public final class S3Middleware: Middleware {
    private let da: DataAccess
    private let bucketManager: BucketManager
    private let authManager: AuthManager
    private let serviceHandler: ServiceHandler
    private let bucketHandler: BucketHandler
    private let objectHandler: ObjectHandler
    private let requireAuth: Bool

    public init(
        da: DataAccess,
        bucketManager: BucketManager,
        storageBaseDir: String,
        requireAuth: Bool = false
    ) {
        self.da = da
        self.bucketManager = bucketManager
        self.authManager = AuthManager(da: da)
        self.serviceHandler = ServiceHandler(da: da, bucketManager: bucketManager)
        self.bucketHandler = BucketHandler(da: da, bucketManager: bucketManager, storageBaseDir: storageBaseDir)
        self.objectHandler = ObjectHandler(da: da, bucketManager: bucketManager, storageBaseDir: storageBaseDir)
        self.requireAuth = requireAuth
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let s3req = S3RequestParser.parse(http: context)
        let ctx = S3Context(http: context, s3Request: s3req)

        // Authentication
        if let creds = await authManager.authenticate(s3req: s3req) {
            ctx.user = creds.user
            ctx.credential = creds.credential
        } else if requireAuth {
            sendError(context, error: S3Error.authenticationRequired)
            return
        }

        do {
            try await dispatch(ctx: ctx)
        } catch let s3err as S3Error {
            sendError(context, error: s3err)
        } catch {
            sendError(context, code: "InternalError", message: error.localizedDescription, status: 500)
        }
    }

    // MARK: - Dispatch

    private func dispatch(ctx: S3Context) async throws {
        switch ctx.s3Request.requestType {
        // Service
        case .listBuckets:
            let xml = try await serviceHandler.listBuckets(ctx: ctx)
            sendXml(ctx.http, xml)

        // Bucket
        case .bucketExists:
            try await bucketHandler.exists(ctx: ctx)

        case .bucketCreate:
            try await bucketHandler.create(ctx: ctx)

        case .bucketRead:
            let xml = try await bucketHandler.listObjects(ctx: ctx)
            sendXml(ctx.http, xml)

        case .bucketDelete:
            try await bucketHandler.delete(ctx: ctx)

        // Object
        case .objectExists:
            try await objectHandler.head(ctx: ctx)

        case .objectWrite:
            try await objectHandler.write(ctx: ctx)

        case .objectRead:
            try await objectHandler.read(ctx: ctx)

        case .objectDelete:
            try await objectHandler.delete(ctx: ctx)

        case .objectDeleteMultiple:
            try await objectHandler.deleteMultiple(ctx: ctx)

        // Unsupported (return 501 stub — implement as needed)
        case .bucketAclRead, .bucketAclWrite:
            ctx.http.response.setStatus(200)
            sendXml(ctx.http, """
                <?xml version="1.0"?><AccessControlPolicy xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>default</ID><DisplayName>Default User</DisplayName></Owner><AccessControlList><Grant><Grantee xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="CanonicalUser"><ID>default</ID><DisplayName>Default User</DisplayName></Grantee><Permission>FULL_CONTROL</Permission></Grant></AccessControlList></AccessControlPolicy>
                """)

        case .bucketTagRead, .objectTagRead:
            sendXml(ctx.http, "<Tagging><TagSet></TagSet></Tagging>")

        case .bucketTagWrite, .bucketTagDelete, .objectTagWrite, .objectTagDelete:
            ctx.http.response.setStatus(204)

        case .bucketVersioningRead:
            sendXml(ctx.http, "<VersioningConfiguration xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"/>")

        case .bucketVersioningWrite:
            ctx.http.response.setStatus(200)

        default:
            ctx.http.response.setStatus(501)
            sendXml(ctx.http, S3Xml.error(code: "NotImplemented", message: "Operation not yet implemented."))
        }
    }

    // MARK: - Helpers

    private func sendXml(_ ctx: HttpContext, _ xml: String) {
        ctx.response.headers["Content-Type"] = "application/xml"
        ctx.response.writeText(xml, contentType: "application/xml")
    }

    private func sendError(_ ctx: HttpContext, error: S3Error) {
        ctx.response.setStatus(error.httpStatus)
        let xml = S3Xml.error(code: error.code, message: error.message)
        ctx.response.headers["Content-Type"] = "application/xml"
        ctx.response.writeText(xml, contentType: "application/xml")
    }

    private func sendError(_ ctx: HttpContext, code: String, message: String, status: Int) {
        ctx.response.setStatus(status)
        let xml = S3Xml.error(code: code, message: message)
        ctx.response.headers["Content-Type"] = "application/xml"
        ctx.response.writeText(xml, contentType: "application/xml")
    }
}

// MARK: - CosmoWebApplicationBuilder extension

extension CosmoWebApplicationBuilder {
    /// Adds the S3 middleware to handle all S3-compatible requests.
    @discardableResult
    public func useCosmoS3(
        da: DataAccess,
        bucketManager: BucketManager,
        storageBaseDir: String,
        requireAuth: Bool = false
    ) -> Self {
        useMiddleware(S3Middleware(
            da: da,
            bucketManager: bucketManager,
            storageBaseDir: storageBaseDir,
            requireAuth: requireAuth
        ))
    }
}
