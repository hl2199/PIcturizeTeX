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
            // every export is transparent.
            Color(nsColor: .textBackgroundColor)

            SVGPreview(svg: model.renderedSVG,
                       inheritedColor: .labelColor,
                       zoom: 1.0)
                .padding(20)
                .onDrag { model.makeDragProvider() }

            if model.renderedSVG == nil && model.errorMessage == nil {
                Text("Type an equation below")
                    .foregroundStyle(.tertiary)
            }
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

                Button {
                    Task { await model.copyToPasteboard() }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(model.renderedSVG == nil)
                .help("Copy as PDF, PNG and SVG at once")

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
                if !model.autoUpdate {
                    Button("Render", action: model.renderNow)
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                Toggle("Auto update", isOn: $model.autoUpdate)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("SVG source", isOn: $model.showSource)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if model.showSource {
                VSplitView {
                    latexField
                    sourceDrawer
                }
            } else {
                latexField
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var latexField: some View {
        TextEditor(text: $model.latex)
            .font(.system(.body, design: .monospaced))
            .padding(6)
            .frame(minHeight: 80)
    }

    private var sourceDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SVG source")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy source", action: model.copySVGSource)
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(model.renderedSVG == nil)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            ScrollView {
                Text(model.renderedSVG.map { SVGDocument.standaloneFile(svg: $0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(minHeight: 80)
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
