# Hydra

macOS native app (Swift + SwiftUI + GRDB). Autonomous AI dev agent with project management.

## Languages & Frameworks
Swift + SwiftUI macOS app. Uses GRDB for SQLite persistence. Verify GRDB conformance patterns against actual API docs before applying.

## Architecture
- `hydra/Models/` — GRDB models: Workspace → Project, Epic, Issue → AgentRun → AgentStep
- `hydra/Database/` — `AppDatabase` with migrations (single v1 migration, pre-release)
- `hydra/Services/` — `SidecarProcess` (JSON-RPC child process), `SidecarBridge` (high-level async API), `SidecarProtocol` (types)
- `hydra/Views/` — SwiftUI views. `Board/` has kanban board (BoardView, BoardViewModel, KanbanColumnView, IssueCardView, IssueDetailView)
- Workspace is the top-level container; Project is a repo/directory within a workspace

## Git & Version Control
- When git worktree creation fails or any operation fails silently, immediately inform the user rather than falling back to an alternative approach without notice.

## Build & Test
- always use `/test-driven-development` when doing implementation
- Xcode project at `hydra.xcodeproj` (not inside a subfolder)
- Build: `xcodebuild -project hydra.xcodeproj -scheme hydra -destination 'platform=macOS' build`
- Unit tests only: `xcodebuild test -project hydra.xcodeproj -scheme hydra -destination 'platform=macOS' -only-testing:hydraTests`
- Tests use in-memory SQLite via `TestDatabase.make()` — no filesystem or app launch needed

## Gotchas
- Xcode `.pbxproj` can't be edited programmatically — new files must be added to targets manually by the user
- GRDB: put all protocol conformances (`Codable, FetchableRecord, MutablePersistableRecord`) on the struct declaration, not in extensions — otherwise "circular reference" errors
- GRDB `belongsTo("x")` looks for a table literally named `x` — use `.references("actual_table")` for snake_case table names
- `Issue` conflicts with `Testing.Issue` — use `hydra.Issue` in test files
- Use XCTest (not Swift Testing `import Testing`) for test files

## Knowledge Base (Obsidian)
Project notes live under `Hydra/` in the Obsidian vault. Use `mcp__mcp-obsidian__*` tools.
Subdirectories: Architecture, Features, Tasks, Research, Decisions, Meetings, Bugs.
