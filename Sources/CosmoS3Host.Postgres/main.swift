import Foundation
import CosmoApiServer
import CosmoS3

struct AppSettings: Decodable {
    var port: Int
    var storageBaseDir: String
    var connectionString: String
    var requireAuth: Bool
    var logging: Bool
    var cors: Bool
}

func loadSettings() -> AppSettings {
    if let url = Bundle.module.url(forResource: "appsettings", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let s = try? JSONDecoder().decode(AppSettings.self, from: data) { return s }
    return AppSettings(port: 18002, storageBaseDir: "./disk",
                       connectionString: "host=localhost port=5432 database=cosmos3 username=postgres password=postgres",
                       requireAuth: false, logging: true, cors: true)
}

let settings = loadSettings()
print("[CosmoS3Host.Postgres] Starting on port \(settings.port)...")

let rawDb = try await DatabaseFactory.create(type: .postgres, connectionString: settings.connectionString)
try await DatabaseFactory.ensureSchema(db: rawDb, type: .postgres)
let da = DataAccess(db: rawDb, tablePrefix: "s3.", usePostgres: true)
let bucketManager = BucketManager(da: da)
try await bucketManager.load()

let builder = CosmoWebApplicationBuilder().listenOn(port: settings.port)
if settings.logging { builder.useLogging() }
if settings.cors    { builder.useCors() }
builder.useCosmoS3(da: da, bucketManager: bucketManager,
                   storageBaseDir: settings.storageBaseDir,
                   requireAuth: settings.requireAuth)

let app = builder.build()
app.get("/_cosmo/health") { ctx in
    try ctx.response.writeJson(["status": "ok", "db": "postgres", "version": "1.0.0"])
}

print("[CosmoS3Host.Postgres] Listening on http://0.0.0.0:\(settings.port)")
try await app.run()
