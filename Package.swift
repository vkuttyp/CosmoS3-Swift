// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CosmoS3",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CosmoS3", targets: ["CosmoS3"]),
        .executable(name: "CosmoS3Host", targets: ["CosmoS3Host"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vkuttyp/CosmoApiServer-Swift.git", from: "1.0.0"),
        .package(url: "https://github.com/vkuttyp/CosmoSQLClient-Swift.git", from: "1.4.3"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "CosmoS3",
            dependencies: [
                .product(name: "CosmoApiServer", package: "CosmoApiServer-Swift"),
                .product(name: "CosmoSQLCore",   package: "CosmoSQLClient-Swift"),
                .product(name: "CosmoSQLite",    package: "CosmoSQLClient-Swift"),
                .product(name: "CosmoPostgres",  package: "CosmoSQLClient-Swift"),
                .product(name: "CosmoMySQL",     package: "CosmoSQLClient-Swift"),
                .product(name: "CosmoMSSQL",     package: "CosmoSQLClient-Swift"),
                .product(name: "Crypto",         package: "swift-crypto"),
            ],
            resources: [
                .copy("Schema/sqlite.sql"),
                .copy("Schema/postgres.sql"),
                .copy("Schema/mysql.sql"),
                .copy("Schema/mssql.sql"),
            ]
        ),
        .executableTarget(
            name: "CosmoS3Host",
            dependencies: ["CosmoS3"],
            resources: [.copy("appsettings.json")]
        ),
        .testTarget(
            name: "CosmoS3Tests",
            dependencies: ["CosmoS3"]
        ),
    ]
)
