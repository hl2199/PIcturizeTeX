import LatexCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            if model.showHistory {
                HistoryPane(model: model)
                Divider()
            }

            centre

            Divider()
            SettingsPane(model: model)
        }
        .frame(minWidth: 840, minHeight: 560)
        .toolbar { toolbar }
        .tint(Theme.accent)
        .task { model.renderNow() }
    }

    // MARK: Centre column

    private var centre: some View {
        VSplitView {
            desk
                .frame(minHeight: 240)
            editor
                .frame(minHeight: 130)
        }
    }

    // MARK: The desk

    /// The signature surface: a dot-grid drafting desk with the equation on a
    /// floating sheet of paper. The sheet is sized to the equation's true
    /// export dimensions, so what floats there is exactly the artefact the
    /// drag hands over.
    private var desk: some View {
        GeometryReader { geo in
            ZStack {
                DeskBackground()
                paperSheet(available: geo.size)
                // Topmost so it, not the web view, receives the desk's mouse
                // events: drag-out and the right-click Copy menu live here.
                PreviewDragSource(model: model)
            }
        }
        .overlay(alignment: .bottom) { statusBar }
        .overlay(alignment: .topTrailing) {
            if model.isRendering {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
    }

    private func paperSheet(available: CGSize) -> some View {
        // Keep the sheet clear of the pane edges and the status bar.
        let maxWidth = max(available.width - 100, 160)
        let maxHeight = max(available.height - 150, 90)

        return Group {
            if model.renderedSVG != nil {
                SVGPreview(svg: model.renderedSVG)
                    .frame(width: min(max(model.pixelWidth, 40), maxWidth),
                           height: min(max(model.pixelHeight, 24), maxHeight))
            } else {
                Text("Type an equation below")
                    .font(.system(.title3, design: .serif))
                    .italic()
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(model.previewNeedsDarkBackground ? Theme.paperDark : Theme.paperLight)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 7)
        )
        .padding(.bottom, 44)
        .animation(.spring(duration: 0.25), value: model.pixelWidth)
        .animation(.spring(duration: 0.25), value: model.pixelHeight)
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                }
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(.orange.opacity(0.35)))
                .padding(.horizontal, 12)
            }

            HStack(spacing: 12) {
                if model.pixelWidth > 0 {
                    Text("\(SVGDocument.format(model.pixelWidth)) × "
                         + "\(SVGDocument.format(model.pixelHeight)) px")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Text("Drag the sheet out, or right-click to copy")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LaTeX")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            TextEditor(text: $model.latex)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.showHistory.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Show or hide history")
        }
    }
}
