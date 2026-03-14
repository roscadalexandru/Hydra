import XCTest
import GRDB
@testable import hydra

final class ProjectTests: XCTestCase {

    private func makeWorkspaceAndDB() throws -> (AppDatabase, Workspace) {
        let db = try TestDatabase.make()
        var workspace = Workspace(name: "Test")
        try db.dbWriter.write { dbConn in
            try workspace.insert(dbConn)
        }
        return (db, workspace)
    }

    func testCreateProject() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var project = Project(workspaceId: workspace.id!, name: "frontend", path: "/code/frontend")
            try project.insert(dbConn)

            XCTAssertNotNil(project.id)
            XCTAssertEqual(project.name, "frontend")
            XCTAssertEqual(project.path, "/code/frontend")
        }
    }

    func testMultipleProjectsPerWorkspace() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var project1 = Project(workspaceId: workspace.id!, name: "frontend", path: "/code/fe")
            var project2 = Project(workspaceId: workspace.id!, name: "backend", path: "/code/be")
            try project1.insert(dbConn)
            try project2.insert(dbConn)

            let projects = try Project
                .filter(Project.Columns.workspaceId == workspace.id!)
                .fetchAll(dbConn)
            XCTAssertEqual(projects.count, 2)
        }
    }

    func testCascadeDeleteWithWorkspace() throws {
        let (db, workspace) = try makeWorkspaceAndDB()
        try db.dbWriter.write { dbConn in
            var project = Project(workspaceId: workspace.id!, name: "api", path: "/code/api")
            try project.insert(dbConn)
            let projectId = project.id

            _ = try Workspace.deleteAll(dbConn)

            let fetched = try Project.fetchOne(dbConn, key: projectId)
            XCTAssertNil(fetched)
        }
    }
}
