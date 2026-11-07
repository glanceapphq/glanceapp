import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records a new keyboard shortcut when clicked.
///
/// While recording, every key press is captured (and swallowed); Esc cancels.
struct ShortcutRecorder: View {
    let hotKey: HotKey
    /// Called when recording starts or stops, so global hot keys can be paused meanwhile.
    let onRecordingChange: (Bool) -> Void
    /// Called with the recorded shortcut; returns an error message if it can't be used.
    let onRecord: (HotKey) -> String?

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut…" : hotKey.displayString)
                    .monospaced(!isRecording)
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .help(isRecording ? "Press a shortcut, or Esc to cancel" : "Click to record a new shortcut")

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        error = nil
        isRecording = true
        onRecordingChange(true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            guard let recorded = HotKey(event: event) else {
                error = "Use ⌘, ⌃ or ⌥ with a key, or a function key."
                NSSound.beep()
                return nil
            }
            error = onRecord(recorded)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }
}
