import SwiftUI

struct SettingsView: View {
    let appState: AppState
    let permissions: PermissionService

    var body: some View {
        Form {
            Section {
                LabeledContent("Screen Recording") {
                    if appState.hasScreenRecordingPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            permissions.openScreenRecordingSettings()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                if !appState.hasScreenRecordingPermission {
                    Text("After granting access, macOS may require reopening the app.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shortcuts") {
                ForEach(CaptureMode.allCases) { mode in
                    LabeledContent(mode.title) {
                        HStack(spacing: 6) {
                            if appState.unavailableHotKeys[mode] == true {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("This shortcut is already used by another app.")
                            }
                            Text(mode.defaultHotKey.displayString)
                                .monospaced()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Poll while the window is open so the status updates after the user toggles the switch.
            while !Task.isCancelled {
                appState.hasScreenRecordingPermission = permissions.hasScreenRecordingAccess
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

#Preview {
    SettingsView(appState: AppState(), permissions: PermissionService())
}
