import SwiftUI

/// Callbacks for editing capture shortcuts.
struct ShortcutActions {
    /// Saves a shortcut (`nil` restores the default); returns an error message if it can't be used.
    let change: (HotKey?, CaptureMode) -> String?
    /// Called when shortcut recording starts or stops.
    let setRecording: (Bool) -> Void
}

struct SettingsView: View {
    let appState: AppState
    let permissions: PermissionService
    let shortcutActions: ShortcutActions

    @AppStorage(SaveLocation.defaultsKey) private var saveLocation: SaveLocation = .desktop
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
            } header: {
                Text("General")
            } footer: {
                if launchAtLoginNeedsApproval {
                    HStack {
                        Text("Allow the app in Login Items to finish.")
                        Button("Open Login Items", action: LaunchAtLogin.openLoginItemsSettings)
                            .buttonStyle(.link)
                    }
                    .foregroundStyle(.secondary)
                } else if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .foregroundStyle(.red)
                }
            }

            Section("Export") {
                Picker("Save screenshots to", selection: $saveLocation) {
                    ForEach(SaveLocation.allCases) { location in
                        Text(location.title).tag(location)
                    }
                }
            }

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

            Section {
                ForEach(CaptureMode.allCases) { mode in
                    let hotKey = appState.hotKeys[mode] ?? mode.defaultHotKey

                    LabeledContent(mode.title) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if appState.unavailableHotKeys[mode] == true {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("This shortcut is already used by another app.")
                            }

                            ShortcutRecorder(
                                hotKey: hotKey,
                                onRecordingChange: shortcutActions.setRecording,
                                onRecord: { shortcutActions.change($0, mode) }
                            )

                            Button {
                                _ = shortcutActions.change(nil, mode)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(hotKey == mode.defaultHotKey)
                            .help("Restore Default (\(mode.defaultHotKey.displayString))")
                        }
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("System screenshot shortcuts (⇧⌘3, ⇧⌘4, ⇧⌘5) take priority over the app's.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Poll while the window is open so the status updates after the user toggles the switch.
            while !Task.isCancelled {
                appState.hasScreenRecordingPermission = permissions.hasScreenRecordingAccess
                launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        // The toggle can be reset below after a failure; don't act on that echo.
        guard enabled != LaunchAtLogin.isEnabled else { return }

        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    }
}

#Preview {
    SettingsView(
        appState: AppState(),
        permissions: PermissionService(),
        shortcutActions: ShortcutActions(change: { _, _ in nil }, setRecording: { _ in })
    )
}
