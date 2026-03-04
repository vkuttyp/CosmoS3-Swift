# CosmoS3-Swift

An S3-compatible object storage server written in Swift, built on top of [CosmoApiServer-Swift](https://github.com/vkuttyp/CosmoApiServer-Swift).

## Features

- **Full S3 API compatibility** — bucket CRUD, object CRUD, multipart upload, bulk delete, versioning
- **SigV4 + SigV2 authentication** using swift-crypto
- **SQLite backend** via [CosmoSQLClient-Swift](https://github.com/vkuttyp/CosmoSQLClient-Swift) (Postgres, MySQL, SQL Server coming soon)
- **Disk-based blob storage** — blobs stored on local filesystem, metadata in SQL
- **Cross-platform** — macOS + Linux

## Running the Host

```bash
swift run CosmoS3Host
```

The server listens on port **18001** by default. Configuration is via `appsettings.json`:

```json
{
  "port": 18001,
  "storageBaseDir": "./disk",
  "requireAuth": false,
  "logging": true,
  "cors": true,
  "database": {
    "type": "sqlite",
    "connectionString": "./cosmos3.db"
  }
}
```

## Using with AWS SDK

Point any AWS S3 SDK at `http://localhost:18001` with dummy credentials (auth disabled by default):

```swift
import AWSS3

let client = S3Client(config: try await S3Client.S3ClientConfiguration(
    endpoint: "http://localhost:18001",
    region: "us-west-1"
))
```

Or with the AWS CLI:

```bash
aws --endpoint-url http://localhost:18001 s3 mb s3://my-bucket
aws --endpoint-url http://localhost:18001 s3 cp file.txt s3://my-bucket/file.txt
aws --endpoint-url http://localhost:18001 s3 ls s3://my-bucket
```

## Package Structure

```
Sources/
  CosmoS3/          # Library: S3 middleware + handlers
    Auth/           # SigV4 + SigV2 authentication
    Data/           # DataAccess (actor), DatabaseFactory, BucketManager
    Handlers/       # ServiceHandler, BucketHandler, ObjectHandler
    Models/         # S3Bucket, S3ObjectMeta, S3User, S3Credential
    Storage/        # DiskStorageDriver
    Xml/            # S3 XML builder + parser
    Schema/         # SQL schema for each DB backend
  CosmoS3Host/      # Executable: loads config, starts server

Tests/
  CosmoS3Tests/     # Unit tests (request parsing, XML generation)
```

## Dependencies

- [CosmoApiServer-Swift](https://github.com/vkuttyp/CosmoApiServer-Swift) ≥ 1.0.0
- [CosmoSQLClient-Swift](https://github.com/vkuttyp/CosmoSQLClient-Swift) ≥ 1.4.3
- [swift-crypto](https://github.com/apple/swift-crypto) ≥ 3.0.0

## License

MIT
