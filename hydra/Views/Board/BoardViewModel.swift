import Foundation
import GRDB
import Combine

@Observable
final class BoardViewModel {
    var issues: [Issue] = []

    let workspaceId: Int64
    private let database: AppDatabase
    private var cancellable: AnyCancellable?

    nonisolated deinit { }

    init(workspaceId: Int64, database: AppDatabase = .shared) {
        self.workspaceId = workspaceId
        self.database = database
        observeIssues()
    }

    var columns: [Issue.Status] {
        Issue.Status.allCases
    }

    func issues(for status: Issue.Status) -> [Issue] {
        issues.filter { $0.status == status }
    }

    func moveIssue(_ issue: Issue, to status: Issue.Status) {
        guard var updated = issues.first(where: { $0.id == issue.id }) else { return }
        updated.status = status
        updated.updatedAt = Date()
        do {
            try database.dbWriter.write { db in
                try updated.update(db)
            }
        } catch {
            print("Failed to move issue: \(error)")
        }
    }

    func createIssue(title: String, priority: Issue.Priority = .medium) {
        var issue = Issue(workspaceId: workspaceId, title: title, priority: priority)
        do {
            try database.dbWriter.write { db in
                try issue.insert(db)
            }
        } catch {
            print("Failed to create issue: \(error)")
        }
    }

    func updateIssue(_ issue: Issue) {
        do {
            try database.dbWriter.write { db in
                try issue.update(db)
            }
        } catch {
            print("Failed to update issue: \(error)")
        }
    }

    func deleteIssue(_ issue: Issue) {
        do {
            try database.dbWriter.write { db in
                _ = try issue.delete(db)
            }
        } catch {
            print("Failed to delete issue: \(error)")
        }
    }

    private func observeIssues() {
        let workspaceId = self.workspaceId

        let observation = ValueObservation.tracking { db in
            try Issue
                .filter(Issue.Columns.workspaceId == workspaceId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }

        cancellable = observation
            .publisher(in: database.dbWriter, scheduling: .async(onQueue: .main))
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] issues in
                    self?.issues = issues
                }
            )
    }
}
