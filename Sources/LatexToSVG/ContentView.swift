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
        .task { await Self.runUIProbeIfRequested() }
    }

    /// Development aid: with UIPROBE_PNG=<path> in the environment, the app
    /// snapshots its own window to that path and exits. Renders via
    /// cacheDisplay, so it works across Spaces and without screen-recording
    /// permission. Inert in normal use.
    @MainActor
    private static func runUIProbeIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["UIPROBE_PNG"] else { return }

        // With UIPROBE_MENUBAR set, capture the menu bar pane instead of the
        // main window. The pane is hosted in a throwaway window because the
        // real popover only exists while the status item is open.
        if ProcessInfo.processInfo.environment["UIPROBE_MENUBAR"] != nil {
            let host = NSWindow(contentViewController:
                NSHostingController(rootView: MenuBarPane(model: AppModel(menuBarLite: true))))
            host.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            host.orderBack(nil)
            try? await Task.sleep(for: .seconds(3))
            capture(host.contentView, to: path)
        } else {
            try? await Task.sleep(for: .seconds(3))
            capture(NSApp.windows.first(where: { $0.isVisible })?.contentView, to: path)
        }
    }

    @MainActor
    private static func capture(_ view: NSView?, to path: String) {
        guard let view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("UIPROBE: no window to capture")
            exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
        print("UIPROBE: wrote \(path)")
        exit(0)
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
            .overlay(alignment: .bottom) { statusBar(zoom: displayZoom(in: geo.size)) }
        }
        .overlay(alignment: .topTrailing) {
            if model.isRendering {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
    }

    /// The sheet shows the equation at its true export size -- the scaling
    /// controls are WYSIWYG -- shrinking only when the equation is larger than
    /// the pane. It is never magnified: an equation that looks too small here
    /// will be exactly that small in the exported file, and the honest remedy
    /// is a larger scale setting.
    private func displayZoom(in available: CGSize) -> Double {
        guard model.pixelWidth > 0, model.pixelHeight > 0 else { return 1 }
        let maxWidth = max(available.width - 100, 160)
        let maxHeight = max(available.height - 150, 90)
        return min(min(maxWidth / model.pixelWidth, maxHeight / model.pixelHeight), 1)
    }

    private func paperSheet(available: CGSize) -> some View {
        let zoom = displayZoom(in: available)

        return Group {
            if model.renderedSVG != nil {
                SVGPreview(svg: model.renderedSVG)
                    .frame(width: model.pixelWidth * zoom,
                           height: model.pixelHeight * zoom)
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

    private func statusBar(zoom: Double) -> some View {
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
                         + "\(SVGDocument.format(model.pixelHeight)) px"
                         + (abs(zoom - 1) > 0.01 ? "  ·  shown at \(Int((zoom * 100).rounded()))%" : ""))
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
