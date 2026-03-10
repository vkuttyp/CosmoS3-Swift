import Foundation
import CosmoApiServer
import CosmoS3

// MARK: - Config

struct AppSettings: Decodable {
    var port: Int
    var storageBaseDir: String
    var database: DbSettings
    var requireAuth: Bool
    var logging: Bool
    var cors: Bool

    struct DbSettings: Decodable {
        var type: String
        var connectionString: String
    }
}

func loadSettings() throws -> AppSettings {
    if let url = Bundle.module.url(forResource: "appsettings", withExtension: "json"),
       let data = try? Data(contentsOf: url) {
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }
    // Fallback defaults
    return AppSettings(
        port: 18001,
        storageBaseDir: "./disk",
        database: .init(type: "sqlite", connectionString: "./cosmos3.db"),
        requireAuth: false,
        logging: true,
        cors: true
    )
}

// MARK: - Main

let settings = try loadSettings()

let dbType: DatabaseType = DatabaseType(rawValue: settings.database.type) ?? .sqlite

print("[CosmoS3Host] Starting on port \(settings.port)...")
let rawDb = try await DatabaseFactory.create(type: dbType, connectionString: settings.database.connectionString)
try await DatabaseFactory.ensureSchema(db: rawDb, type: dbType)
let da = DataAccess(db: rawDb)
let bucketManager = BucketManager(da: da)
try await bucketManager.load()

let builder = CosmoWebApplicationBuilder()
builder.configurationBuilder.addJsonFile("Sources/CosmoS3Host/appsettings.json")
builder.listenOn(port: settings.port)

if settings.logging { builder.useLogging() }
if settings.cors    { builder.useCors() }

builder.useCosmoS3(
    da: da,
    bucketManager: bucketManager,
    storageBaseDir: settings.storageBaseDir,
    requireAuth: settings.requireAuth
)

let app = builder.build()

// Health check endpoint
app.get("/_cosmo/health") { ctx in
    try ctx.response.writeJson(["status": "ok", "version": "1.0.0"])
}

print("[CosmoS3Host] Listening on http://0.0.0.0:\(settings.port)")
try await app.run()
