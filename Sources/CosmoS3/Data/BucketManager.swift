import Foundation

/// Thread-safe in-memory bucket cache, backed by DataAccess for persistence.
public actor BucketManager {
    private var buckets: [String: S3Bucket] = [:]   // keyed by name
    private let da: DataAccess

    public init(da: DataAccess) {
        self.da = da
    }

    public func load() async throws {
        let all = try await da.getBuckets()
        buckets = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
        print("[CosmoS3] BucketManager loaded \(buckets.count) bucket(s)")
    }

    public func get(name: String) -> S3Bucket? {
        buckets[name]
    }

    public func all() -> [S3Bucket] {
        Array(buckets.values).sorted { $0.name < $1.name }
    }

    public func forUser(_ userGuid: String) -> [S3Bucket] {
        buckets.values.filter { $0.ownerGuid == userGuid }.sorted { $0.name < $1.name }
    }

    public func add(_ bucket: S3Bucket) async throws {
        try await da.addBucket(bucket)
        buckets[bucket.name] = bucket
    }

    public func remove(name: String) async throws {
        guard let bucket = buckets[name] else { return }
        try await da.deleteBucket(guid: bucket.guid)
        buckets.removeValue(forKey: name)
    }
}
