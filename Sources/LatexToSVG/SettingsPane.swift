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
                // The system colour panel carries its own hex entry, so the
                // well is the only control needed here. Picking a colour also
                // selects Custom, so the well is never dead to a click.
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(css: model.customColorText) ?? .labelColor) },
                    set: {
                        model.customColorText = $0.cssHexString
                        model.colorChoice = .custom
                    }
                ))
                .labelsHidden()
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
            } detail: {
                Picker("", selection: Binding(
                    get: { model.fontFamily },
                    set: { model.fontFamily = $0; model.scaleChoice = .matchFont }
                )) {
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)

                TextField("", value: Binding(
                    get: { model.fontSize },
                    set: { model.fontSize = $0; model.scaleChoice = .matchFont }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text("px")
                    .foregroundStyle(.secondary)
            }

            radioRow("Manual", selected: model.scaleChoice == .manual) {
                model.scaleChoice = .manual
            } detail: {
                Text("1 ex =")
                    .foregroundStyle(.secondary)
                TextField("", value: Binding(
                    get: { model.manualPixelsPerEx },
                    set: { model.manualPixelsPerEx = $0; model.scaleChoice = .manual }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A radio option whose controls are always visible, so selecting never
    /// reshapes the form. A compact control sits inline at the trailing edge;
    /// anything wider goes on a `detail` line beneath the title, indented to a
    /// shared left edge so the columns align. Controls respond only while
    /// their option is the selected one.
    private func radioRow<Trailing: View, Detail: View>(
        _ title: String,
        selected: Bool,
        select: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder detail: () -> Detail = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: select) {
                    HStack(spacing: 6) {
                        Image(systemName: selected ? "inset.filled.circle" : "circle")
                            .foregroundStyle(selected ? Theme.accent : Color.secondary)
                            .frame(width: 14)
                        Text(title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // Controls stay live: using one selects its own option, so a
                // click is never dead. Dimming still marks the inactive rows.
                trailing()
                    .opacity(selected ? 1 : 0.55)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                detail()
                    .opacity(selected ? 1 : 0.55)
            }
            .padding(.leading, 20)
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
