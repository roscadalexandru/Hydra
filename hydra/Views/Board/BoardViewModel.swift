import Foundation
import GRDB
import Combine

@Observable
final class BoardViewModel {
    var issues: [Issue] = []
    var workspace: Workspace?

    private var cancellable: AnyCancellable?

    init() {}

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
            try AppDatabase.shared.dbWriter.write { db in
                try updated.update(db)
            }
        } catch {
            print("Failed to move issue: \(error)")
        }
    }

    func createIssue(title: String, priority: Issue.Priority = .medium) {
        guard let workspaceId = workspace?.id else { return }
        var issue = Issue(workspaceId: workspaceId, title: title, priority: priority)
        do {
            try AppDatabase.shared.dbWriter.write { db in
                try issue.insert(db)
            }
        } catch {
            print("Failed to create issue: \(error)")
        }
    }

    func updateIssue(_ issue: Issue) {
        do {
            try AppDatabase.shared.dbWriter.write { db in
                try issue.update(db)
            }
        } catch {
            print("Failed to update issue: \(error)")
        }
    }

    func deleteIssue(_ issue: Issue) {
        do {
            try AppDatabase.shared.dbWriter.write { db in
                _ = try issue.delete(db)
            }
        } catch {
            print("Failed to delete issue: \(error)")
        }
    }

    func ensureWorkspace() {
        do {
            try AppDatabase.shared.dbWriter.write { db in
                if let existing = try Workspace.fetchOne(db) {
                    self.workspace = existing
                } else {
                    var newWorkspace = Workspace(name: "My Workspace")
                    try newWorkspace.insert(db)
                    self.workspace = newWorkspace
                }
            }
            observeIssues()
        } catch {
            print("Failed to ensure workspace: \(error)")
        }
    }

    private func observeIssues() {
        guard let workspaceId = workspace?.id else { return }

        let observation = ValueObservation.tracking { db in
            try Issue
                .filter(Issue.Columns.workspaceId == workspaceId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }

        cancellable = observation
            .publisher(in: AppDatabase.shared.dbWriter, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] issues in
                    self?.issues = issues
                }
            )
    }
}
