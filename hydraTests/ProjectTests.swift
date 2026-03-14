import XCTest
import GRDB
@testable import hydra

final class ProjectTests: XCTestCase {

    func testCreateProject() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var project = Project(name: "Test Project")
            try project.insert(dbConn)

            XCTAssertNotNil(project.id)
            XCTAssertEqual(project.name, "Test Project")
            XCTAssertEqual(project.defaultAutonomyMode, .supervised)
        }
    }

    func testFetchProject() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var project = Project(name: "My App")
            try project.insert(dbConn)

            let fetched = try Project.fetchOne(dbConn, key: project.id)
            XCTAssertNotNil(fetched)
            XCTAssertEqual(fetched?.name, "My App")
        }
    }

    func testUpdateProject() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var project = Project(name: "Old Name")
            try project.insert(dbConn)

            project.name = "New Name"
            project.defaultAutonomyMode = .autonomous
            try project.update(dbConn)

            let fetched = try Project.fetchOne(dbConn, key: project.id)
            XCTAssertEqual(fetched?.name, "New Name")
            XCTAssertEqual(fetched?.defaultAutonomyMode, .autonomous)
        }
    }

    func testDeleteProject() throws {
        let db = try TestDatabase.make()
        try db.dbWriter.write { dbConn in
            var project = Project(name: "To Delete")
            try project.insert(dbConn)
            let id = project.id

            _ = try project.delete(dbConn)

            let fetched = try Project.fetchOne(dbConn, key: id)
            XCTAssertNil(fetched)
        }
    }

    func testProjectDefaults() throws {
        let project = Project(name: "Defaults")
        XCTAssertEqual(project.description, "")
        XCTAssertEqual(project.defaultAutonomyMode, .supervised)
        XCTAssertNil(project.id)
    }
}
