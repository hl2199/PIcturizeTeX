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
        .frame(width: 330)
    }

    // MARK: Colour

    private var colorSection: some View {
        Section("Color") {
            Picker("", selection: $model.colorChoice) {
                ForEach(ColorChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if model.colorChoice == .custom {
                // The colour well is the primary control; the CSS field is the
                // escape hatch for named colours and exact values.
                ColorPicker("Color", selection: Binding(
                    get: { Color(nsColor: NSColor(css: model.customColorText) ?? .labelColor) },
                    set: { model.customColorText = $0.cssHexString }
                ))

                HStack(spacing: 6) {
                    Text("CSS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("#0066cc", text: $model.customColorText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                }
                Text("Any CSS colour works here, for example rebeccapurple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Scale

    private var scaleSection: some View {
        Section("Scaling") {
            Picker("", selection: $model.scaleChoice) {
                ForEach(ScaleChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch model.scaleChoice {
            case .standard:
                Text("1 ex = 8 px.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .matchFont:
                Picker("Font", selection: $model.fontFamily) {
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                HStack(spacing: 6) {
                    Text("Size")
                    TextField("", value: $model.fontSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("px")
                }

                Text("The equation is scaled so its x-height matches this font.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .manual:
                HStack(spacing: 6) {
                    Text("1 ex =")
                    TextField("", value: $model.manualPixelsPerEx, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("px")
                }
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
            // A fixed height keeps the sections below from shifting when the
            // caption swaps between the two descriptions.
            Group {
                if model.displayMode {
                    Text("Standalone-equation proportions, as \\[ … \\] gives: "
                         + "full-size fractions, limits above big operators.")
                } else {
                    Text("In-sentence proportions, as $ … $ gives: "
                         + "compact fractions, limits beside big operators.")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
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
