import AppKit
import LatexCore
import SwiftUI

/// The menu bar companion: a compact, always-display-mode equation card.
///
/// Runs on its own `AppModel` instance, so it works with the main window
/// closed and its settings never fight the main window's. Drag-out and
/// right-click copy reuse the same machinery as the desk.
/// Receives NSColorPanel changes. Kept alive for the app's lifetime because
/// the panel holds its target unsafely -- if the target deallocated while the
/// panel was open, the next colour change would touch freed memory.
@MainActor
final class MenuBarColorPanelTarget: NSObject {
    static let shared = MenuBarColorPanelTarget()
    var onColor: ((NSColor) -> Void)?

    @objc func colorChanged(_ sender: NSColorPanel) {
        onColor?(sender.color)
    }
}

/// A colour well that works inside the menu bar pane.
///
/// SwiftUI's ColorPicker silently does nothing there: it orders the shared
/// colour panel front, but macOS only shows that panel for the active app,
/// and a status-item window never activates the app. This well activates the
/// app explicitly and drives NSColorPanel by hand.
struct MenuBarColorWell: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            let panel = NSColorPanel.shared
            panel.showsAlpha = false
            panel.color = model.effectiveColor
            MenuBarColorPanelTarget.shared.onColor = { [weak model] color in
                guard let model, let srgb = color.usingColorSpace(.sRGB) else { return }
                model.customColorText = String(format: "#%02x%02x%02x",
                                               Int(round(srgb.redComponent * 255)),
                                               Int(round(srgb.greenComponent * 255)),
                                               Int(round(srgb.blueComponent * 255)))
                model.colorChoice = .custom
            }
            panel.setTarget(MenuBarColorPanelTarget.shared)
            panel.setAction(#selector(MenuBarColorPanelTarget.colorChanged(_:)))
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } label: {
            // Always the colour the equation currently renders in, whichever
            // mode is selected.
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: model.effectiveColor))
                .frame(width: 38, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .help("Choose a custom color")
    }
}

struct MenuBarPane: View {
    @Bindable var model: AppModel
    /// Shared with the app scene's MenuBarExtra(isInserted:) and the settings
    /// toggle, so removal here can be undone from the main window.
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    private let paneWidth: CGFloat = 400
    private let previewHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview

            TextEditor(text: $model.latex)
                .font(.system(.callout, design: .monospaced))
                .frame(height: 96)
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

                MenuBarColorWell(model: model)
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

            HStack {
                Button("Remove from menu bar") {
                    showMenuBarExtra = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(.caption)
                Spacer()
                Text("Restore it in the app's settings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
