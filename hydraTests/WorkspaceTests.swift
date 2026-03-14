import XCTest
import GRDB
@testable import hydra

final class WorkspaceTests: XCTestCase {

    func testCreateWorkspace() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var workspace = Workspace(name: "Test Workspace")
            try workspace.insert(dbConn)

            XCTAssertNotNil(workspace.id)
            XCTAssertEqual(workspace.name, "Test Workspace")
            XCTAssertEqual(workspace.defaultAutonomyMode, .supervised)
        }
    }

    func testFetchWorkspace() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var workspace = Workspace(name: "My App")
            try workspace.insert(dbConn)

            let fetched = try Workspace.fetchOne(dbConn, key: workspace.id)
            XCTAssertNotNil(fetched)
            XCTAssertEqual(fetched?.name, "My App")
        }
    }

    func testUpdateWorkspace() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var workspace = Workspace(name: "Old Name")
            try workspace.insert(dbConn)

            workspace.name = "New Name"
            workspace.defaultAutonomyMode = .autonomous
            try workspace.update(dbConn)

            let fetched = try Workspace.fetchOne(dbConn, key: workspace.id)
            XCTAssertEqual(fetched?.name, "New Name")
            XCTAssertEqual(fetched?.defaultAutonomyMode, .autonomous)
        }
    }

    func testDeleteWorkspace() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var workspace = Workspace(name: "To Delete")
            try workspace.insert(dbConn)
            let id = workspace.id

            _ = try workspace.delete(dbConn)

            let fetched = try Workspace.fetchOne(dbConn, key: id)
            XCTAssertNil(fetched)
        }
    }

    func testWorkspaceDefaults() throws {
        let workspace = Workspace(name: "Defaults")
        XCTAssertEqual(workspace.description, "")
        XCTAssertEqual(workspace.defaultAutonomyMode, .supervised)
        XCTAssertNil(workspace.id)
    }

    func testLastOpenedAtDefaultsToNil() throws {
        let workspace = Workspace(name: "Fresh")
        XCTAssertNil(workspace.lastOpenedAt)
    }

    func testLastOpenedAtPersistsRoundTrip() throws {
        let db = try TestDatabase.make()
        let now = Date()
        try db.dbWriter.write { dbConn in
            var workspace = Workspace(name: "Recent", lastOpenedAt: now)
            try workspace.insert(dbConn)

            let fetched = try Workspace.fetchOne(dbConn, key: workspace.id)
            XCTAssertNotNil(fetched?.lastOpenedAt)
            XCTAssertEqual(
                fetched!.lastOpenedAt!.timeIntervalSinceReferenceDate,
                now.timeIntervalSinceReferenceDate,
                accuracy: 1.0
            )
        }
    }

    func testLastOpenedAtCanBeUpdated() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var workspace = Workspace(name: "Update Me")
            try workspace.insert(dbConn)

            XCTAssertNil(workspace.lastOpenedAt)

            let now = Date()
            workspace.lastOpenedAt = now
            try workspace.update(dbConn)

            let fetched = try Workspace.fetchOne(dbConn, key: workspace.id)
            XCTAssertNotNil(fetched?.lastOpenedAt)
        }
    }
}
