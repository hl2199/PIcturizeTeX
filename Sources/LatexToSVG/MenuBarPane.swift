import AppKit
import LatexCore
import SwiftUI

/// The menu bar companion: a compact, always-display-mode equation card.
///
/// Runs on its own `AppModel` instance, so it works with the main window
/// closed and its settings never fight the main window's. Drag-out and
/// right-click copy reuse the same machinery as the desk.
struct MenuBarPane: View {
    @Bindable var model: AppModel

    private let paneWidth: CGFloat = 320
    private let previewHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview

            TextEditor(text: $model.latex)
                .font(.system(.callout, design: .monospaced))
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25)))

            HStack {
                Text("Color")
                Spacer()
                Picker("", selection: $model.colorChoice) {
                    Text("Black").tag(ColorChoice.black)
                    Text("White").tag(ColorChoice.white)
                    Text("Custom").tag(ColorChoice.custom)
                }
                .labelsHidden()
                .fixedSize()

                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(css: model.customColorText) ?? .labelColor) },
                    set: {
                        model.customColorText = $0.cssHexString
                        model.colorChoice = .custom
                    }
                ))
                .labelsHidden()
            }

            HStack {
                Text("Scale")
                Spacer()
                Picker("", selection: $model.scaleChoice) {
                    Text("Default (1 ex = 8 px)").tag(ScaleChoice.standard)
                    Text("Match a font").tag(ScaleChoice.matchFont)
                    Text("Manual").tag(ScaleChoice.manual)
                }
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            HStack {
                Text("Drag the equation out, or right-click to copy")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button("Save as \(format.displayName)…") {
                            Task { await model.save(format: format) }
                        }
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .fixedSize()
                .disabled(model.renderedSVG == nil)
            }
        }
        .padding(12)
        .frame(width: paneWidth)
        .tint(Theme.accent)
        .task { model.renderNow() }
    }

    private var preview: some View {
        ZStack {
            DeskBackground()

            Group {
                if model.renderedSVG != nil {
                    SVGPreview(svg: model.renderedSVG)
                        .frame(width: model.pixelWidth * previewZoom,
                               height: model.pixelHeight * previewZoom)
                } else {
                    Text("Type an equation")
                        .font(.system(.callout, design: .serif))
                        .italic()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.previewNeedsDarkBackground ? Theme.paperDark : Theme.paperLight)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            )

            PreviewDragSource(model: model)
        }
        .frame(height: previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .padding(6)
            }
        }
    }

    /// True size, shrinking only to fit the small pane -- same rule as the
    /// main desk.
    private var previewZoom: Double {
        guard model.pixelWidth > 0, model.pixelHeight > 0 else { return 1 }
        return min(min((paneWidth - 60) / model.pixelWidth,
                       (previewHeight - 40) / model.pixelHeight), 1)
    }
}
