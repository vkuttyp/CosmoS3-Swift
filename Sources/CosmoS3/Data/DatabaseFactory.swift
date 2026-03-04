import Foundation
import CosmoSQLCore
import CosmoSQLite

// MARK: - DatabaseFactory

public enum DatabaseType: String, Sendable {
    case sqlite    = "sqlite"
    case postgres  = "postgres"
    case mysql     = "mysql"
    case sqlserver = "sqlserver"
}

public enum DatabaseFactory {

    public static func create(type: DatabaseType, connectionString: String) async throws -> any SQLDatabase {
        switch type {
        case .sqlite:
            let storage: SQLiteConnection.Storage = connectionString.lowercased() == ":memory:"
                ? .memory
                : .file(path: connectionString)
            return try await SQLiteConnection.open(configuration: .init(storage: storage))
        case .postgres:
            fatalError("PostgresConnection support coming soon — add CosmoPostgres dependency")
        case .mysql:
            fatalError("MySQLConnection support coming soon — add CosmoMySQL dependency")
        case .sqlserver:
            fatalError("MSSQLConnection support coming soon — add CosmoMSSQL dependency")
        }
    }

    // MARK: - Schema bootstrap

    public static func ensureSchema(db: any SQLDatabase, type: DatabaseType) async throws {
        let sql = try schemaSQL(for: type)
        // Split on semicolons, drop blanks, execute each statement
        let statements = sql
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for stmt in statements {
            try await db.execute(stmt)
        }
    }

    private static func schemaSQL(for type: DatabaseType) throws -> String {
        let filename: String
        switch type {
        case .sqlite:    filename = "sqlite.sql"
        case .postgres:  filename = "postgres.sql"
        case .mysql:     filename = "mysql.sql"
        case .sqlserver: filename = "mssql.sql"
        }
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil,
                                          subdirectory: "Schema"),
              let sql = try? String(contentsOf: url, encoding: .utf8)
        else {
            // Fallback: look next to the executable (for Linux hosts without Bundle.module)
            let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let fallback = execDir.appendingPathComponent("Schema/\(filename)")
            guard let sql = try? String(contentsOf: fallback, encoding: .utf8) else {
                throw S3Error.internalError("Schema file '\(filename)' not found in bundle or exe dir")
            }
            return sql
        }
        return sql
    }
}
