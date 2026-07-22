import AppKit
import LatexCore
import SwiftUI

/// The right-hand pane, set as a native grouped form: quiet, dense, and
/// unmistakably macOS.
struct SettingsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            colorSection
            scaleSection
            renderingSection
            exportSection
            preambleSection
        }
        .formStyle(.grouped)
        .frame(width: 310)
    }

    // MARK: Colour

    private var colorSection: some View {
        Section("Color") {
            Picker("Color", selection: $model.colorChoice) {
                ForEach(ColorChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.colorChoice == .custom {
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(nsColor: NSColor(css: model.customColorText) ?? .labelColor) },
                    set: { model.customColorText = $0.cssHexString }
                ))

                TextField("CSS value", text: $model.customColorText)
                    .font(.body.monospaced())
            }
        }
    }

    // MARK: Scale

    private var scaleSection: some View {
        Section {
            Picker("Mode", selection: $model.scaleChoice) {
                Text("Default (1 ex = 8 px)").tag(ScaleChoice.standard)
                Text("Match a font").tag(ScaleChoice.matchFont)
                Text("Manual").tag(ScaleChoice.manual)
            }

            switch model.scaleChoice {
            case .standard:
                EmptyView()

            case .matchFont:
                Picker("Font", selection: $model.fontFamily) {
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                TextField("Size (px)", value: $model.fontSize, format: .number)

            case .manual:
                TextField("Pixels per ex", value: $model.manualPixelsPerEx, format: .number)
            }
        } header: {
            Text("Scale")
        } footer: {
            if model.scaleChoice == .matchFont {
                Text("The equation is scaled so its x-height matches this font.")
            }
        }
    }

    // MARK: Rendering

    private var renderingSection: some View {
        Section {
            Picker("Style", selection: $model.displayMode) {
                Text("Display").tag(true)
                Text("Inline").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Rendering")
        } footer: {
            Text("Display uses standalone-equation proportions, as \\[ … \\] does; "
                 + "inline uses the compact style of math inside a sentence, as $ … $ does.")
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            Picker("PNG resolution", selection: $model.pngDPI) {
                Text("96 dpi").tag(96.0)
                Text("192 dpi").tag(192.0)
                Text("300 dpi").tag(300.0)
                Text("600 dpi").tag(600.0)
            }

            Picker("Drag format", selection: $model.dragFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("A drag produces one file in this format. "
                 + "Copy puts PDF, PNG and SVG on the clipboard at once.")
        }
    }

    // MARK: Preamble

    private var preambleSection: some View {
        Section {
            TextEditor(text: $model.preamble)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 88)
                .scrollContentBackground(.hidden)
        } header: {
            Text("Macro preamble")
        } footer: {
            Text("Applied to every equation and saved between launches, "
                 + "for example \\newcommand{\\R}{\\mathbb{R}}.")
        }
    }
}

// MARK: - Colour conversion helpers

extension NSColor {
    /// Parses the subset of CSS colours worth round-tripping through the colour
    /// well: `#rgb` and `#rrggbb`.
    convenience init?(css: String) {
        var text = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("#") {
            text.removeFirst()
            if text.count == 3 {
                text = text.map { "\($0)\($0)" }.joined()
            }
            guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
            self.init(srgbRed: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255,
                      alpha: 1)
            return
        }
        return nil
    }
}

extension Color {
    /// `#rrggbb`, which is valid CSS and so safe to write back into the field.
    var cssHexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}
