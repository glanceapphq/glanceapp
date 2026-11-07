import SwiftUI

/// Root view of the editor window: toolbar, zoomable canvas and inspector.
struct EditorView: View {
    static let toolbarHeight: CGFloat = 44
    static let inspectorWidth: CGFloat = 220
    static let cornerRadius: CGFloat = 12

    @Bindable var model: EditorModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model, onClose: onClose)
            Divider()
            HStack(spacing: 0) {
                CanvasScrollView(
                    canvasSize: model.canvasSize,
                    zoom: $model.zoom,
                    zoomToFitRequest: model.zoomToFitRequest
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
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")

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
