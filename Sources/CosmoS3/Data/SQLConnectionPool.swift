import Foundation
import CosmoSQLCore

// MARK: - SQLConnectionPool

/// A thread-safe connection pool that wraps any SQLDatabase factory.
/// Implements SQLDatabase so it can be used as a drop-in replacement.
///
/// - Maintains a pool of ready connections (up to `maxConnections`).
/// - New connections are created on demand up to the limit.
/// - Callers that exceed the limit wait until a connection is released.
/// - On error, the connection is returned to the pool (the next caller will
///   get a fresh error if the connection is actually broken).
public actor SQLConnectionPool: SQLDatabase {

    // MARK: - Types

    public typealias Factory = @Sendable () async throws -> any SQLDatabase

    // MARK: - State

    private let factory: Factory
    private let maxConnections: Int

    private var available: [any SQLDatabase] = []   // idle connections
    private var inUse: Int = 0                       // connections currently checked out
    private var waiters: [CheckedContinuation<any SQLDatabase, Error>] = []

    // MARK: - Init

    /// Create a pool.
    /// - Parameters:
    ///   - maxConnections: Maximum concurrent connections. Default 10.
    ///   - minConnections: Connections to warm up at init time. Default 1.
    ///   - factory: Async closure that opens one new connection.
    public init(maxConnections: Int = 10, factory: @escaping Factory) {
        self.maxConnections = maxConnections
        self.factory = factory
    }

    /// Open `count` connections eagerly (call after `init`).
    public func warmUp(count: Int = 1) async throws {
        for _ in 0..<min(count, maxConnections) {
            let conn = try await factory()
            available.append(conn)
        }
    }

    // MARK: - Acquire / Release

    private func acquire() async throws -> any SQLDatabase {
        if let conn = available.popLast() {
            inUse += 1
            return conn
        }
        if inUse < maxConnections {
            inUse += 1
            return try await factory()
        }
        // All connections in use — wait
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release(_ conn: any SQLDatabase) {
        inUse -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            inUse += 1
            waiter.resume(returning: conn)
        } else {
            available.append(conn)
        }
    }

    // MARK: - SQLDatabase conformance

    public func query(_ sql: String, _ binds: [SQLValue]) async throws -> [SQLRow] {
        let conn = try await acquire()
        do {
            let rows = try await conn.query(sql, binds)
            release(conn)
            return rows
        } catch {
            release(conn)
            throw error
        }
    }

    public func execute(_ sql: String, _ binds: [SQLValue]) async throws -> Int {
        let conn = try await acquire()
        do {
            let affected = try await conn.execute(sql, binds)
            release(conn)
            return affected
        } catch {
            release(conn)
            throw error
        }
    }

    public func close() async throws {
        // Resume any waiting callers with an error
        for waiter in waiters {
            waiter.resume(throwing: SQLConnectionPoolError.closed)
        }
        waiters = []
        // Close all idle connections
        for conn in available {
            try? await conn.close()
        }
        available = []
    }
}

// MARK: - Errors

public enum SQLConnectionPoolError: Error {
    case closed
}
