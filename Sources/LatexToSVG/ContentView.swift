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
        .frame(minWidth: 780, minHeight: 520)
        .toolbar { toolbar }
        .task { model.renderNow() }
    }

    // MARK: Centre column

    private var centre: some View {
        VSplitView {
            preview
                .frame(minHeight: 160)
            editor
                .frame(minHeight: 120)
        }
    }

    private var preview: some View {
        ZStack {
            // A checkerboard would imply the background is part of the artwork;
            // a plain surface reads as "nothing here", which is accurate since
            // every export is transparent. The surface darkens when the chosen
            // equation colour would vanish against a light background.
            if model.previewNeedsDarkBackground {
                Color(red: 0.15, green: 0.15, blue: 0.17)
            } else {
                Color(nsColor: .textBackgroundColor)
            }

            SVGPreview(svg: model.renderedSVG)
                .padding(20)

            if model.renderedSVG == nil && model.errorMessage == nil {
                Text("Type an equation below")
                    .foregroundStyle(.tertiary)
            }

            // Topmost so it, not the web view, receives the preview's mouse
            // events: drag-out and the right-click Copy menu both live here.
            PreviewDragSource(model: model)
        }
        .overlay(alignment: .bottom) { statusBar }
        .overlay(alignment: .topTrailing) {
            if model.isRendering {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial)
            }

            HStack(spacing: 12) {
                if model.pixelWidth > 0 {
                    Text("\(SVGDocument.format(model.pixelWidth)) × "
                         + "\(SVGDocument.format(model.pixelHeight)) px")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Text("Drag the equation out, or right-click to copy")
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
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.renderedSVG == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LaTeX")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            TextEditor(text: $model.latex)
                .font(.system(.body, design: .monospaced))
                .padding(6)
                .frame(minHeight: 80)
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
