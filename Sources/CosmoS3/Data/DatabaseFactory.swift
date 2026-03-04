import Foundation
import CosmoSQLCore
import CosmoSQLite
import CosmoPostgres
import CosmoMySQL
import CosmoMSSQL

// MARK: - DatabaseType

public enum DatabaseType: String, Sendable {
    case sqlite    = "sqlite"
    case postgres  = "postgres"
    case mysql     = "mysql"
    case sqlserver = "sqlserver"
}

// MARK: - DatabaseFactory

public enum DatabaseFactory {

    /// Open a connection from a connection string.
    /// - SQLite:    file path (`./data.db`) or `:memory:`
    /// - Postgres:  `host=localhost port=5432 dbname=s3 user=s3 password=s3`
    /// - MySQL:     same key=value style
    /// - SQL Server: ADO.NET style `Server=host,1433;Database=s3;User Id=sa;Password=P@ss`
    public static func create(type: DatabaseType, connectionString: String) async throws -> any SQLDatabase {
        switch type {
        case .sqlite:
            let storage: SQLiteConnection.Storage = connectionString.lowercased() == ":memory:"
                ? .memory
                : .file(path: connectionString)
            return try await SQLiteConnection.open(configuration: .init(storage: storage))

        case .postgres:
            let cfg = try parseKV(connectionString, defaults: ("localhost", 5432, "s3", "s3", "s3"))
            return try await PostgresConnection.connect(
                configuration: .init(
                    host: cfg.host, port: cfg.port,
                    database: cfg.database, username: cfg.username, password: cfg.password,
                    tls: .prefer
                )
            )

        case .mysql:
            let cfg = try parseKV(connectionString, defaults: ("localhost", 3306, "s3", "s3", "s3"))
            return try await MySQLConnection.connect(
                configuration: .init(
                    host: cfg.host, port: cfg.port,
                    database: cfg.database, username: cfg.username, password: cfg.password,
                    tls: .prefer
                )
            )

        case .sqlserver:
            return try await MSSQLConnection.connect(
                configuration: try .init(connectionString: connectionString)
            )
        }
    }

    // MARK: - Schema bootstrap

    public static func ensureSchema(db: any SQLDatabase, type: DatabaseType) async throws {
        let sql = try schemaSQL(for: type)
        let statements = sql
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for stmt in statements {
            try await db.execute(stmt)
        }
    }

    // MARK: - Helpers

    /// Parse `key=value` pairs (whitespace or semicolon separated).
    private static func parseKV(
        _ s: String,
        defaults: (host: String, port: Int, database: String, username: String, password: String)
    ) throws -> (host: String, port: Int, database: String, username: String, password: String) {
        var pairs: [String: String] = [:]
        let sep = s.contains(";") ? ";" : " "
        for part in s.components(separatedBy: sep) {
            let kv = part.components(separatedBy: "=")
            guard kv.count >= 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = kv[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            pairs[key] = val
        }
        func get(_ keys: String...) -> String? { keys.compactMap { pairs[$0] }.first }

        return (
            host:     get("host", "server", "data source") ?? defaults.host,
            port:     Int(get("port") ?? "") ?? defaults.port,
            database: get("database", "dbname", "db") ?? defaults.database,
            username: get("username", "user id", "uid", "user") ?? defaults.username,
            password: get("password", "pwd") ?? defaults.password
        )
    }

    private static func schemaSQL(for type: DatabaseType) throws -> String {
        let filename: String
        switch type {
        case .sqlite:    filename = "sqlite.sql"
        case .postgres:  filename = "postgres.sql"
        case .mysql:     filename = "mysql.sql"
        case .sqlserver: filename = "mssql.sql"
        }
        if let url = Bundle.module.url(forResource: filename, withExtension: nil,
                                       subdirectory: "Schema"),
           let sql = try? String(contentsOf: url, encoding: .utf8) {
            return sql
        }
        // Linux fallback: look next to the executable
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let fallback = execDir.appendingPathComponent("Schema/\(filename)")
        guard let sql = try? String(contentsOf: fallback, encoding: .utf8) else {
            throw S3Error.internalError("Schema file '\(filename)' not found in bundle or exe dir")
        }
        return sql
    }
}
