import AppKit
import LatexCore
import SwiftUI

/// The right-hand pane: everything that changes how the equation looks or is
/// exported.
struct SettingsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                colorSection
                Divider()
                scaleSection
                Divider()
                renderingSection
                Divider()
                exportSection
                Divider()
                preambleSection
            }
            .padding(16)
        }
        .frame(width: 280)
    }

    // MARK: Colour

    private var colorSection: some View {
        Section("Colour") {
            Picker("", selection: $model.colorChoice) {
                ForEach(ColorChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if model.colorChoice == .custom {
                // The colour well is the primary control; the CSS field is the
                // escape hatch for named colours and exact values.
                ColorPicker("Colour", selection: Binding(
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
        Section("Rendering") {
            Picker("", selection: $model.displayMode) {
                Text("Display").tag(true)
                Text("Inline").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Display uses standalone-equation proportions, as \\[ … \\] does; "
                 + "inline uses the compact style of math inside a sentence, as $ … $ does.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section("Export") {
            HStack {
                Text("PNG resolution")
                Spacer()
                Picker("", selection: $model.pngDPI) {
                    Text("96 dpi").tag(96.0)
                    Text("192 dpi").tag(192.0)
                    Text("300 dpi").tag(300.0)
                    Text("600 dpi").tag(600.0)
                }
                .labelsHidden()
                .frame(width: 110)
            }

            HStack {
                Text("Drag exports")
                Spacer()
                Picker("", selection: $model.dragFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            Text("A drag produces one file, so it uses a single format. "
                 + "Copy puts all three on the clipboard at once.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Preamble

    private var preambleSection: some View {
        Section("Macro preamble") {
            TextEditor(text: $model.preamble)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.3)))
            Text("Applied to every equation, and saved between launches. "
                 + "For example \\newcommand{\\R}{\\mathbb{R}}.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A titled group, laid out consistently across the pane.
    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Colour conversion helpers

extension NSColor {
    /// Parses the subset of CSS colours worth round-tripping through the colour
    /// well: `#rgb`, `#rrggbb`, and any name AppKit already knows.
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
