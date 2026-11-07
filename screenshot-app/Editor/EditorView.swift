import AppKit
import SwiftUI

/// Callbacks from the editor UI to its window controller.
struct EditorActions {
    let close: () -> Void
    let copy: () -> Void
    let save: () -> Void
}

/// Root view of the editor window: toolbar, zoomable canvas and inspector.
struct EditorView: View {
    static let toolbarHeight: CGFloat = 44
    static let inspectorWidth: CGFloat = 220
    static let cornerRadius: CGFloat = 12

    @Bindable var model: EditorModel
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model, actions: actions)
            Divider()
            HStack(spacing: 0) {
                CanvasScrollView(
                    canvasSize: model.canvasSize,
                    zoom: $model.zoom,
                    zoomToFitRequest: model.zoomToFitRequest,
                    cursor: model.activeTool?.cursor,
                    onDrag: model.handleCanvasDrag,
                    textField: model.textFieldRequest,
                    textColor: NSColor(model.annotationColor.color),
                    onTextCommit: model.commitText
                ) {
                    CompositionView(model: model)
                }
                Divider()
                EditorInspector(model: model)
                    .frame(width: Self.inspectorWidth)
            }
        }
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.separator)
        }
    }
}

private struct EditorToolbar: View {
    let model: EditorModel
    let actions: EditorActions

    var body: some View {
        HStack(spacing: 12) {
            Button(action: actions.close) {
                Image(systemName: "xmark")
            }
            .keyboardShortcut(unlessEditingText(.cancelAction))
            .help("Close (Esc)")

            Divider().frame(height: 20)

            HStack(spacing: 2) {
                ForEach(EditorTool.allCases) { tool in
                    ToolButton(systemImage: tool.systemImage, isSelected: model.activeTool == tool) {
                        model.activeTool = model.activeTool == tool ? nil : tool
                    }
                    .keyboardShortcut(unlessEditingText(KeyboardShortcut(KeyEquivalent(tool.shortcutKey), modifiers: [])))
                    .help("\(tool.title) (\(tool.shortcutKey.uppercased()))")
                }
            }

            HStack(spacing: 6) {
                ForEach(AnnotationColor.allCases) { color in
                    ColorDot(color: color, isSelected: model.annotationColor == color) {
                        model.annotationColor = color
                    }
                }
            }

            Divider().frame(height: 20)

            Button(action: model.undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut(unlessEditingText(KeyboardShortcut("z", modifiers: .command)))
            .disabled(!model.canUndo)
            .help("Undo (⌘Z)")

            Button(action: model.redo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut(unlessEditingText(KeyboardShortcut("z", modifiers: [.command, .shift])))
            .disabled(!model.canRedo)
            .help("Redo (⇧⌘Z)")

            Spacer()

            HStack(spacing: 4) {
                Button(action: model.zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom Out (⌘-)")

                Button(action: model.zoomToActualSize) {
                    Text(model.zoom, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(minWidth: 44)
                }
                .keyboardShortcut("1", modifiers: .command)
                .help("Actual Size (⌘1)")

                Button(action: model.zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom In (⌘+)")

                Button(action: model.zoomToFit) {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .keyboardShortcut("0", modifiers: .command)
                .help("Zoom to Fit (⌘0)")
            }

            Divider().frame(height: 20)

            HStack(spacing: 8) {
                Button("Copy", action: actions.copy)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(unlessEditingText(KeyboardShortcut("c", modifiers: .command)))
                    .help("Copy to Clipboard (⌘C)")

                Button("Save", action: actions.save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save as PNG to \(SaveLocation.current.title) (⌘S)")
            }
            .controlSize(.small)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: EditorView.toolbarHeight)
        // The window is borderless; let the toolbar's empty space move it.
        .background {
            Color.clear
                .contentShape(.rect)
                .gesture(WindowDragGesture())
        }
    }
}

extension EditorToolbar {
    /// Disables shortcuts that would steal keys from the inline text field while typing.
    func unlessEditingText(_ shortcut: KeyboardShortcut) -> KeyboardShortcut? {
        model.isEditingText ? nil : shortcut
    }
}

private extension EditorTool {
    var cursor: NSCursor {
        switch self {
        case .text: .iBeam
        case .arrow, .rectangle, .counter, .pixelate: .crosshair
        }
    }
}

private struct ToolButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 26)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
    }
}

private struct ColorDot: View {
    let color: AnnotationColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .overlay { Circle().strokeBorder(.black.opacity(0.15)) }
                .frame(width: 14, height: 14)
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(color.rawValue.capitalized)
    }
}

private struct EditorInspector: View {
    @Bindable var model: EditorModel

    private let swatchColumns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InspectorSection("Background") {
                LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 8) {
                    ForEach(CanvasBackground.allCases) { background in
                        BackgroundSwatch(background: background, isSelected: model.background == background) {
                            model.background = background
                        }
                    }
                }
            }

            InspectorSection("Padding") {
                SliderRow(value: $model.padding, range: EditorModel.paddingRange)
            }

            InspectorSection("Corner Radius") {
                SliderRow(value: $model.cornerRadius, range: EditorModel.cornerRadiusRange)
            }

            Spacer()

            Button("Reset to Defaults", action: model.resetStyle)
                .controlSize(.small)
                .disabled(model.hasDefaultStyle)
                .help("Restore default background, padding, corner radius and arrow color")
        }
        .padding(16)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct SliderRow: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        HStack {
            Slider(value: $value, in: range, step: 1)
            Text("\(Int(value))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct BackgroundSwatch: View {
    let background: CanvasBackground
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let style = background.style {
                    RoundedRectangle(cornerRadius: 6).fill(style)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    Image(systemName: "slash.circle")
                        .foregroundStyle(.secondary)
                }
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.separator)
            }
            .frame(width: 36, height: 36)
            .padding(2)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(background.title)
    }
}
