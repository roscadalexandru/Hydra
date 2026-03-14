# Hydra

macOS native app (Swift + SwiftUI + GRDB). Autonomous AI dev agent with project management.

## Build & Test
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

## Knowledge Base
Obsidian vault is used for all project notes (architecture, tasks, decisions, etc.).
Notes live under `Hydra/` in the vault. Use `mcp__mcp-obsidian__*` tools to read/write them.

## Obsidian Structure
- `Hydra/Architecture/` — system design
- `Hydra/Features/` — feature planning
- `Hydra/Tasks/` — backlog and work tracking
- `Hydra/Research/` — investigations
- `Hydra/Decisions/` — ADRs
- `Hydra/Meetings/` — meeting notes
- `Hydra/Bugs/` — issue tracking
