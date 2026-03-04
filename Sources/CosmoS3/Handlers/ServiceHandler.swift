import Foundation

public struct ServiceHandler {
    private let da: DataAccess
    private let bucketManager: BucketManager

    public init(da: DataAccess, bucketManager: BucketManager) {
        self.da = da
        self.bucketManager = bucketManager
    }

    public func listBuckets(ctx: S3Context) async throws -> String {
        let user = ctx.user ?? S3User(guid: "default", name: "Default User", email: "", createdUtc: "")
        let buckets = await bucketManager.forUser(user.guid)
        return S3Xml.listBuckets(owner: user, buckets: buckets)
    }
}
