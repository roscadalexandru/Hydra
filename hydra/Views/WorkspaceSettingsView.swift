import SwiftUI

struct WorkspaceSettingsView: View {
    let workspaceId: Int64
    @State private var viewModel: WorkspaceSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedName: String = ""
    @State private var editedDescription: String = ""
    @State private var editedAutonomyMode: Workspace.AutonomyMode = .supervised
    @State private var didLoadInitialValues = false

    @State private var projectToRemove: Project?

    init(workspaceId: Int64) {
        self.workspaceId = workspaceId
        self._viewModel = State(wrappedValue: WorkspaceSettingsViewModel(workspaceId: workspaceId))
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            projectsTab
                .tabItem { Label("Projects", systemImage: "folder") }
        }
        .frame(width: 480, height: 360)
        .onDisappear {
            commitName()
            commitDescription()
        }
        .onChange(of: viewModel.workspace) { _, ws in
            guard let ws, !didLoadInitialValues else { return }
            editedName = ws.name
            editedDescription = ws.description
            editedAutonomyMode = ws.defaultAutonomyMode
            didLoadInitialValues = true
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .alert(
            "Remove Project",
            isPresented: Binding(
                get: { projectToRemove != nil },
                set: { if !$0 { projectToRemove = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                projectToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let id = projectToRemove?.id {
                    viewModel.removeProject(id)
                }
                projectToRemove = nil
            }
        } message: {
            if let project = projectToRemove {
                Text("Remove \"\(project.name)\" from this workspace? The files on disk will not be deleted.")
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            TextField("Name", text: $editedName)
                .onSubmit { commitName() }

            TextField("Description", text: $editedDescription, axis: .vertical)
                .lineLimit(3...6)
                .onSubmit { commitDescription() }

            Picker("Default Autonomy Mode", selection: $editedAutonomyMode) {
                ForEach(Workspace.AutonomyMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .onChange(of: editedAutonomyMode) { _, newValue in
                guard didLoadInitialValues else { return }
                viewModel.updateWorkspace(autonomyMode: newValue)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func commitName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        guard didLoadInitialValues, !trimmed.isEmpty, editedName != viewModel.workspace?.name else { return }
        viewModel.updateWorkspace(name: editedName)
    }

    private func commitDescription() {
        guard didLoadInitialValues, editedDescription != viewModel.workspace?.description else { return }
        viewModel.updateWorkspace(description: editedDescription)
    }

    // MARK: - Projects Tab

    private var projectsTab: some View {
        VStack(spacing: 0) {
            if viewModel.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a directory to give the agent access to code.")
                )
            } else {
                List {
                    ForEach(viewModel.projects) { project in
                        ProjectRow(project: project) {
                            projectToRemove = project
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Add Project\u{2026}") {
                    pickDirectory()
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"
        panel.prompt = "Add Project"

        if panel.runModal() == .OK, let url = panel.url {
            let name = url.lastPathComponent
            let path = url.path
            viewModel.addProject(name: name, path: path)
        }
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let project: Project
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body.bold())
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
            } label: {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove project")
        }
        .padding(.vertical, 4)
    }
}
