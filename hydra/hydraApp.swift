import SwiftUI

@main
struct HydraApp: App {
    var body: some Scene {
        Window("Welcome to Hydra", id: "welcome") {
            WelcomeView()
        }
        .defaultSize(width: 800, height: 500)

        WindowGroup("Workspace", for: Int64.self) { $workspaceId in
            if let workspaceId {
                MainView(workspaceId: workspaceId)
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}
