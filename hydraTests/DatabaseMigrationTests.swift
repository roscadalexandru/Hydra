import XCTest
import GRDB
@testable import hydra

final class DatabaseMigrationTests: XCTestCase {

    func testMigrationCreatesAllTables() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.read { dbConn in
            let tables = try String.fetchAll(dbConn, sql: """
                SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                ORDER BY name
            """)

            XCTAssertTrue(tables.contains("projects"))
            XCTAssertTrue(tables.contains("repositories"))
            XCTAssertTrue(tables.contains("epics"))
            XCTAssertTrue(tables.contains("issues"))
            XCTAssertTrue(tables.contains("agent_runs"))
            XCTAssertTrue(tables.contains("agent_steps"))
        }
    }

    func testMigrationIsIdempotent() throws {
        let dbQueue = try DatabaseQueue()
        _ = try AppDatabase(dbQueue)
        _ = try AppDatabase(dbQueue)
    }
}
