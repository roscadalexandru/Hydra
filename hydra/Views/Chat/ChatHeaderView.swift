import SwiftUI

struct ChatHeaderView: View {
    let sessionTitle: String
    let projects: [Project]
    @Binding var selectedProjectId: Int64?

    var body: some View {
        HStack(spacing: 12) {
            Text(sessionTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Picker("Project", selection: $selectedProjectId) {
                Text("No Project").tag(nil as Int64?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as Int64?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
