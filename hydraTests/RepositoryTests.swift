import XCTest
import GRDB
@testable import hydra

final class RepositoryTests: XCTestCase {

    private func makeProjectAndDB() throws -> (AppDatabase, Project) {
        let db = try TestDatabase.make()
        var project = Project(name: "Test")
        try db.dbWriter.write { dbConn in
            try project.insert(dbConn)
        }
        return (db, project)
    }

    func testCreateRepository() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var repo = Repository(projectId: project.id!, name: "frontend", path: "/code/frontend")
            try repo.insert(dbConn)

            XCTAssertNotNil(repo.id)
            XCTAssertEqual(repo.name, "frontend")
            XCTAssertEqual(repo.path, "/code/frontend")
        }
    }

    func testMultipleReposPerProject() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var repo1 = Repository(projectId: project.id!, name: "frontend", path: "/code/fe")
            var repo2 = Repository(projectId: project.id!, name: "backend", path: "/code/be")
            try repo1.insert(dbConn)
            try repo2.insert(dbConn)

            let repos = try Repository
                .filter(Repository.Columns.projectId == project.id!)
                .fetchAll(dbConn)
            XCTAssertEqual(repos.count, 2)
        }
    }

    func testCascadeDeleteWithProject() throws {
        let (db, project) = try makeProjectAndDB()
        try db.dbWriter.write { dbConn in
            var repo = Repository(projectId: project.id!, name: "api", path: "/code/api")
            try repo.insert(dbConn)
            let repoId = repo.id

            _ = try Project.deleteAll(dbConn)

            let fetched = try Repository.fetchOne(dbConn, key: repoId)
            XCTAssertNil(fetched)
        }
    }
}
