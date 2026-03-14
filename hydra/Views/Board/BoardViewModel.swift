import Foundation
import GRDB
import Combine

@Observable
final class BoardViewModel {
    var issues: [Issue] = []
    var project: Project?

    private var cancellable: AnyCancellable?

    init() {
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
            try AppDatabase.shared.dbWriter.write { db in
                try updated.update(db)
            }
        } catch {
            print("Failed to move issue: \(error)")
        }
    }

    func createIssue(title: String, priority: Issue.Priority = .medium) {
        guard let projectId = project?.id else { return }
        var issue = Issue(projectId: projectId, title: title, priority: priority)
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

    func ensureProject() {
        do {
            try AppDatabase.shared.dbWriter.write { db in
                if let existing = try Project.fetchOne(db) {
                    self.project = existing
                } else {
                    var newProject = Project(name: "My Project")
                    try newProject.insert(db)
                    self.project = newProject
                }
            }
        } catch {
            print("Failed to ensure project: \(error)")
        }
    }

    private func observeIssues() {
        let observation = ValueObservation.tracking { db in
            try Issue.order(Column("createdAt").asc).fetchAll(db)
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
