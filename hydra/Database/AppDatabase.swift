import Foundation
import GRDB

struct AppDatabase {
    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "workspaces") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("defaultAutonomyMode", .text).notNull().defaults(to: "supervised")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "projects") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("workspace", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "epics") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("workspace", onDelete: .cascade).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "issues") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("workspace", onDelete: .cascade).notNull()
                t.belongsTo("epic", onDelete: .setNull)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "backlog")
                t.column("priority", .text).notNull().defaults(to: "medium")
                t.column("assigneeType", .text).notNull().defaults(to: "human")
                t.column("assigneeName", .text).notNull().defaults(to: "")
                t.column("autonomyMode", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "agent_runs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("issue", onDelete: .cascade).notNull()
                t.column("status", .text).notNull().defaults(to: "running")
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("error", .text)
            }

            try db.create(table: "agent_steps") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("agentRunId", .integer)
                    .notNull()
                    .references("agent_runs", onDelete: .cascade)
                t.column("orderIndex", .integer).notNull()
                t.column("description", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("output", .text)
                t.column("filesChanged", .text)
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: "chat_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("workspace", onDelete: .cascade).notNull()
                t.column("issueId", .integer).references("issues", onDelete: .setNull)
                t.column("sdkSessionId", .text)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("title", .text).notNull().defaults(to: "New Chat")
                t.column("totalCostUsd", .double)
                t.column("totalDurationMs", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "chat_messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("chatSessionId", .integer)
                    .notNull()
                    .references("chat_sessions", onDelete: .cascade)
                t.column("orderIndex", .integer).notNull()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("toolName", .text)
                t.column("toolId", .text)
                t.column("toolInput", .text)
                t.column("isError", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "chat_messages_on_session_order",
                on: "chat_messages",
                columns: ["chatSessionId", "orderIndex"]
            )
        }

        migrator.registerMigration("v3") { db in
            try db.alter(table: "workspaces") { t in
                t.add(column: "lastOpenedAt", .datetime)
            }
        }

        migrator.registerMigration("v4") { db in
            try db.alter(table: "chat_sessions") { t in
                t.add(column: "projectId", .integer).references("projects", onDelete: .setNull)
            }
        }

        return migrator
    }
}

extension AppDatabase {
    static let shared = makeShared()

    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = appSupportURL.appendingPathComponent("Hydra", isDirectory: true)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let databaseURL = directoryURL.appendingPathComponent("hydra.sqlite")
            let dbPool = try DatabasePool(path: databaseURL.path)
            return try AppDatabase(dbPool)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
}
