import AppKit
import LatexCore
import SwiftUI

/// The right-hand pane. Laid out by hand as grouped-style cards rather than a
/// SwiftUI `Form`: the grouped form imposes its own row structure -- labels
/// synthesised from placeholders, controls re-aligned to the trailing edge --
/// which fights the static radio-row design. Hand layout is deterministic.
struct SettingsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                card("Color") { colorRows }
                card("Scale") { scaleRows }
                card("Rendering") { renderingRows }
                card("Export") { exportRows }
                card("Macro preamble") { preambleRows }
            }
            .padding(16)
        }
        .frame(width: 330)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Colour

    @ViewBuilder
    private var colorRows: some View {
        radioRow("Black", selected: model.colorChoice == .black) {
            model.colorChoice = .black
        }

        radioRow("White", selected: model.colorChoice == .white) {
            model.colorChoice = .white
        }

        radioRow("Custom", selected: model.colorChoice == .custom) {
            model.colorChoice = .custom
        } trailing: {
            // The system colour panel carries its own hex entry too. Picking a
            // colour or editing the field selects Custom, so neither control
            // is ever dead to a click.
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(css: model.customColorText) ?? .labelColor) },
                set: {
                    model.customColorText = $0.cssHexString
                    model.colorChoice = .custom
                }
            ))
            .labelsHidden()
        } detail: {
            // Pushed to the trailing edge so the field sits directly beneath
            // the colour well above it.
            Spacer(minLength: 0)
            TextField("", text: Binding(
                get: { model.customColorText },
                set: { model.customColorText = $0; model.colorChoice = .custom }
            ), prompt: Text("#0066cc"))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
        }
    }

    // MARK: Scale

    @ViewBuilder
    private var scaleRows: some View {
        radioRow("Default (1 ex = 8 px)", selected: model.scaleChoice == .standard) {
            model.scaleChoice = .standard
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
            // A fixed width: .fixedSize() would size the popup to its widest
            // menu item, and font family names run long.
            .frame(width: 150)

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

    // MARK: Rendering

    @ViewBuilder
    private var renderingRows: some View {
        Picker("", selection: $model.displayMode) {
            Text("Display").tag(true)
            Text("Inline").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        // A fixed height keeps the cards below from shifting when the caption
        // swaps between the two descriptions.
        Group {
            if model.displayMode {
                Text("Standalone-equation proportions, as \\[ … \\] gives: "
                     + "full-size fractions, limits above big operators.")
            } else {
                Text("In-sentence proportions, as $ … $ gives: "
                     + "compact fractions, limits beside big operators.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
    }

    // MARK: Export

    @ViewBuilder
    private var exportRows: some View {
        labeledPopup("PNG resolution") {
            Picker("", selection: $model.pngDPI) {
                Text("96 dpi").tag(96.0)
                Text("192 dpi").tag(192.0)
                Text("300 dpi").tag(300.0)
                Text("600 dpi").tag(600.0)
            }
        }

        labeledPopup("Drag format") {
            Picker("", selection: $model.dragFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    // MARK: Preamble

    @ViewBuilder
    private var preambleRows: some View {
        TextEditor(text: $model.preamble)
            .font(.system(.caption, design: .monospaced))
            .frame(height: 88)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25)))

        Text("Applied to every equation and saved between launches, "
             + "for example \\newcommand{\\R}{\\mathbb{R}}.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Layout primitives

    /// A grouped-style section: small header, rounded card, quiet background.
    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternarySystemFill)))
        }
    }

    /// Label at the leading edge, pop-up hugging the trailing edge.
    private func labeledPopup<P: View>(_ label: String,
                                       @ViewBuilder popup: () -> P) -> some View {
        HStack {
            Text(label)
            Spacer()
            popup()
                .labelsHidden()
                .fixedSize()
        }
    }

    /// A radio option whose controls are always visible, so selecting never
    /// reshapes the card. A compact control sits inline at the trailing edge;
    /// anything wider goes on a `detail` line beneath the title, indented to
    /// the title's left edge. Controls stay live -- using one selects its own
    /// option -- and inactive rows are dimmed, never disabled.
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

                trailing()
                    .opacity(selected ? 1 : 0.55)
            }

            HStack(spacing: 6) {
                detail()
                    .opacity(selected ? 1 : 0.55)
            }
            .padding(.leading, 20)
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
