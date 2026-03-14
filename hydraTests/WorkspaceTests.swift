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
}
