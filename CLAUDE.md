# Hydra

macOS native app (Swift + SwiftUI + GRDB). Autonomous AI dev agent with project management.

## Languages & Frameworks
Swift + SwiftUI macOS app. Uses GRDB for SQLite persistence. Verify GRDB conformance patterns against actual API docs before applying.

## Architecture
- `hydra/Models/` — GRDB models: Workspace → Project, Epic, Issue → AgentRun → AgentStep
- `hydra/Database/` — `AppDatabase` with migrations (v1 core tables, v2 chat tables, v3 workspace lastOpenedAt; pre-release)
- `hydra/Services/` — `SidecarProcess` (JSON-RPC child process), `SidecarBridge` (high-level async API), `SidecarProtocol` (types)
- `hydra/ViewModels/` — standalone ViewModels (e.g. `WorkspaceSettingsViewModel`)
- `hydra/Views/` — SwiftUI views. `Board/` has kanban board, `Chat/` has chat interface, `WelcomeView` is the workspace launcher
- Two-scene app: `Window("welcome")` singleton + `WindowGroup(for: Int64.self)` for workspace windows
- Workspace is the top-level container; Project is a repo/directory within a workspace

## Git & Version Control
- When git worktree creation fails or any operation fails silently, immediately inform the user rather than falling back to an alternative approach without notice.

## Build & Test
- always use `/test-driven-development` when doing implementation
- Xcode project at `hydra.xcodeproj` (not inside a subfolder)
- Build: `xcodebuild -project hydra.xcodeproj -scheme hydra -destination 'platform=macOS' build`
- Unit tests only: `xcodebuild test -project hydra.xcodeproj -scheme hydra -destination 'platform=macOS' -only-testing:hydraTests`
- Tests use in-memory SQLite via `TestDatabase.make()` — no filesystem or app launch needed
- For async ValueObservation tests, use `XCTNSPredicateExpectation` polling — not `asyncAfter` fixed delays

## Gotchas
- Xcode project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files are auto-discovered, no manual pbxproj edits needed
- GRDB: put all protocol conformances (`Codable, FetchableRecord, MutablePersistableRecord`) on the struct declaration, not in extensions — otherwise "circular reference" errors
- GRDB `belongsTo("x")` auto-pluralizes to find table `xs` — use explicit `.column().references("table")` for non-standard names like `chatSessionId` → `chat_sessions`
- `Issue` conflicts with `Testing.Issue` — use `hydra.Issue` in test files
- Use XCTest (not Swift Testing `import Testing`) for test files
- GRDB: `@MainActor` ViewModels must use `scheduling: .async(onQueue: .main)` for ValueObservation publishers — `.immediate` delivers on background thread causing data races
- GRDB: use `dbWriter.read` for read-only queries, not `dbWriter.write` — `write` takes an exclusive lock unnecessarily
- GRDB: in `@MainActor` test classes, `dbWriter.read`/`write` require `await`
- `@MainActor` ViewModels should use `Task.detached` with async `dbWriter.write` for DB mutations to avoid blocking the main thread
- Swift bug #87316: `@Observable` classes need `nonisolated deinit { }` or XCTest crashes with `-default-isolation MainActor`
- Git worktrees don't copy `node_modules` — run `cd sidecar && npm install` in worktrees or SidecarProcessTests will crash
- SwiftUI: `@Environment(\.dismiss)` is a no-op for top-level `Window` scenes — use `dismissWindow(id:)` instead
- SwiftUI: `.onDisappear` on `TabView` children fires on tab switch, not just parent dismissal — put sheet-dismiss logic on the `TabView` itself
- App target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types are implicitly `@MainActor`. Test target does NOT set this, so test classes are nonisolated and `dbWriter.read`/`write` don't need `await`

## Knowledge Base (Obsidian)
Project notes live under `Hydra/` in the Obsidian vault. Use `mcp__mcp-obsidian__*` tools.
Subdirectories: Architecture, Features, Tasks, Research, Decisions, Meetings, Bugs.
