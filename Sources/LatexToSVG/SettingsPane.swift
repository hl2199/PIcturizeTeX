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

    /// Every option owns one permanent row with its controls inline, so
    /// selecting an option never adds or removes rows -- the layout is static.
    private var colorSection: some View {
        Section("Color") {
            radioRow("Black", selected: model.colorChoice == .black) {
                model.colorChoice = .black
            } trailing: {
                EmptyView()
            }

            radioRow("White", selected: model.colorChoice == .white) {
                model.colorChoice = .white
            } trailing: {
                EmptyView()
            }

            radioRow("Custom", selected: model.colorChoice == .custom) {
                model.colorChoice = .custom
            } trailing: {
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(css: model.customColorText) ?? .labelColor) },
                    set: { model.customColorText = $0.cssHexString }
                ))
                .labelsHidden()

                TextField("#0066cc", text: $model.customColorText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 110)
            }
        }
    }

    // MARK: Scale

    private var scaleSection: some View {
        Section("Scale") {
            radioRow("Default (1 ex = 8 px)", selected: model.scaleChoice == .standard) {
                model.scaleChoice = .standard
            } trailing: {
                EmptyView()
            }

            radioRow("Match a font", selected: model.scaleChoice == .matchFont) {
                model.scaleChoice = .matchFont
            } trailing: {
                Picker("", selection: $model.fontFamily) {
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)

                TextField("", value: $model.fontSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                Text("px")
                    .foregroundStyle(.secondary)
            }

            radioRow("Manual", selected: model.scaleChoice == .manual) {
                model.scaleChoice = .manual
            } trailing: {
                Text("1 ex =")
                    .foregroundStyle(.secondary)
                TextField("", value: $model.manualPixelsPerEx, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A radio option whose controls live inline on the same row: clicking the
    /// title selects the option, and the trailing controls stay put whether or
    /// not it is selected.
    private func radioRow<Trailing: View>(_ title: String,
                                          selected: Bool,
                                          select: @escaping () -> Void,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 6) {
                    Image(systemName: selected ? "inset.filled.circle" : "circle")
                        .foregroundStyle(selected ? Theme.accent : Color.secondary)
                    Text(title)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // The controls stay visible either way -- static layout -- but only
            // respond while their option is the active one.
            trailing()
                .disabled(!selected)
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
